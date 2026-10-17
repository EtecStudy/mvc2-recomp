#!/usr/bin/env bash
# Restore ONLY public open-source tool archives from known relay commits.
# Never game data. Does not checkout/reset/switch this session's branch.
set -euo pipefail
cd "$(dirname "$0")/.."
restore() {
  local sha="$1"; shift
  git fetch --depth=1 origin "$sha"
  git archive "$sha" "$@" | tar -x
}
if { [ ! -f tools/downloads/ghidra_12.0.2_PUBLIC_20260129.zip ] &&
     [ ! -f tools/downloads/relay/ghidra-12.0.2/MANIFEST.sha256 ]; } ||
   { [ ! -f tools/downloads/ghidra_12.0.2_PUBLIC_20261004_ghidra-emotionengine-reloaded.zip ] &&
     [ ! -f tools/downloads/relay/ghidra-ee-reloaded-2.1.38/MANIFEST.sha256 ]; }; then
  restore 0274d763fa00c1d07842800300d2c57124c0bca2 \
    tools/downloads/relay/ghidra-12.0.2 tools/downloads/relay/ghidra-ee-reloaded-2.1.38
fi
if { [ ! -f tools/downloads/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz ] &&
     [ ! -f tools/downloads/jdk-relay/MANIFEST.sha256 ]; } ||
   { [ ! -f tools/downloads/ghidra_12.1.4_PUBLIC_20260921.zip ] &&
     [ ! -f tools/downloads/ghidra-relay/MANIFEST.sha256 ]; }; then
  restore e73ec4d96594391def563b074461fdf3f60ce58f \
    tools/downloads/jdk-relay tools/downloads/ghidra-relay
fi
echo '[restore] available tool archives/chunks ready; setup verifies hashes before extraction'
