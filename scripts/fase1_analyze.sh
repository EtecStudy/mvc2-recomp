#!/usr/bin/env bash
# ============================================================================
# FASE 1 pipeline — SLPM_622.27 analysis & recompiler inputs.
#
#   scripts/fase1_analyze.sh [path-to-elf] [--recomp]
#
# Steps:
#   0. SHA-256 gate against the verified disc ELF (docs/discoveries.md)
#   1. Ghidra 12.0.2 + EmotionEngine (r5900:LE:32:default) headless import
#      with auto-analysis, then PS2Recomp's ExportPS2Functions.java
#      -> generated/config/mvc2.toml + mvc2_functions.csv
#   2. ps2_analyzer cross-check -> generated/config/mvc2_analyzer.toml
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
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source scripts/env.sh

ELF="${1:-game/working/SLPM_622.27}"
DO_RECOMP=0
[ "${2:-}" = "--recomp" ] && DO_RECOMP=1
EXPECTED_SHA256="de42633ccf9d78fed3d8cbecd75a81a9e043a7b4298be374a8ffa7689cb42af5"

if [ ! -f "$ELF" ]; then
  echo "[fase1] ELF not found: $ELF"
  echo "[fase1] The verified ELF is staged in Supabase (bootstrap_transfer);"
  echo "[fase1] see PS2-20 / docs/problems.md P-006 for how to place it here."
  exit 2
fi

echo "== step 0: checksum gate =="
if echo "$EXPECTED_SHA256  $ELF" | sha256sum -c - ; then
  echo "  OK: byte-identical to the Supabase-verified disc ELF"
elif [ "${MVC2_SKIP_HASH:-0}" = "1" ]; then
  echo "  WARNING: hash differs, continuing because MVC2_SKIP_HASH=1"
else
  echo "  ERROR: hash mismatch (set MVC2_SKIP_HASH=1 to override knowingly)"
  exit 3
fi

GH_EE="$MVC2_ROOT/tools/ghidra/ghidra_12.0.2_PUBLIC"
mkdir -p generated/config analysis/ghidra_projects builddir/logs

echo "== step 1: Ghidra 12.0.2 + r5900 -> ExportPS2Functions =="
"$GH_EE/support/analyzeHeadless" "$MVC2_ROOT/analysis/ghidra_projects" mvc2_slpm62227 \
  -import "$ELF" \
  -processor "r5900:LE:32:default" \
  -scriptPath "$MVC2_ROOT/tools/ps2recomp/PS2Recomp/ps2xRecomp/tools/ghidra" \
  -postScript ExportPS2Functions.java \
      "$MVC2_ROOT/generated/config/mvc2.toml" \
      "$MVC2_ROOT/generated/config/mvc2_functions.csv" \
  -log "$MVC2_ROOT/builddir/logs/fase1-ghidra.log" \
  -scriptlog "$MVC2_ROOT/builddir/logs/fase1-ghidra-script.log" 2>&1 | tail -15
echo "  ghidra exit: ${PIPESTATUS[0]} (full log: builddir/logs/fase1-ghidra.log)"

echo "== step 2: ps2_analyzer cross-check =="
tools/ps2recomp/bin/ps2_analyzer "$ELF" generated/config/mvc2_analyzer.toml 2>&1 \
  | tee builddir/logs/fase1-analyzer.log | tail -6

echo "== step 3: comparison summary =="
python3 - <<'PY'
import csv, re, pathlib
gh = pathlib.Path('generated/config/mvc2_functions.csv')
gh_addr = set()
if gh.exists():
    for row in csv.DictReader(gh.open()):
        try: gh_addr.add(int(row['Start'], 16))
        except Exception: pass
print(f"  ghidra csv functions/labels: {len(gh_addr)}")
an = pathlib.Path('generated/config/mvc2_analyzer.toml')
if an.exists():
    txt = an.read_text(errors='ignore')
    m = re.findall(r'0x[0-9a-fA-F]{8}', txt)
    print(f"  analyzer toml size: {len(txt)} bytes, address-like tokens: {len(m)}")
print("  (previous discarded attempt for reference: 268 modules / 1,094,592 instructions)")
PY

echo "== step 4: TOML normalization (low memory, 1 worker) =="
python3 - <<'PY'
import pathlib, re
p = pathlib.Path('generated/config/mvc2.toml')
if not p.exists():
    print("  mvc2.toml missing; inspect builddir/logs/fase1-ghidra.log"); raise SystemExit(0)
t = p.read_text()
def ensure(key, val):
    global t
    if re.search(rf'^\s*{key}\s*=', t, re.M):
        t = re.sub(rf'^\s*{key}\s*=.*$', f'{key} = {val}', t, flags=re.M)
    elif '[general]' in t:
        t = t.replace('[general]', f'[general]\n{key} = {val}', 1)
    else:
        print(f"  WARNING: could not place {key}; edit the TOML manually")
ensure('low_memory_mode', 'true')
ensure('output_worker_threads', '1')
ensure('single_file_output', 'false')
p.write_text(t)
print("  mvc2.toml normalized")
PY

if [ "$DO_RECOMP" = "1" ]; then
  echo "== step 5: ps2_recomp (LONG — 2 cores; generated/cpp) =="
  tools/ps2recomp/bin/ps2_recomp generated/config/mvc2.toml 2>&1 \
    | tee builddir/logs/fase1-recomp.log | tail -10
  echo "  recomp exit: ${PIPESTATUS[0]}"
else
  echo "== step 5 skipped (pass --recomp to generate C++) =="
fi
echo "[fase1] done."
