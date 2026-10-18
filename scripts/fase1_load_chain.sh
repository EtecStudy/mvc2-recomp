#!/usr/bin/env bash
# Actual US bounded-window evidence, NOT full ELF analysis/codegen.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh >/dev/null
source scripts/target.sh
DIR="$MVC2_ROOT/game/working/slus_20486/load_chain"
OUT="$MVC2_ROOT/builddir/logs/us-load-chain"
mkdir -p "$OUT" builddir/us-load-chain-project
python3 - "$DIR" "$MVC2_TARGET_SHA256" <<'PY'
import json,pathlib,sys
sys.path.insert(0,'scripts')
from match_sdk_window import verify_windows
p=pathlib.Path(sys.argv[1]);m=json.loads(pathlib.Path('analysis/scout/slus_20486/load_chain_windows.json').read_text())
assert m['serial']=='SLUS_204.86' and m['elf_sha256']==sys.argv[2]
n=verify_windows(p,m)
(p/'windows.tsv').write_text(''.join(f"{w['name']}\t{int(w['va'],16):x}\t{w['bytes']}\t{w['sha256']}\n" for w in m['windows']))
(p/'entries.tsv').write_text(''.join(f"{int(w['va'],16)+off:x}\n" for w in m['windows'] for off in w['entry_offsets']))
print(f'Verified {n} US fragment bytes; full-game gate remains separate')
PY
rm -f "$OUT/functions.json" "$OUT/disassembly.tsv"
timeout 300 tools/ghidra/ghidra_12.0.2_PUBLIC/support/analyzeHeadless \
  "$MVC2_ROOT/builddir/us-load-chain-project" partial_load_chain \
  -import "$DIR/load_core.bin" -loader BinaryLoader -loader-baseAddr 0x10b970 \
  -processor r5900:LE:32:default -noanalysis -scriptPath "$MVC2_ROOT/scripts/ghidra" \
  -postScript DisassembleWindows.java "$DIR" "$OUT/disassembly.tsv" \
  -postScript DecompileEntries.java "$DIR/entries.tsv" "$OUT" \
  -deleteProject > "$OUT/ghidra.log" 2>&1
grep -q 'Partial entries decompiled successfully: 4' "$OUT/ghidra.log"
python3 scripts/summarize_load_chain.py
