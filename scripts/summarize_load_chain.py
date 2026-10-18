#!/usr/bin/env python3
"""Reproduce partial US load-chain signature/decompiler evidence, not game codegen."""
import csv
import hashlib
import json
from pathlib import Path
import struct
import subprocess

from match_sdk_window import classify, load_embedded, match_prefix, verify_windows

ROOT = Path(__file__).resolve().parents[1]
FACTS = ROOT/'analysis/scout/slus_20486'
DATA = ROOT/'game/working/slus_20486/load_chain'
OUT = ROOT/'builddir/logs/us-load-chain'
HEADER = ROOT/'tools/ps2recomp/PS2Recomp/ps2xAnalyzer/include/ps2recomp/sce_symbol_database_data.h'
HEADER_SHA = '0fdd1168a815c8af2529cae9076ae813a1304c5c3a41e48d88d38e21e7b5833d'


def main():
    manifest = json.loads((FACTS/'load_chain_windows.json').read_text())
    n = verify_windows(DATA, manifest)
    if hashlib.sha256(HEADER.read_bytes()).hexdigest() != HEADER_SHA:
        raise ValueError('SDK database header changed; review the pin before matching')
    database = load_embedded(HEADER)
    functions = json.loads((OUT/'functions.json').read_text())
    by_entry = {int(f['entry'],16): f for f in functions}
    entries = []
    for window in manifest['windows']:
        raw = (DATA/(window['name']+'.bin')).read_bytes()
        base = int(window['va'],16)
        for offset in window['entry_offsets']:
            va = base+offset
            f = by_entry[va]
            assert base <= int(f['body_min'],16) <= int(f['body_max'],16) < base+len(raw)
            candidates = match_prefix(raw[offset:], database, va)
            entries.append({'entry':f'0x{va:08x}', 'window':window['name'],
                            'signature_status':classify(candidates), 'candidates':candidates,
                            'ghidra_inferred_function':f})
    assert len(entries) == len(by_entry) == 4
    core = next(e for e in entries if e['entry']=='0x0010b970')
    assert core['signature_status']=='unique_full_hash_match'
    assert {c['name'] for c in core['candidates']}=={'_sceSifLoadModule'}
    thin = next(e for e in entries if e['entry']=='0x0010bb98')
    assert thin['signature_status']=='short_signature_candidate'
    # Independent upstream native scanner on a clearly labeled DERIVED fragment ELF.
    # It never passes the full-game target gate and is never used for game codegen.
    raw=(DATA/'load_core.bin').read_bytes();base=0x10b970
    header=struct.pack('<16sHHIIIIIHHHHHH',b'\x7fELF\x01\x01\x01'+bytes(9),2,8,1,base,52,0,0x20924000,52,32,1,40,0,0)
    ph=struct.pack('<8I',1,256,base,base,len(raw),len(raw),5,16)
    fragment=DATA/'derived_load_core.elf'
    fragment.write_bytes((header+ph).ljust(256,b'\0')+raw)
    native_csv=DATA/'partial_analyzer.csv'
    native_csv.unlink(missing_ok=True)
    with (OUT/'native-analyzer.log').open('w') as log:
        subprocess.run([str(ROOT/'tools/ps2recomp/bin/mvc2_analyzer_export'),str(fragment),
                        str(DATA/'partial_analyzer.toml'),str(native_csv)],
                       stdout=log,stderr=log,check=True,timeout=120)
    with native_csv.open() as stream: native=list(csv.DictReader(stream))
    assert any(r['Name']=='_sceSifLoadModule' and int(r['Start'],16)==base for r in native)
    with (OUT/'disassembly.tsv').open() as stream: rows=list(csv.DictReader(stream,delimiter='\t'))
    bind = (DATA/'load_bind.bin').read_bytes()
    # Actual US LUI/ORI and JAL words, not a guessed SID from a filename.
    assert struct.unpack_from('<I',bind,40)[0] == 0x3c058000
    assert struct.unpack_from('<I',bind,48)[0] == 0x34a50006
    assert struct.unpack_from('<I',bind,52)[0] == 0x0c041b26
    sid=((struct.unpack_from('<I',bind,40)[0]&0xffff)<<16)|(struct.unpack_from('<I',bind,48)[0]&0xffff)
    assert struct.unpack_from('<I',(DATA/'load_entry.bin').read_bytes(),4)[0] == 0x0000402d
    assert struct.unpack_from('<I',raw,20)[0] == 0x0100982d  # t0 -> s3
    assert struct.unpack_from('<I',raw,448)[0] == 0x0260282d  # s3 -> RPC a1
    prior=json.loads((FACTS/'code_windows.json').read_text())
    helper=json.loads((FACTS/'helper_window.json').read_text())
    intervals=sorted((int(w['va'],16),int(w['va'],16)+w['bytes']) for w in prior['windows']+[helper]+manifest['windows'])
    assert all(a[1]<=b[0] for a,b in zip(intervals,intervals[1:]))
    previous_insns=json.loads((FACTS/'window_call_facts.json').read_text())['decoded_instructions']+json.loads((FACTS/'helper_call_facts.json').read_text())['decoded_instructions']
    report={'serial':manifest['serial'], 'elf_sha256':manifest['elf_sha256'],
            'scope':'PARTIAL US windows only; not full ELF analysis or actual module execution',
            'sdk_database':{'upstream_commit':'eb8688b2fd191129f103a39543002c005b33409c','header_sha256':HEADER_SHA},
            'captured_window_bytes':n,'decoded_window_instructions':len(rows),'entries':entries,
            'native_fragment_scan':{'derived_elf':True,'original_game_file_modified':False,'records':native,
                                    'note':'Native scanner extends matching signature over trailing NOPs. This is not the original full ELF.'},
            'all_local_window_scope':{'windows':len(intervals),'nonoverlapping_bytes':sum(hi-lo for lo,hi in intervals),'decoded_instructions':previous_insns+len(rows)},
            'protocol_observations':{
                'loadfile_bind_sid':f'0x{sid:08x}',
                'sid_instruction_sites':['0x0010b1c0','0x0010b1c8'],
                'bind_call_site':'0x0010b1cc','bind_call_target':'0x00106c98',
                'bind_target_name_source':'sceSifBindRpc annotation in matched _lf_bind signature; target body not hashed here',
                'client_address':'0x004c7080','send_and_receive_buffer':'0x004c6e80',
                'module_rpc_call_site':'0x0010bb4c','rpc_target':'0x00106e68',
                'rpc_target_name_source':'sceSifCallRpc annotation shared by strong core/bind matches; target body not hashed here',
                'load_request_send_bytes':512,'load_request_receive_bytes':8,
                'bootstrap_probe_function':255,'bootstrap_probe_receive_bytes':4,
                'thin_entry_sets_t0_zero':True,
                'ordinary_load_rpc_function':0,
                'function_zero_evidence':'Thin t0=0; core preserves t0 in s3 and moves s3 into a1 at 0x0010bb30. Static path only.',
                'request_layout_inferred':{'arg_length_offset':0,'path_offset':8,'path_capacity':252,'arguments_offset':260,'arguments_capacity':252},
                'source':'Bounded Ghidra decompilation, instruction operands and normalized SDK signature annotations; no runtime trace',
                'tsnddrv_own_rpc_sid_established':False},
            'runtime_source_review':{'pin':'eb8688b2fd191129f103a39543002c005b33409c',
                'path':'ps2xIOP/src/iop_subsystem.cpp',
                'finding':'Core service factories are MCSERV/DBCMAN/LIBSD, not LOADFILE. canBindRpc needs a route or an actually registered emulated server. Runtime handling of this guest loader path remains untested; no fake descriptor/stub was added.'},
            'limitations':['SDK signature matches are relative to the pinned database, not exact game SDK-version proof.',
                           'Thin32B trampoline has only230 unmasked bits: short candidate, no automatic name assignment.',
                           'Relocation annotations suggest callee names but do not independently hash their target bodies.',
                           'Partial decompiler types/ABI/globals are inferred; no RPC response or runtime load order observed.'],
            'full_us_elf_analysis_complete':False,'whole_game_cpp_generated':False}
    (FACTS/'load_chain_facts.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f'Partial load chain: {n} verified bytes, {len(rows)} instructions, 4 bounded entries; native core signature corroborated')


if __name__ == '__main__':
    main()
