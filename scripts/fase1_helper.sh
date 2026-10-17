#!/usr/bin/env bash
# SHA-gated partial analysis; never bypasses full-game target verification.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh >/dev/null
source scripts/target.sh
DIR="$MVC2_ROOT/game/working/slus_20486/helper"
python3 - "$DIR" "$MVC2_TARGET_SHA256" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1]);m=json.loads(pathlib.Path('analysis/scout/slus_20486/helper_window.json').read_text())
assert m['serial']=='SLUS_204.86' and m['elf_sha256']==sys.argv[2] and m['va']=='0x003dcad0'
b=(p/'module_wrapper.bin').read_bytes()
assert len(b)==m['bytes'] and hashlib.sha256(b).hexdigest()==m['sha256']
(p/'windows.tsv').write_text(f"module_wrapper\t3dcad0\t{len(b)}\t{m['sha256']}\n")
PY
mkdir -p builddir/us-helper-project builddir/logs
rm -f builddir/logs/us-helper-pseudocode.c builddir/logs/us-helper-function.json
timeout 300 tools/ghidra/ghidra_12.0.2_PUBLIC/support/analyzeHeadless \
  "$MVC2_ROOT/builddir/us-helper-project" us_helper \
  -import "$DIR/module_wrapper.bin" -loader BinaryLoader -loader-baseAddr 0x3dcad0 \
  -processor r5900:LE:32:default -noanalysis -scriptPath "$MVC2_ROOT/scripts/ghidra" \
  -postScript DisassembleWindows.java "$DIR" "$MVC2_ROOT/builddir/logs/us-helper-disassembly.tsv" \
  -postScript DecompileWindow.java 003dcad0 "$MVC2_ROOT/builddir/logs/us-helper-pseudocode.c" \
    "$MVC2_ROOT/builddir/logs/us-helper-function.json" \
  -deleteProject > builddir/logs/us-helper-ghidra.log 2>&1
grep -q 'Partial window decompilation exported' builddir/logs/us-helper-ghidra.log
python3 - <<'PY'
import csv,json,pathlib
p=pathlib.Path('analysis/scout/slus_20486')
f=json.loads(pathlib.Path('builddir/logs/us-helper-function.json').read_text())
with open('builddir/logs/us-helper-disassembly.tsv') as h:rows=list(csv.DictReader(h,delimiter='\t'))
assert len(rows)==96
lo,hi=int(f['body_min'],16),int(f['body_max'],16)
calls=[{'site':'0x'+r['va'],'target':'0x'+r['flows']} for r in rows if 'CALL' in r['flow_type'] and lo<=int(r['va'],16)<=hi]
assert sum(c['target']=='0x0010bb98' for c in calls)==2
assert any(c['target']=='0x0011eb60' for c in calls)
f.update({'serial':'SLUS_204.86','tool':'Ghidra 12.0.2 + EE 2.1.38','window_bytes':384,'decoded_instructions':96,'calls_in_inferred_function':calls,'diagnostic_string':{'va':'0x004ba4f0','text':"Can't load module %s\n",'source':'separate SQL C-string extraction from hash-verified US ELF'},'interpretation':'Module-load retry wrapper candidate. Static decompiler suggests arg4=0 retries while result<0; finite arg4 retries stop on positive result, otherwise diagnostic. ABI/SDK name not verified.','full_elf_analysis_complete':False})
(p/'helper_call_facts.json').write_text(json.dumps(f,indent=2)+'\n')
print(f"Helper window: 96 instructions, {len(calls)} direct calls in inferred function; no SDK name assigned")
PY
