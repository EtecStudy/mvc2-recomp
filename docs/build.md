# Build guide

Everything builds **inside the repo** with the vendored toolchain.
From a fresh shell at the repo root:

```bash
source scripts/env.sh        # PATH, JAVA_HOME, GHIDRA_INSTALL_DIR
```

## 0. (Re)create the whole toolchain

```bash
scripts/setup_tools.sh       # idempotent; skips what already exists
scripts/test_infra.sh        # must end with "0 failed"
```

`setup_tools.sh` steps: git clones (PS2Recomp, REA ×2, GhidraMCP ×2, agent
skill) → cmake/ninja from PyPI wheels → Temurin JDK 21 (local archive or
Actions-relay chunks) → Ghidra 12.1.4 (same) → PS2Recomp build → REA
`npm ci && npm run build`. Pinned versions/hashes: `tools/MANIFEST.md`.

## 1. Project skeleton (FASE 0 stand-in for the game target)

```bash
cmake -S . -B builddir/mvc2 -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build builddir/mvc2
(cd builddir/mvc2 && ctest --output-on-failure)   # infra.smoke
```

## 2. PS2Recomp

```bash
scripts/build_ps2recomp.sh
# = cmake -S tools/ps2recomp/PS2Recomp -B builddir/ps2recomp -G Ninja
#     -DPS2X_BUILD_STUDIO=OFF -DPS2X_BUILD_RUNTIME=OFF (see script header)
#   cmake --build builddir/ps2recomp -j2 -- -k 0
#   → tools/ps2recomp/bin/{ps2_recomp,ps2_analyzer}
ctest --test-dir builddir/ps2recomp/ps2xTest/gs_cache   # 45 tests
tools/ps2recomp/bin/ps2_analyzer                        # usage
tools/ps2recomp/bin/ps2_recomp                          # usage
```

## 3. Ghidra headless

```bash
"$GHIDRA_INSTALL_DIR/support/analyzeHeadless" \
  analysis/ghidra_projects <project> -import <file> [-postScript ...]
```

Requires `JAVA_HOME` = the **full** Temurin JDK (`tools/jdk/jdk-21*`, set by
`env.sh`). The `tools/jdk/jdk4py/` runtime is **not** a JDK (no javac) and
Ghidra refuses it — see problems P-004.

## 4. REA

```bash
cd tools/rea/rea
node scripts/rea.mjs --version                    # 6.5.0
node scripts/rea.mjs doctor --json                # ghidra provider available
node scripts/rea.mjs analyze <elf> --provider ghidra --json
node scripts/rea.mjs mcp                          # MCP server on stdio
```

Rebuild after `git pull` in that tree: `npm ci && npm run build`.

## 5. Known build gaps (tracked in docs/problems.md)

* `ps2xRuntime` (Linux): needs `pkg-config` + ffmpeg dev libs (P-005).
  `ps2xTest`'s `ps2_test_lib` needs the runtime headers, so it is the one
  target that does not build today; `ninja -k 0` still produces everything
  else, including both CLI tools and the 3 gs_cache test executables.
* `ps2xStudio`: needs OpenGL dev packages; GUI tool, not required.
* Windows target: no MSVC/MinGW in this sandbox (see architecture.md).
