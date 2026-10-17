#!/usr/bin/env python3
"""Summarize only direct-call/address facts from the partial US Ghidra pass."""
import collections
import csv
import json
from pathlib import Path

p = Path('analysis/scout/slus_20486')
with Path('builddir/logs/us-window-disassembly.tsv').open() as f:
    rows = list(csv.DictReader(f, delimiter='\t'))
by = collections.Counter(r['window'] for r in rows)
assert dict(by) == {'boot': 32, 'usb_init': 71, 'audio_init': 80, 'network_init': 63}, by
assert len(rows) == 246
refs = json.loads((p / 'module_xref_candidates.json').read_text())
lookup = {int(r['va'], 16): r for r in rows}
checked = []
for x in refs['refs']:
    site = int(x['site'], 16)
    if site in lookup:
        assert lookup[site]['mnemonic'] == 'addiu'
        assert lookup[int(x['lui'], 16)]['mnemonic'] == 'lui'
        checked.append(x['site'])
calls = [{'window': r['window'], 'site': '0x' + r['va'], 'target': '0x' + r['flows']}
         for r in rows if 'CALL' in r['flow_type']]
common = [r for r in calls if r['target'] == '0x003dcad0']
assert len(common) == 11
result = {
    'serial': 'SLUS_204.86', 'elf_sha256': refs['elf_sha256'],
    'tool': 'Ghidra 12.0.2 + EmotionEngine 2.1.38, r5900:LE:32:default',
    'scope': 'Four SHA-gated windows, 992 bytes. Partial disassembly only; not full ELF analysis. Window-end branches may lack delay slots and remain undecoded.',
    'decoded_instructions': len(rows), 'instructions_by_window': dict(by),
    'lui_addiu_candidate_sites_confirmed_as_instructions': checked,
    'direct_calls': calls, 'common_module_call_target': '0x003dcad0',
    'common_target_calls': len(common),
    'limitations': [
        'Callee SDK name is not verified.',
        'Calls and nearby path setup are static evidence only; no execution or global load order proven.',
        'No authoritative function map, full-game TOML or game C++ generation completed.',
    ],
}
(p / 'window_call_facts.json').write_text(json.dumps(result, indent=2) + '\n')
print(f'Partial US disassembly: {len(rows)} instructions, {len(checked)} candidate sites decoded, {len(common)} calls to shared callee')
