#!/usr/bin/env bash
# ============================================================
# mvc2-recomp — environment setup for the local toolchain.
# Usage:  source scripts/env.sh
# All tools live inside the repo (tools/) so the project does
# not depend on system-wide installs. See docs/bootstrap.md.
# ============================================================
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MVC2_ROOT="$REPO_ROOT"

# cmake 4.4.4 (PyPI wheel) + ninja 1.13.2 (PyPI wheel)
export PATH="$REPO_ROOT/tools/cmake/bin:$REPO_ROOT/tools/bin:$PATH"

# JDK 21 — prefer the full Eclipse Temurin install (tools/jdk/jdk-21*).
# The jdk4py image under tools/jdk/jdk4py is a trimmed jlink runtime
# WITHOUT javac and must NOT be used as JAVA_HOME (Ghidra rejects it).
for d in "$REPO_ROOT"/tools/jdk/jdk-21*; do
  [ -x "$d/bin/javac" ] && export JAVA_HOME="$d"
done
[ -n "${JAVA_HOME:-}" ] && export PATH="$JAVA_HOME/bin:$PATH"

# Ghidra 12.1.4 (official NSA release)
for d in "$REPO_ROOT"/tools/ghidra/ghidra_*_PUBLIC; do
  [ -d "$d" ] && export GHIDRA_INSTALL_DIR="$d"
done

# PS2Recomp tools (built locally into tools/ps2recomp/bin)
export PATH="$REPO_ROOT/tools/ps2recomp/bin:$PATH"

echo "[mvc2-env] root=$MVC2_ROOT"
echo "[mvc2-env] cmake: $(cmake --version 2>/dev/null | head -1)"
echo "[mvc2-env] ninja: $(ninja --version 2>/dev/null)"
echo "[mvc2-env] javac: $(javac --version 2>&1 | head -1)"
echo "[mvc2-env] GHIDRA_INSTALL_DIR=${GHIDRA_INSTALL_DIR:-<not extracted yet>}"
