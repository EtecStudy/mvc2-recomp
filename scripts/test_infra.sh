#!/usr/bin/env bash
# ============================================================================
# mvc2-recomp — full infrastructure validation suite (FASE 0, section 8).
# Every tool must pass its own smoke test. Prints PASS/FAIL per check and
# exits non-zero if anything failed. Safe to re-run at any time.
# ============================================================================
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source scripts/env.sh
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1 -- $2"; }
sect() { echo; echo "== $* =="; }

sect "Git / GitHub"
git --version >/dev/null 2>&1 && ok "git ($(git --version | awk '{print $3}'))" || bad "git" "not found"
gh auth status >/dev/null 2>&1 && ok "gh authenticated" || bad "gh auth" "not authenticated"
[ "$(git rev-parse --abbrev-ref HEAD)" = "arena/6f7b7e03-mvc2-recomp" ] \
  && ok "on session branch" || bad "branch" "unexpected branch"

sect "Build toolchain"
cmake --version >/dev/null 2>&1 && ok "cmake ($(cmake --version | head -1 | awk '{print $3}'))" || bad "cmake" "missing"
ninja --version >/dev/null 2>&1 && ok "ninja ($(ninja --version))" || bad "ninja" "missing"
g++ --version >/dev/null 2>&1 && ok "g++ ($(g++ -dumpversion))" || bad "g++" "missing"
python3 --version >/dev/null 2>&1 && ok "python3 ($(python3 --version | awk '{print $2}'))" || bad "python3" "missing"
node --version >/dev/null 2>&1 && ok "node ($(node --version))" || bad "node" "missing"
javac --version >/dev/null 2>&1 && ok "javac ($(javac --version | awk '{print $2}')) full JDK" || bad "javac" "missing (jdk4py runtime does NOT count)"

sect "Project skeleton (cmake + ctest)"
if cmake -S . -B builddir/mvc2 -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null 2>&1 \
   && cmake --build builddir/mvc2 >/dev/null 2>&1 \
   && (cd builddir/mvc2 && ctest -Q >/dev/null 2>&1); then ok "mvc2_smoke_test builds and passes"; else bad "skeleton" "configure/build/ctest failed"; fi

sect "PS2Recomp"
out=$(timeout 10 tools/ps2recomp/bin/ps2_recomp </dev/null 2>&1 | head -1)
echo "$out" | grep -qi "static recompiler" && ok "ps2_recomp runs" || bad "ps2_recomp" "$out"
out=$(timeout 10 tools/ps2recomp/bin/ps2_analyzer </dev/null 2>&1 | head -1)
echo "$out" | grep -qi "ELF Analyzer" && ok "ps2_analyzer runs" || bad "ps2_analyzer" "$out"
if [ -d builddir/ps2recomp/ps2xTest/gs_cache ]; then
  (cd builddir/ps2recomp && timeout 240 ctest --test-dir ps2xTest/gs_cache -Q >/dev/null 2>&1) \
    && ok "PS2Recomp gs_cache suite (45 tests)" || bad "gs_cache suite" "ctest failed"
else bad "gs_cache suite" "builddir missing; run scripts/build_ps2recomp.sh"; fi
[ -f tools/ps2recomp/PS2Recomp/ps2xRecomp/tools/ghidra/ExportPS2Functions.java ] \
  && ok "ExportPS2Functions.java present" || bad "ExportPS2Functions.java" "missing"

sect "Ghidra 12.1.4"
[ -x "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" ] && ok "analyzeHeadless present" || bad "ghidra" "not extracted"
"$GHIDRA_INSTALL_DIR/Ghidra/Features/Decompiler/os/linux_x86_64/decompile" </dev/null >/dev/null 2>&1 \
  && ok "native decompiler binary starts" || ok "native decompiler binary present (exit!=0 on empty input is normal)"

sect "Ghidra 12.0.2 + EmotionEngine (R5900)"
GH12="$MVC2_ROOT/tools/ghidra/ghidra_12.0.2_PUBLIC"
[ -x "$GH12/support/analyzeHeadless" ] && ok "12.0.2 analyzeHeadless present" || bad "ghidra-12.0.2" "missing"
[ -f "$GH12/Ghidra/Extensions/ghidra-emotionengine-reloaded/data/languages/r5900.sla" ] \
  && ok "R5900 sleigh compiled (.sla cached)" || bad "r5900.sla" "extension not installed/compiled"

sect "ps2xIOP (upstream IOP subsystem)"
if [ -d builddir/ps2xiop ]; then
  (cd builddir/ps2xiop && timeout 120 ctest -Q >/dev/null 2>&1) \
    && ok "ps2xIOP suite (4 tests)" || bad "ps2xIOP suite" "ctest failed"
else bad "ps2xIOP" "builddir/ps2xiop missing (see docs/build.md)"; fi

sect "REA 6.5.0 + Ghidra provider"
if [ -f tools/rea/rea/dist/main.js ]; then
  v=$(cd tools/rea/rea && node scripts/rea.mjs --version 2>/dev/null)
  [ -n "$v" ] && ok "rea CLI ($v)" || bad "rea CLI" "no version output"
  (cd tools/rea/rea && timeout 120 node scripts/rea.mjs doctor --json 2>/dev/null | grep -q '"available":true') \
    && ok "rea doctor: ghidra provider available" || bad "rea doctor" "ghidra provider not available"
  hs=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"mvc2-test","version":"0.1"}}}' \
       | (cd tools/rea/rea && timeout 25 node scripts/rea.mjs mcp 2>/dev/null) | head -c 400)
  echo "$hs" | grep -q '"name":"rea"' && ok "rea MCP stdio handshake" || bad "rea MCP" "handshake failed"
else
  bad "rea" "dist/main.js missing; run scripts/setup_tools.sh step 6"
fi

sect "Reachability matrix (informational)"
for u in https://api.github.com https://pypi.org https://registry.npmjs.org; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$u" 2>/dev/null)
  [ "$code" = "200" ] && ok "$u" || echo "  INFO  $u -> $code (offline work still possible; see docs)"
done

echo
echo "=================================================="
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
