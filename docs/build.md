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

## Active USA FASE 1 pipeline

```bash
scripts/fase1_analyze.sh game/working/SLUS_204.86 --recomp
bash scripts/test_ghidra_ee.sh  # original synthetic ELF → export → C++ probe
bash tests/test_target.sh     # fail-closed serial/size/hash checks
python3 tests/test_normalize_config.py
```

The full-game command currently exits 2 because the local US ELF is still
missing (P-006); small-window Ghidra work is not a substitute. Verified hash
is pinned in `scripts/target.sh`. Exports use `generated/config/slus_20486/`;
normalizer forces ignored C++ output to `generated/cpp/slus_20486/` (the
upstream export defaults to an unignored config/output folder).

Standalone cache-test rebuild (no runtime graphics dependencies):

```bash
cmake -S tools/ps2recomp/PS2Recomp/ps2xTest/gs_cache -B builddir/gs_cache -G Ninja
cmake --build builddir/gs_cache -j2
ctest --test-dir builddir/gs_cache --no-tests=error --output-on-failure
cmake -S tools/ps2recomp/PS2Recomp/ps2xIOP -B builddir/ps2xiop -G Ninja -DPS2X_IOP_BUILD_TESTS=ON
cmake --build builddir/ps2xiop -j2
ctest --test-dir builddir/ps2xiop --no-tests=error --output-on-failure
```

Setup now enforces manifest source pins, verifies the reassembled JDK hash,
and distinguishes Ghidra versions explicitly. Native decompiler validation
no longer treats missing executables as passes. Graphics runtime P-005 is
still a later-phase Linux X11/Wayland dependency issue, not an EE-codegen issue.


## Independent analyzer CSV exporter

```bash
bash scripts/build_analyzer_export.sh
```

Builds only the analyzer adapter/library dependency chain, not the GUI or
runtime/tests that require missing Linux development packages. Uses one
compiler worker to limit memory; source injection leaves upstream files
unchanged. `setup_tools.sh` now includes this adapter. `test_ghidra_ee.sh`
proves analyzer CLI/adapter TOML parity, compares independent CSV maps,
then generates C++ from the Ghidra config on original synthetic code.

A hash-pinned 29.7MB local dependency archive is verified/restored by
`scripts/restore_analyzer_deps.py`; CMake local source overrides and
FULLY_DISCONNECTED were used in a successful rebuild. Pin/digest details:
`tools/analyzer_deps.json`. No archive/game bytes are committed. Initial
restore caught an incorrect CMakeLists assumption for Rabbitizer; fixed
to its actual include/rabbitizer.h sentinel and covered by restore tests.


## Bounded US load-chain analysis (not whole-game codegen)

`bash scripts/fase1_load_chain.sh` verifies three ignored source windows,
imports them into a separate Ghidra12.0.2/EE project, decompiles four
entries, checks full relocation-normalized SDK signatures and corroborates
the core with the native analyzer on a **derived fragment ELF**. It never
calls the full-game pipeline on a fragment and never generates game C++.
Required bytes come from the read-only capture_us_load_chain.sql route;
full source hashes/entry offsets are in load_chain_windows.json. Raw
bytes, derived ELF/TOML/CSV and pseudocode remain ignored. Fact report:
`analysis/scout/slus_20486/load_chain_facts.json`.


## Owner attachment intake (agent-run)

After the owner attaches only the extracted US SLUS_204.86, the agent
runs `python3 scripts/import_us_elf.py ATTACHMENT_PATH`, then the existing
`fase1_analyze.sh game/working/SLUS_204.86 --recomp` workflow. No manual
shell commands are requested from the owner. Import reads the pinned
identity from target.sh, verifies the copied content independently and
publishes atomically without overwriting a different target. It never
moves/modifies the attachment or uploads game bytes to GitHub/Storage.
Wrong files and destination races/symlinks are covered by7synthetic tests.
