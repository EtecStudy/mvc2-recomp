#!/usr/bin/env bash
# ============================================================================
# FASE 1 pipeline — SLUS_204.86 analysis & recompiler inputs.
#
#   scripts/fase1_analyze.sh [path-to-elf] [--recomp]
#
# Steps:
#   0. SHA-256 gate against the verified disc ELF (docs/discoveries.md)
#   1. Ghidra 12.0.2 + EmotionEngine (r5900:LE:32:default) headless import
#      with auto-analysis, then PS2Recomp's ExportPS2Functions.java
#      -> generated/config/slus_20486/mvc2.toml + mvc2_functions.csv
#   2. ps2_analyzer cross-check -> generated/config/slus_20486/mvc2_analyzer.toml
#   3. Printed comparison summary (function counts / address overlap)
#   4. TOML normalization for this small machine:
#      general.low_memory_mode=true, output_worker_threads=1 (PS2-16)
#   5. With --recomp: run ps2_recomp (LONG on 2 cores; runs detached-ish
#      under tee; generated C++ lands in generated/cpp, gitignored)
#
# Prereq: the ELF locally (issue PS2-20 / docs/problems.md P-006).
# NOTE on memory: if Ghidra OOMs, raise VMARGS -Xmx in
#   tools/ghidra/ghidra_12.0.2_PUBLIC/support/launch.properties
# (box has 3.8 GiB; keep at least ~1 GiB for the OS).
# ============================================================================
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source scripts/env.sh

ELF="${1:-game/working/SLUS_204.86}"
DO_RECOMP=0
[ "${2:-}" = "--recomp" ] && DO_RECOMP=1
source scripts/target.sh
mvc2_verify_target "$ELF" || exit $?

GH_EE="$MVC2_ROOT/tools/ghidra/ghidra_12.0.2_PUBLIC"
mkdir -p generated/config/slus_20486 analysis/ghidra_projects builddir/logs

# Avoid treating stale exports as a successful run (headless can log script
# errors without a failing process status). Only derived US outputs are removed.
rm -f generated/config/slus_20486/mvc2.toml generated/config/slus_20486/mvc2_functions.csv

echo "== step 1: Ghidra 12.0.2 + r5900 -> ExportPS2Functions =="
"$GH_EE/support/analyzeHeadless" "$MVC2_ROOT/analysis/ghidra_projects" mvc2_slus20486 \
  -import "$ELF" -overwrite \
  -processor "r5900:LE:32:default" \
  -scriptPath "$MVC2_ROOT/tools/ps2recomp/PS2Recomp/ps2xRecomp/tools/ghidra" \
  -postScript ExportPS2Functions.java \
      "$MVC2_ROOT/generated/config/slus_20486/mvc2.toml" \
      "$MVC2_ROOT/generated/config/slus_20486/mvc2_functions.csv" \
  -log "$MVC2_ROOT/builddir/logs/slus20486-fase1-ghidra.log" \
  -scriptlog "$MVC2_ROOT/builddir/logs/slus20486-fase1-ghidra-script.log" 2>&1 | tail -15
echo "  ghidra exit: ${PIPESTATUS[0]} (full log: builddir/logs/slus20486-fase1-ghidra.log)"

test -s generated/config/slus_20486/mvc2.toml
test -s generated/config/slus_20486/mvc2_functions.csv

echo "== step 2: ps2_analyzer cross-check =="
tools/ps2recomp/bin/ps2_analyzer "$ELF" generated/config/slus_20486/mvc2_analyzer.toml 2>&1 \
  | tee builddir/logs/slus20486-fase1-analyzer.log | tail -6

echo "== step 3: comparison summary =="
python3 - <<'PY'
import csv, re, pathlib
gh = pathlib.Path('generated/config/slus_20486/mvc2_functions.csv')
gh_addr = set()
if gh.exists():
    for row in csv.DictReader(gh.open()):
        try: gh_addr.add(int(row['Start'], 16))
        except Exception: pass
assert gh_addr, "No valid function/label starts exported; refusing codegen"
print(f"  ghidra csv functions/labels: {len(gh_addr)}")
an = pathlib.Path('generated/config/slus_20486/mvc2_analyzer.toml')
if an.exists():
    txt = an.read_text(errors='ignore')
    m = re.findall(r'0x[0-9a-fA-F]{8}', txt)
    print(f"  analyzer toml size: {len(txt)} bytes, address-like tokens: {len(m)}")
print("  Target: SLUS_204.86; no Japanese function counts are reused.")
PY

echo "== step 4: TOML normalization (low memory, 1 worker) =="
python3 scripts/normalize_recomp_config.py \
  generated/config/slus_20486/mvc2.toml generated/cpp/slus_20486

if [ "$DO_RECOMP" = "1" ]; then
  echo "== step 5: ps2_recomp (LONG — 2 cores; generated/cpp) =="
  tools/ps2recomp/bin/ps2_recomp generated/config/slus_20486/mvc2.toml 2>&1 \
    | tee builddir/logs/slus20486-fase1-recomp.log | tail -10
  echo "  recomp exit: ${PIPESTATUS[0]}"
else
  echo "== step 5 skipped (pass --recomp to generate C++) =="
fi
echo "[fase1] done."
