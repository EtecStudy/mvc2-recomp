#!/usr/bin/env bash
# ============================================================================
# Build the PS2Recomp toolchain (core tools used by this project):
#   ps2_recomp   - R5900 static recompiler (ELF + TOML -> C++)
#   ps2_analyzer - ELF analyzer (ELF -> TOML), embedded SCE symbol DB
#   gs_cache test suites
# Excluded on this Linux sandbox (see docs/problems.md):
#   ps2xStudio   - needs OpenGL dev packages (GUI tool, not required)
#   ps2xRuntime  - Linux path needs pkg-config + ffmpeg dev libraries;
#                  tracked as FASE 1 infrastructure work. NOTE: with
#                  RUNTIME=OFF, ps2xTest's ps2_test_lib also fails to
#                  compile (it includes runtime/IOP headers); every other
#                  target builds. We build with `ninja -k 0` for that reason.
# ============================================================================
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source scripts/env.sh >/dev/null
mkdir -p builddir/logs tools/ps2recomp/bin

cmake -S tools/ps2recomp/PS2Recomp -B builddir/ps2recomp -G Ninja \
  -DPS2X_BUILD_STUDIO=OFF -DPS2X_BUILD_RUNTIME=OFF \
  -DPS2X_BUILD_RECOMP=ON -DPS2X_BUILD_ANALYZER=ON -DPS2X_BUILD_TEST=ON \
  -DCMAKE_BUILD_TYPE=Release 2>&1 | tee builddir/logs/ps2recomp-configure.log | tail -3

cmake --build builddir/ps2recomp -j 2 -- -k 0 2>&1 | tee builddir/logs/ps2recomp-build.log | tail -5

cp -f builddir/ps2recomp/ps2xRecomp/ps2_recomp \
      builddir/ps2recomp/ps2xAnalyzer/ps2_analyzer \
      tools/ps2recomp/bin/
echo "[build_ps2recomp] binaries staged in tools/ps2recomp/bin/:"
ls -lh tools/ps2recomp/bin/
