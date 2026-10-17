#!/usr/bin/env bash
# ============================================================================
# mvc2-recomp — (re)build the complete local toolchain from scratch.
#
# Idempotent: every step is skipped when its output already exists.
# This is the "GitHub might be gone tomorrow" insurance: with a full
# workspace snapshot it does nothing; on a bare checkout it recreates
# everything using ONLY the hosts reachable from the sandbox
# (github.com git/codeload, pypi.org, registry.npmjs.org) — plus the
# GitHub Actions relay for release binaries (Ghidra, JDK), whose chunks
# are pulled with plain git. Versions/SHAs: tools/MANIFEST.md.
# ============================================================================
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$PWD"
echo "[setup] repo root: $ROOT"
mkdir -p tools/downloads/wheels tools/bin builddir/logs

step() { echo; echo "########## $* ##########"; }
have() { [ -e "$1" ]; }

# ---------------------------------------------------------------------------
step "1. Vendored source clones (git, github.com)"
clone() { # url dest
  if have "$2/.git"; then echo "  ok (exists) $2 @ $(git -C "$2" rev-parse --short HEAD)";
  else echo "  cloning $1 -> $2"; git clone "$1" "$2" || echo "  FAIL clone $2"; fi
}
clone https://github.com/ran-j/PS2Recomp.git                     tools/ps2recomp/PS2Recomp
clone https://github.com/morluto/rea.git                         tools/rea/rea
clone https://github.com/cyberkaida/reverse-engineering-assistant.git tools/rea/reverse-engineering-assistant
clone https://github.com/LaurieWired/GhidraMCP.git               tools/rea/GhidraMCP
clone https://github.com/bethington/ghidra-mcp.git               tools/rea/ghidra-mcp
clone https://github.com/hkmodd/ps2-recomp-Agent-SKILL.git       tools/extra/ps2-recomp-Agent-SKILL

# ---------------------------------------------------------------------------
step "2. cmake + ninja from PyPI wheels (pypi.org)"
# GitHub release assets are unreachable from the sandbox; the official
# cmake/ninja PyPI wheels contain the same upstream binaries.
if have tools/cmake/bin/cmake && have tools/bin/ninja; then
  echo "  ok: $(tools/cmake/bin/cmake --version | head -1), ninja $(tools/bin/ninja --version)"
else
  python3 -m pip download cmake==4.4.4 ninja==1.13.2 -d tools/downloads/wheels || \
  python3 -m pip download cmake ninja -d tools/downloads/wheels
  rm -rf tools/bin/_wheel_extract && mkdir -p tools/bin/_wheel_extract
  for w in tools/downloads/wheels/cmake-*.whl tools/downloads/wheels/ninja-*.whl; do
    python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall('tools/bin/_wheel_extract')" "$w"
  done
  CMDATA=$(find tools/bin/_wheel_extract -path "*cmake/data" -type d | head -1)
  mkdir -p tools/cmake && cp -r "$CMDATA"/. tools/cmake/ && chmod +x tools/cmake/bin/*
  cp "$(find tools/bin/_wheel_extract -name ninja -type f | head -1)" tools/bin/ninja && chmod +x tools/bin/ninja
  echo "  installed: $(tools/cmake/bin/cmake --version | head -1), ninja $(tools/bin/ninja --version)"
fi

# ---------------------------------------------------------------------------
step "3. Full JDK 21 (Eclipse Temurin)"
JDK_DIR=$(ls -d tools/jdk/jdk-21* 2>/dev/null | head -1)
if [ -n "$JDK_DIR" ] && [ -x "$JDK_DIR/bin/javac" ]; then
  echo "  ok: $("$JDK_DIR/bin/javac" --version) in $JDK_DIR"
elif have tools/downloads/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz; then
  ( cd tools/downloads && echo "ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94  OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz" | sha256sum -c - )
  tar xzf tools/downloads/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz -C tools/jdk
  echo "  extracted from local archive"
elif have tools/downloads/jdk-relay/MANIFEST.sha256; then
  ( cd tools/downloads/jdk-relay && sha256sum -c MANIFEST.sha256 )
  cat tools/downloads/jdk-relay/*.part* > tools/downloads/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz
  tar xzf tools/downloads/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz -C tools/jdk
  echo "  extracted from relay chunks"
else
  cat <<'EOF'
  MISSING. The Temurin tarball could not be found locally and GitHub
  release assets are unreachable from this sandbox. To re-fetch via the
  Actions relay:
    1. date -u +%FT%TZ >> tools/jdk/.fetch-jdk-trigger
    2. git add -f tools/jdk/.fetch-jdk-trigger && git commit && git push
    3. wait for workflow "fetch-jdk (bootstrap relay)", then git pull
    4. re-run this script (step 3 will use the relay chunks).
  NOTE: do NOT fall back to PyPI jdk4py — it is a jlink runtime without
  javac and Ghidra rejects it (docs/problems.md P-004).
EOF
fi

# ---------------------------------------------------------------------------
step "4. Ghidra 12.1.4"
GH_DIR=$(ls -d tools/ghidra/ghidra_*_PUBLIC 2>/dev/null | head -1)
if [ -n "$GH_DIR" ] && [ -x "$GH_DIR/support/analyzeHeadless" ]; then
  echo "  ok: $GH_DIR"
elif have tools/downloads/ghidra_12.1.4_PUBLIC_20260921.zip; then
  ( cd tools/downloads && echo "ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db  ghidra_12.1.4_PUBLIC_20260921.zip" | sha256sum -c - )
  python3 - <<'PY'
import zipfile, os
z = zipfile.ZipFile('tools/downloads/ghidra_12.1.4_PUBLIC_20260921.zip')
for info in z.infolist():
    z.extract(info, 'tools/ghidra')
    mode = (info.external_attr >> 16) & 0o7777
    if mode:
        try: os.chmod(os.path.join('tools/ghidra', info.filename), mode)
        except Exception: pass
print('  extracted', len(z.infolist()), 'entries')
PY
elif have tools/downloads/ghidra-relay/MANIFEST.sha256; then
  ( cd tools/downloads/ghidra-relay && sha256sum -c MANIFEST.sha256 )
  cat tools/downloads/ghidra-relay/*.part* > tools/downloads/ghidra_12.1.4_PUBLIC_20260921.zip
  echo "  reassembled; re-run to extract" && exec "$0" "$@"
else
  cat <<'EOF'
  MISSING. Re-fetch via the Actions relay (same flow as the JDK):
    1. date -u +%FT%TZ >> tools/ghidra/.fetch-ghidra-trigger
    2. git add tools/ghidra/.fetch-ghidra-trigger && git commit && git push
    3. wait for workflow "fetch-ghidra (bootstrap relay)", then git pull
    4. re-run this script.
EOF
fi

# ---------------------------------------------------------------------------
step "5. PS2Recomp build (ps2_recomp + ps2_analyzer)"
if have tools/ps2recomp/bin/ps2_recomp && have tools/ps2recomp/bin/ps2_analyzer; then
  echo "  ok: tools/ps2recomp/bin/{ps2_recomp,ps2_analyzer}"
else
  scripts/build_ps2recomp.sh
fi

# ---------------------------------------------------------------------------
step "6. REA (npm ci + build)"
if [ -f tools/rea/rea/dist/main.js ]; then
  echo "  ok: rea $(cd tools/rea/rea && node scripts/rea.mjs --version 2>/dev/null)"
else
  ( cd tools/rea/rea && npm ci --no-audit --no-fund && npm run build ) \
    2>&1 | tail -5
fi

echo
echo "[setup] done. Validate with: scripts/test_infra.sh"
