#!/usr/bin/env bash
# End-to-end tool probe with a tiny ORIGINAL synthetic ELF, never game bytes.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh >/dev/null
mkdir -p builddir/tests builddir/logs
WORK=$(mktemp -d "$PWD/builddir/tests/ghidra-ee.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
python3 - "$WORK/probe.elf" <<'PY'
import struct, sys
from pathlib import Path
# ELF32 LE MIPS ET_EXEC, entry 0x100000, one executable PT_LOAD.
ident = b'\x7fELF\x01\x01\x01' + bytes(9)
header = struct.pack('<16sHHIIIIIHHHHHH', ident, 2, 8, 1, 0x100000,
                     52, 0, 0x20924000, 52, 32, 1, 40, 0, 0)
# Original function: addiu v0,zero,42; jr ra; nop; nop.
code = struct.pack('<4I', 0x2402002a, 0x03e00008, 0, 0)
ph = struct.pack('<8I', 1, 0x100, 0x100000, 0x100000, len(code), len(code), 5, 0x100)
Path(sys.argv[1]).write_bytes((header + ph).ljust(0x100, b'\0') + code)
PY
mkdir -p "$WORK/project"
GH="$MVC2_ROOT/tools/ghidra/ghidra_12.0.2_PUBLIC"
timeout 600 "$GH/support/analyzeHeadless" "$WORK/project" ee_probe \
  -import "$WORK/probe.elf" -processor r5900:LE:32:default \
  -scriptPath "$MVC2_ROOT/tools/ps2recomp/PS2Recomp/ps2xRecomp/tools/ghidra" \
  -postScript ExportPS2Functions.java "$WORK/probe.toml" "$WORK/probe.csv" \
  -deleteProject > builddir/logs/ghidra-ee-probe.log 2>&1
python3 - "$WORK" <<'PY'
import csv, pathlib, sys, tomllib
p = pathlib.Path(sys.argv[1])
d = tomllib.loads((p / 'probe.toml').read_text())
rows = list(csv.DictReader((p / 'probe.csv').open()))
assert d and rows, 'No exported functions from synthetic probe'
print(f'PASS: Ghidra 12.0.2 / r5900 imports synthetic ELF; ExportPS2Functions produces TOML + CSV ({len(rows)} rows)')
PY

# Prove the translator works on the original synthetic function, not game code.
python3 scripts/normalize_recomp_config.py "$WORK/probe.toml" "$WORK/cpp"
timeout 120 tools/ps2recomp/bin/ps2_recomp "$WORK/probe.toml" \
  > builddir/logs/recomp-synthetic-probe.log 2>&1
find "$WORK/cpp" -name '*.cpp' -type f | grep -q .
echo 'PASS: synthetic ELF -> Ghidra TOML/CSV -> normalized config -> ps2_recomp C++'
