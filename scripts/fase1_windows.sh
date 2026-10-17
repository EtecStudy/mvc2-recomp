#!/usr/bin/env bash
# Partial US scouting ONLY: this does not bypass the full-ELF pipeline gate.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh >/dev/null
source scripts/target.sh
DIR="$MVC2_ROOT/game/working/slus_20486/windows"
python3 - "$DIR" "$MVC2_TARGET_SHA256" <<'PY'
import hashlib, json, pathlib, sys
folder = pathlib.Path(sys.argv[1])
meta = json.loads(pathlib.Path('analysis/scout/slus_20486/code_windows.json').read_text())
assert meta['serial'] == 'SLUS_204.86' and meta['elf_sha256'] == sys.argv[2]
lines = []
for w in meta['windows']:
    name = w['name']
    assert name in {'boot', 'usb_init', 'audio_init', 'network_init'}
    data = (folder / (name + '.bin')).read_bytes()
    assert len(data) == w['bytes'] and hashlib.sha256(data).hexdigest() == w['sha256'], name
    lines.append(f"{name}\t{int(w['va'], 16):x}\t{len(data)}\t{w['sha256']}")
(folder / 'windows.tsv').write_text('\n'.join(lines) + '\n')
print('Verified four partial US windows (992 bytes), NOT the full ELF')
PY
mkdir -p builddir/us-windows-project builddir/logs
rm -f builddir/logs/us-window-disassembly.tsv
timeout 300 tools/ghidra/ghidra_12.0.2_PUBLIC/support/analyzeHeadless \
  "$MVC2_ROOT/builddir/us-windows-project" us_windows \
  -import "$DIR/boot.bin" -loader BinaryLoader -loader-baseAddr 0x100000 \
  -processor r5900:LE:32:default -noanalysis \
  -scriptPath "$MVC2_ROOT/scripts/ghidra" \
  -postScript DisassembleWindows.java "$DIR" "$MVC2_ROOT/builddir/logs/us-window-disassembly.tsv" \
  -deleteProject > builddir/logs/us-window-ghidra.log 2>&1
grep -q 'Window disassembly exported' builddir/logs/us-window-ghidra.log
python3 scripts/summarize_us_windows.py
