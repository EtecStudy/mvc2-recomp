#!/usr/bin/env bash
# Build only the upstream analyzer library + our independent CSV exporter.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh >/dev/null
mkdir -p builddir/logs tools/ps2recomp/bin
CACHE_ARGS=()
if [ -f tools/downloads/analyzer-deps.tar.gz ]; then
  python3 scripts/restore_analyzer_deps.py
  CACHE_ARGS=(-C "$MVC2_ROOT/builddir/analyzer-deps.cmake")
fi
cmake "${CACHE_ARGS[@]}" -S tools/ps2recomp/PS2Recomp -B builddir/ps2recomp -G Ninja \
  -DPS2X_BUILD_STUDIO=OFF -DPS2X_BUILD_RUNTIME=OFF -DPS2X_BUILD_TEST=OFF \
  -DPS2X_BUILD_RECOMP=ON -DPS2X_BUILD_ANALYZER=ON -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PROJECT_PS2RetroX_INCLUDE="$MVC2_ROOT/scripts/analyzer_export.cmake" \
  2>&1 | tee builddir/logs/analyzer-export-configure.log
# SDK database compilation is memory-heavy. One worker deliberately.
cmake --build builddir/ps2recomp --target mvc2_analyzer_export -j 1 \
  2>&1 | tee builddir/logs/analyzer-export-build.log
cp builddir/ps2recomp/mvc2_analyzer_export tools/ps2recomp/bin/
echo 'Independent analyzer map exporter built successfully'
