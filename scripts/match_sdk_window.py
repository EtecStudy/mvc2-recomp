#!/usr/bin/env python3
"""Full relocation-normalized SDK hashes at known bounded-window entries.

Not a whole-ELF scan. Does not assign names, create stubs, infer an exact SDK
version or prove runtime behavior. SHA-256 verifies original window bytes;
the database's SHA-1 is only a normalized signature comparison.
"""
import hashlib
import json
from pathlib import Path
import re
import struct

MASKS = {'NONE': 0xffffffff, 'MIPS_26': 0xfc000000, 'MIPS_32': 0,
         'MIPS_HI16': 0xffff0000, 'MIPS_LO16': 0xffff0000,
         'MIPS_GPREL16': 0xffff0000, 'MIPS_LITERAL': 0xffff0000}


def load_embedded(header):
    text = header.read_text()
    try:
        segment = text.split('kSymbolsJsonChunks[] = {', 1)[1].split('    };', 1)[0]
    except IndexError as e:
        raise ValueError('Embedded symbols array not found') from e
    chunks = re.findall(r'R"PS2SDB\((.*?)\)PS2SDB", (\d+)\}', segment, re.S)
    if not chunks or any(len(t.encode()) != int(n) for t, n in chunks):
        raise ValueError('Embedded symbol chunk length mismatch')
    return json.loads(''.join(t for t, _ in chunks))


def normalize(data, relocations):
    result = bytearray(data)
    bits = len(result)*8
    seen = set()
    for offset, relocation in relocations.items():
        offset = int(offset)
        typ = relocation['type']
        if typ not in MASKS:
            raise ValueError(f'Unsupported relocation type: {typ}')
        if offset % 4 or offset < 0 or offset+4 > len(result) or offset in seen:
            raise ValueError('Invalid/overlapping relocation offset')
        seen.add(offset)
        mask = MASKS[typ]
        word = struct.unpack_from('<I', result, offset)[0]
        struct.pack_into('<I', result, offset, word & mask)
        bits -= 32-mask.bit_count()
    return bytes(result), bits


def match_prefix(data, database, va):
    candidates = []
    for library, names in database.items():
        for name, hashes in names.items():
            for digest, variants in hashes.items():
                for variant, record in variants.items():
                    n = record['size']
                    if record['type'] != 'FUNCTION' or n <= 0 or n % 4 or n > len(data):
                        continue
                    normalized, bits = normalize(data[:n], record.get('relocations', {}))
                    if hashlib.sha1(normalized).hexdigest() != digest:
                        continue
                    calls = []
                    for offset, relocation in record.get('relocations', {}).items():
                        if relocation['type'] != 'MIPS_26':
                            continue
                        offset = int(offset)
                        word = struct.unpack_from('<I', data, offset)[0]
                        if word >> 26 not in (2, 3):
                            raise ValueError('MIPS_26 match is not a J/JAL instruction')
                        pc = va+offset
                        target = ((pc+4) & 0xf0000000) | ((word & 0x03ffffff) << 2)
                        calls.append({'site': f'0x{pc:08x}', 'target': f'0x{target:08x}',
                                      'database_symbol_annotation': relocation['symbol'],
                                      'target_body_hash_verified_by_this_record': False})
                    candidates.append({'library': library, 'name': name, 'signature_bytes': n,
                                       'normalized_sha1': digest, 'variant': variant,
                                       'unmasked_bits': bits, 'database_versions': record.get('versions', []),
                                       'annotated_direct_transfers': calls})
    return sorted(candidates, key=lambda x: (x['library'], x['name'], x['signature_bytes'], x['variant']))


def classify(candidates):
    identities = {(c['library'], c['name']) for c in candidates}
    if not identities:
        return 'no_match'
    if len(identities) != 1:
        return 'ambiguous_identity'
    return 'unique_full_hash_match' if max(c['unmasked_bits'] for c in candidates) >= 256 else 'short_signature_candidate'


def verify_windows(root, manifest):
    total = 0
    for w in manifest['windows']:
        if not re.fullmatch(r'[a-z_]+', w['name']):
            raise ValueError('Unsafe window filename')
        b = (root/(w['name']+'.bin')).read_bytes()
        if len(b) != w['bytes'] or hashlib.sha256(b).hexdigest() != w['sha256']:
            raise ValueError(f"Unverified window: {w['name']}")
        for off in w['entry_offsets']:
            if type(off) is not int or off < 0 or off % 4 or off >= len(b):
                raise ValueError('Invalid entry offset')
        total += len(b)
    return total
