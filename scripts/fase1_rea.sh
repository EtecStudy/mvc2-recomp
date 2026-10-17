#!/usr/bin/env bash
# ============================================================================
# FASE 1 — REA (Ghidra 12.1.4 provider) scouting passes over the ELF.
# Division of labour: REA gives fast agent-friendly overviews; the
# authoritative function map comes from Ghidra 12.0.2 + r5900 in
# scripts/fase1_analyze.sh (REA's pinned Ghidra 12.1.4 has no EmotionEngine
# extension build; see PS2-16 comment). Outputs land in analysis/scout/.
#
#   scripts/fase1_rea.sh [path-to-elf]
# ============================================================================
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source scripts/env.sh

ELF="${1:-game/working/SLPM_622.27}"
[ -f "$ELF" ] || { echo "[rea] ELF not found: $ELF (PS2-20)"; exit 2; }
mkdir -p analysis/scout builddir/logs
REA="node tools/rea/rea/scripts/rea.mjs"

echo "== rea doctor (ghidra provider) =="
timeout 180 $REA doctor --json > analysis/scout/rea_doctor.json 2>&1
grep -o '"id":"ghidra","configured":true,"available":true' analysis/scout/rea_doctor.json \
  && echo "  provider OK" || echo "  WARNING: provider not available (see rea_doctor.json)"

echo "== binary_overview =="
timeout 1800 $REA analyze "$ELF" --provider ghidra --json \
  > analysis/scout/rea_overview.json 2> builddir/logs/fase1-rea.log
echo "  exit: $? -> analysis/scout/rea_overview.json"

echo "== procedure inventory (count only) =="
timeout 1800 $REA search "$ELF" . --kind procedures --mode regex --provider ghidra --json \
  > analysis/scout/rea_procedures.json 2>> builddir/logs/fase1-rea.log
python3 - <<'PY'
import json, pathlib
p = pathlib.Path('analysis/scout/rea_procedures.json')
try:
    d = json.loads(p.read_text())
    res = d.get('normalized_result') or {}
    items = res.get('items') or res.get('procedures') or []
    print(f"  REA procedures: {len(items)}")
except Exception as e:
    print(f"  could not parse rea_procedures.json ({e}); inspect manually")
PY
echo "[rea] done."
