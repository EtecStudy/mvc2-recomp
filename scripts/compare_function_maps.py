#!/usr/bin/env python3
"""Compare actual exported maps, not arbitrary hexadecimal tokens in TOML.

Ghidra remains authoritative. Its CSV can include code labels and non-contiguous
bodies; Size need not equal End-Start. Disagreements are reported, never merged
into SDK identities or automatically patched/stubbed.
"""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile
import tomllib


def executable_ranges(elf):
    if len(elf) < 52 or elf[:7] != b'\x7fELF\x01\x01\x01':
        raise ValueError('Expected ELF32 little-endian version 1')
    typ, machine = struct.unpack_from('<HH', elf, 16)
    if (typ, machine) != (2, 8) or struct.unpack_from('<I', elf, 20)[0] != 1:
        raise ValueError('Expected MIPS ET_EXEC')
    entry, phoff = struct.unpack_from('<II', elf, 24)
    phsize, count = struct.unpack_from('<HH', elf, 42)
    if phsize < 32 or not count or phoff < 52 or phoff + phsize * count > len(elf):
        raise ValueError('Invalid program-header bounds')
    ranges = []
    for i in range(count):
        kind, offset, va, _, filesz, memsz, flags, _ = struct.unpack_from('<8I', elf, phoff + phsize*i)
        if kind != 1:
            continue
        if filesz > memsz or offset + filesz > len(elf) or va + memsz > 2**32:
            raise ValueError('Invalid load segment bounds')
        if flags & 1 and filesz:
            ranges.append((va, va + filesz))
    if not any(lo <= entry < hi for lo, hi in ranges):
        raise ValueError('ELF entry is not backed by executable file bytes')
    return entry, ranges


def read_map(path, ranges):
    result = {}
    with path.open(newline='') as stream:
        rows = csv.DictReader(stream)
        if rows.fieldnames != ['Name', 'Start', 'End', 'Size']:
            raise ValueError(f'{path}: expected Name,Start,End,Size header')
        for n, row in enumerate(rows, 2):
            try:
                if None in row or any(v is None for v in row.values()) or not row['Name'].strip():
                    raise ValueError('incomplete CSV row')
                start, end, size = int(row['Start'], 16), int(row['End'], 16), int(row['Size'])
                if start % 4 or end % 4 or size % 4 or not 0 < size <= end-start:
                    raise ValueError('invalid instruction range/body size')
                if not any(lo <= start < end <= hi for lo, hi in ranges):
                    raise ValueError('range not backed by one executable file segment')
                if start in result:
                    raise ValueError('duplicate start')
                result[start] = dict(name=row['Name'], end=end, size=size)
            except ValueError as e:
                raise ValueError(f'{path}:{n}: {e}') from e
    if not result:
        raise ValueError(f'{path}: empty map')
    return result


def check_config(path, elf_path, csv_path=None, count=None):
    doc = tomllib.loads(path.read_text())
    general = doc.get('general')
    if not isinstance(general, dict):
        raise ValueError(f'{path}: missing/invalid general table')
    inp = general.get('input')
    # Upstream resolves input paths from the process working directory.
    if not isinstance(inp, str) or Path(inp).resolve() != elf_path.resolve():
        raise ValueError(f'{path}: config input is not the analyzed ELF')
    if csv_path is not None:
        mapping = doc['general'].get('ghidra_output')
        if not isinstance(mapping, str) or Path(mapping).resolve() != csv_path.resolve():
            raise ValueError(f'{path}: config refers to a different Ghidra map')
        meta = doc.get('ghidra_export', {})
        if not isinstance(meta, dict):
            raise ValueError(f'{path}: invalid export metadata')
        if any(type(meta.get(k)) is not int for k in ('function_count', 'code_label_count', 'csv_record_count')):
            raise ValueError(f'{path}: export counts must be integers')
        if meta['function_count'] <= 0 or meta['code_label_count'] < 0:
            raise ValueError(f'{path}: no discovered functions or negative label count')
        if meta.get('csv_record_count') != count:
            raise ValueError(f'{path}: missing/mismatched CSV record count')
        if meta.get('function_count', -1) + meta.get('code_label_count', -1) != count:
            raise ValueError(f'{path}: function/label totals differ from CSV')
    return doc


def compare(elf_path, gh_csv, an_csv, gh_toml, an_toml):
    raw = elf_path.read_bytes()
    entry, ranges = executable_ranges(raw)
    gh, an = read_map(gh_csv, ranges), read_map(an_csv, ranges)
    gd = check_config(gh_toml, elf_path, gh_csv, len(gh))
    check_config(an_toml, elf_path)
    for name, mapping in [('Ghidra', gh), ('analyzer', an)]:
        if not any(start <= entry < rec['end'] for start, rec in mapping.items()):
            raise ValueError(f'{name}: entry is not covered by its map')
    common = sorted(gh.keys() & an.keys())
    mismatches = [dict(start=f'0x{s:08x}', ghidra_end=f"0x{gh[s]['end']:08x}",
                       analyzer_end=f"0x{an[s]['end']:08x}")
                  for s in common if gh[s]['end'] != an[s]['end']]
    hashes = {name: hashlib.sha256(p.read_bytes()).hexdigest() for name, p in
              [('ghidra_csv', gh_csv), ('analyzer_csv', an_csv), ('ghidra_toml', gh_toml), ('analyzer_toml', an_toml)]}
    return {
        'schema': 1,
        'elf': dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(), entry=f'0x{entry:08x}'),
        'input_sha256': hashes,
        'ghidra_records': len(gh),
        'ghidra_functions': gd['ghidra_export']['function_count'],
        'ghidra_code_labels': gd['ghidra_export']['code_label_count'],
        'analyzer_records': len(an),
        'common_starts': len(common),
        'same_end_at_common_start': len(common)-len(mismatches),
        'boundary_disagreements': mismatches,
        'ghidra_only_starts': [f'0x{s:08x}' for s in sorted(gh.keys()-an.keys())],
        'analyzer_only_starts': [f'0x{s:08x}' for s in sorted(an.keys()-gh.keys())],
        'entry_covered_by_both': True,
        'limitations': [
            'Ghidra CSV includes functions and executable labels; analyzer map is independently discovered.',
            'Equal starts/end extents do not prove semantic equivalence, SDK identity or execution.',
            'Ghidra body Size may be smaller than End-Start; boundaries are compared separately.',
            'Disagreements are not merged and do not create stubs/patches.'
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('elf', 'ghidra_csv', 'analyzer_csv', 'ghidra_toml', 'analyzer_toml', 'output'):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    try:
        result = compare(args.elf, args.ghidra_csv, args.analyzer_csv, args.ghidra_toml, args.analyzer_toml)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix='.map-comparison-', dir=args.output.parent)
        try:
            with os.fdopen(fd, 'w') as f:
                json.dump(result, f, indent=2)
                f.write('\n')
            os.replace(tmp, args.output)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
    except (ValueError, OSError) as e:
        parser.exit(1, f'Map cross-check refused: {e}\n')
    print(f"Map cross-check: Ghidra={result['ghidra_records']} records, analyzer={result['analyzer_records']}, common starts={result['common_starts']}, boundary disagreements={len(result['boundary_disagreements'])}")


if __name__ == '__main__':
    main()
