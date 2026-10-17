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
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$PWD"
echo "[setup] repo root: $ROOT"
mkdir -p tools/downloads/wheels tools/bin tools/jdk tools/ghidra builddir/logs
bash scripts/restore_tool_archives.sh

step() { echo; echo "########## $* ##########"; }
have() { [ -e "$1" ]; }

# ---------------------------------------------------------------------------
step "1. Vendored source clones (git, github.com)"
clone() { # url dest pinned-sha
  if have "$2/.git"; then
    [ "$(git -C "$2" rev-parse HEAD)" = "$3" ] || {
      echo "  ERROR: $2 HEAD differs from MANIFEST pin $3; preserving local tree" >&2; return 1;
    }
    echo "  ok (pinned) $2 @ $3"
  else
    git clone "$1" "$2"
    git -C "$2" checkout --detach "$3"
  fi
}
clone https://github.com/ran-j/PS2Recomp.git tools/ps2recomp/PS2Recomp eb8688b2fd191129f103a39543002c005b33409c
clone https://github.com/morluto/rea.git tools/rea/rea 300905c11be1c25b98fda9e2b71dfa899fc2831c
clone https://github.com/cyberkaida/reverse-engineering-assistant.git tools/rea/reverse-engineering-assistant a05a6b0a18649efd6d74ec8447bdadf8d468c365
clone https://github.com/LaurieWired/GhidraMCP.git tools/rea/GhidraMCP 1e980252087b2479a21b9ca6d82d5829538651a7
clone https://github.com/bethington/ghidra-mcp.git tools/rea/ghidra-mcp cf8b12db27eb139b28b90eaa3488306da910d759
clone https://github.com/hkmodd/ps2-recomp-Agent-SKILL.git tools/extra/ps2-recomp-Agent-SKILL a1cafc23ac2d37d16ce979d3d4987a0bb6989dda

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
JDK_DIR=$(ls -d tools/jdk/jdk-21* 2>/dev/null | head -1) || JDK_DIR=""
if [ -n "$JDK_DIR" ] && [ -x "$JDK_DIR/bin/javac" ]; then
  echo "  ok: $("$JDK_DIR/bin/javac" --version) in $JDK_DIR"
elif have tools/downloads/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz; then
  ( cd tools/downloads && echo "ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94  OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz" | sha256sum -c - )
  tar xzf tools/downloads/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz -C tools/jdk
  echo "  extracted from local archive"
elif have tools/downloads/jdk-relay/MANIFEST.sha256; then
  ( cd tools/downloads/jdk-relay && sha256sum -c MANIFEST.sha256 )
  cat tools/downloads/jdk-relay/*.part* > tools/downloads/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz
  ( cd tools/downloads && echo "ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94  OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz" | sha256sum -c - )
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
GH_DIR=tools/ghidra/ghidra_12.1.4_PUBLIC
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
step "4b. Ghidra 12.0.2 + EmotionEngine extension (R5900, FASE 1)"
# REA pins Ghidra 12.1.4 (step 4), but the R5900 processor module
# (chaoticgd/ghidra-emotionengine-reloaded) releases target 12.0.x.
# Both installs coexist: 12.1.4 -> REA, 12.0.2+EE -> ExportPS2Functions.
extract_zip_perms() { # zip destdir
  python3 - "$1" "$2" <<'PY'
import zipfile, os, sys
z = zipfile.ZipFile(sys.argv[1])
for info in z.infolist():
    z.extract(info, sys.argv[2])
    m = (info.external_attr >> 16) & 0o7777
    if m:
        try: os.chmod(os.path.join(sys.argv[2], info.filename), m)
        except Exception: pass
print('  extracted', len(z.infolist()), 'entries from', sys.argv[1])
PY
}
relay_or_local() { # relay-name archive-name sha256 -> echoes archive path in tools/downloads
  local name="$1" arc="$2" sha="$3"
  if have "tools/downloads/$arc"; then
    ( cd tools/downloads && echo "$sha  $arc" | sha256sum -c - >/dev/null ) && { echo "tools/downloads/$arc"; return 0; }
  fi
  if have "tools/downloads/relay/$name/MANIFEST.sha256"; then
    ( cd "tools/downloads/relay/$name" && sha256sum -c MANIFEST.sha256 >/dev/null ) || return 1
    cat "tools/downloads/relay/$name"/*.part* > "tools/downloads/$arc"
    ( cd tools/downloads && echo "$sha  $arc" | sha256sum -c - >/dev/null ) && { echo "tools/downloads/$arc"; return 0; }
  fi
  return 1
}
GH12_DIR=tools/ghidra/ghidra_12.0.2_PUBLIC
EE_DIR="$GH12_DIR/Ghidra/Extensions/ghidra-emotionengine-reloaded"
if [ -x "$GH12_DIR/support/analyzeHeadless" ] && [ -d "$EE_DIR/data/languages" ]; then
  echo "  ok: $GH12_DIR + EmotionEngine extension"
else
  if ARC=$(relay_or_local ghidra-12.0.2 ghidra_12.0.2_PUBLIC_20260129.zip cf6e9de0b4d6e4ad2810bb4cd7fda59da726a98a454cd140694782aeaf2580e1); then
    [ -d "$GH12_DIR" ] || extract_zip_perms "$ARC" tools/ghidra
  else
    echo "  MISSING ghidra 12.0.2: bump tools/.fetch-requests, commit+push, git pull, re-run."
  fi
  if ARC=$(relay_or_local ghidra-ee-reloaded-2.1.38 ghidra_12.0.2_PUBLIC_20261004_ghidra-emotionengine-reloaded.zip a9ce84b2408a50a2cb7a767e217971ed2c20a46773eb82b3ce8d3c921681bc01); then
    # extension must be INSTALLED under Ghidra/Extensions/ (not Extensions/Ghidra/)
    [ -d "$EE_DIR" ] || extract_zip_perms "$ARC" "$GH12_DIR/Ghidra/Extensions"
  else
    echo "  MISSING EE extension: same relay flow as above."
  fi
fi

# ---------------------------------------------------------------------------
step "5. PS2Recomp build (ps2_recomp + ps2_analyzer)"
if have tools/ps2recomp/bin/ps2_recomp && have tools/ps2recomp/bin/ps2_analyzer; then
  echo "  ok: tools/ps2recomp/bin/{ps2_recomp,ps2_analyzer}"
else
  scripts/build_ps2recomp.sh
fi

# ---------------------------------------------------------------------------
step "5b. Independent analyzer map exporter"
if [ -x tools/ps2recomp/bin/mvc2_analyzer_export ]; then
  echo "  ok: mvc2_analyzer_export"
else
  bash scripts/build_analyzer_export.sh
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
