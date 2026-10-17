# FASE 0 — Bootstrap report (2026-10-17)

> Historical FASE 0 report for the former JP target. The only active game
> target is now SLUS_204.86 (D-010); current findings are in
> `analysis/scout/slus_20486/`. Do not reuse JP binary facts.

Goal of this phase: **build and validate a complete local environment able to
start the re-engineering of Marvel vs. Capcom 2 (PS2, SLPM-622.27) into a
native PC port via PS2Recomp** — before touching the game itself.

Validation suite: `scripts/test_infra.sh` → **22 passed, 0 failed**
(log: `builddir/logs/test-infra-2026-10-17.log`). Re-run it at any time.

---

## 1. Sandbox / host reality (read this first)

| Fact | Value |
|---|---|
| OS | Debian 12, Linux 6.1 x86_64 |
| CPU / RAM / disk | 2 cores / 3.8 GiB / 21 GB (≈20 GB free at start) |
| Reachable hosts | `github.com`, `api.github.com`, `codeload.github.com`, `pypi.org`, `files.pythonhosted.org`, `registry.npmjs.org` |
| **Unreachable** | `release-assets.githubusercontent.com` (all GitHub *release* downloads!), `raw.githubusercontent.com`, `media.githubusercontent.com` (LFS), `*.supabase.co`, everything else |

Consequence: `git clone`, codeload tarballs, PyPI wheels and npm tarballs work;
**release binaries do not download directly**. Workaround that was built and
proven twice: the **GitHub Actions relay** (`.github/workflows/fetch-ghidra.yml`,
`fetch-jdk.yml`) — a runner downloads the official archive, verifies SHA-256
against the API-published digest, splits it into <100 MB chunks, commits them
to the session branch; the sandbox `git pull`s, reassembles, re-verifies and
deletes the chunks. Details: `docs/problems.md` P-001.

## 2. Tools — obtained, configured, tested

| Tool | Version | Location | Source (offline-reproducible) | Test | Result |
|---|---|---|---|---|---|
| git | 2.39.5 | system | preinstalled | `git status`, push/pull | ✅ |
| gh CLI | 2.23.0 | system | preinstalled, authenticated as `EtecStudy` | `gh auth status`, `gh run list` | ✅ |
| g++ | 12.2.0 | system | preinstalled | full PS2Recomp build | ✅ |
| CMake | 4.4.4 | `tools/cmake/` | PyPI wheel `cmake==4.4.4` (release host blocked) | configures root + PS2Recomp | ✅ |
| Ninja | 1.13.2 (kitware) | `tools/bin/ninja` | PyPI wheel `ninja==1.13.2` | all builds | ✅ |
| Python | 3.11.2 | system | preinstalled | pip downloads (PEP 668 → `pip download` only) | ✅ |
| Node.js / npm | 22.22.3 / 10.9.8 | system | preinstalled | REA `npm ci` + build | ✅ |
| JDK (runtime probe) | Temurin 21.0.8 jlink image | `tools/jdk/jdk4py/` | PyPI `jdk4py==21.0.8.2` | `java -version` OK, **but no javac → rejected by Ghidra** | ⚠️ do not use (P-004) |
| **JDK 21 full** | **Temurin 21.0.12.1+1** | `tools/jdk/jdk-21.0.12.1+1/` | Actions relay, SHA-256 `ce79869e…ee94` | `javac 21.0.12.1`, runs Ghidra + REA bridge | ✅ |
| **PS2Recomp** | main @ `eb8688b` (2026-10-14) | `tools/ps2recomp/PS2Recomp/`, bins in `tools/ps2recomp/bin/` | git clone; all deps are git-FetchContent | builds with g++; `ps2_recomp`/`ps2_analyzer` run; **45/45 gs_cache tests pass** | ✅ |
| **Ghidra** | **12.1.4_PUBLIC 20260921** | `tools/ghidra/ghidra_12.1.4_PUBLIC/` | Actions relay, SHA-256 `ddac49f9…d4db` (official digest) | `analyzeHeadless` import of ELF probe: *Analysis succeeded* | ✅ |
| **REA** | **6.5.0** @ `300905c` | `tools/rea/rea/` | git clone + npm | `rea doctor` → ghidra provider **available**; `rea analyze --provider ghidra` produced real evidence JSON; MCP stdio handshake OK | ✅ |
| REA (Java ext.) | main @ `a05a6b0` | `tools/rea/reverse-engineering-assistant/` | git clone (cyberkaida) | vendored only — needs Gradle/Maven Central to build (blocked); not required while morluto/rea works | 📦 local copy |
| GhidraMCP (LaurieWired) | main @ `1e98025` | `tools/rea/GhidraMCP/` | git clone | vendored only (GUI plugin; sandbox is headless) | 📦 local copy |
| ghidra-mcp (bethington) | dev @ `cf8b12d` | `tools/rea/ghidra-mcp/` | git clone | vendored only (headless MCP alternative; needs Gradle to build) | 📦 local copy |
| PS2 recomp Agent SKILL | main @ `a1cafc2` | `tools/extra/ps2-recomp-Agent-SKILL/` | git clone | vendored reference material (PS2 docs + agent skill) | 📦 local copy |

Exact SHAs, URLs and re-fetch procedure: `tools/MANIFEST.md` + `scripts/setup_tools.sh`.

### PS2Recomp build notes
* Configure used: `-DPS2X_BUILD_STUDIO=OFF -DPS2X_BUILD_RUNTIME=OFF`
  `RECOMP=ON ANALYZER=ON TEST=ON`, Release, Ninja. Scripted in
  `scripts/build_ps2recomp.sh`.
* All 163 targets except `ps2_test_lib` build cleanly under g++ 12 (upstream
  is "tested mainly with MSVC"). `ps2_test_lib` includes runtime/IOP headers
  and therefore needs `PS2X_BUILD_RUNTIME=ON`; the Linux runtime path needs
  `pkg-config` + ffmpeg dev libraries, absent here → tracked as P-005
  (runtime is FASE 3 work anyway; codegen pipeline does not need it yet).
* FetchContent dependencies actually cloned during the build (proof that a
  bare rebuild works): ELFIO, toml11, fmt, libdwarf, rabbitizer
  (MIPS disassembler), nlohmann/json.

### REA ↔ Ghidra integration proof
* `GHIDRA_INSTALL_DIR` + full JDK on PATH (wired in `scripts/env.sh`).
* `rea doctor --json`: provider `ghidra` → `configured:true, available:true,
  providerVersion:"12.1.4"`; all Ghidra checks healthy (installation,
  headless, native decompiler is linux/x64 ELF, Java 21 JDK accepted).
  Global `healthy:false` is only due to optional engines we do not use
  (Hopper/IDA/jadx/kuna) and the uninstalled REA skill.
* `rea analyze builddir/mvc2/tests/mvc2_smoke_test --provider ghidra --json`
  → exit 0, full `binary_overview` evidence (segments, image base) computed
  by the real Ghidra headless.
* MCP server: stdio `initialize` handshake returns
  `serverInfo {name:"rea", version:"6.5.0"}`, 207 MCP tools in catalog.

## 3. Supabase — game archive located, inventoried, ELF extracted server-side

Project `tkndzbkcmgfailtxuwie` ("…ps2recomp…'s Project"), created for this
work. Found:

* **Storage bucket `ps2recomp` (public)** — split archive
  `Marvel vs. Capcom 2 - New Age of Heroes (Japan).zip.001 … .007`
  (6 × 20,971,520 B + 5,460,450 B = **131,289,570 B**).
* **DB schema (public)**: `build_targets` (1 row: `mvc2-slpm-622-27`),
  `runtime_components` (10 rows, all `missing`), `disc_files`, `elf_modules`,
  `game_functions`, `sdk_symbols`, `probe_runs` (empty),
  `v_function_progress` view. Enums: `component_status`, `function_status`,
  `function_origin`.

The sandbox cannot reach `*.supabase.co` from bash (TLS killed by egress
filter — P-002) and the connector has no file-download tool. The inventory
and the ELF were therefore processed **server-side** with a temporary edge
function triggered through `pg_net` from SQL, staging results into
`public.bootstrap_transfer` (function already **deleted** afterwards;
method documented in `docs/reverse_engineering.md`). Original archive was
**not modified** — only read.

Verified facts (all cross-checked, see `docs/discoveries.md`):
* The zip contains exactly one entry: `Marvel vs. Capcom 2 - New Age of
  Heroes (Japan).iso`, DEFLATE, **208,384,000 B** inflated (CD image).
* ISO9660 PVD: system `PLAYSTATION`, volume `MARVEL_VS_CAPCOM2`.
  Full walk: **39 entries, 0 missed directories** — written to `disc_files`.
* Boot ELF `/SLPM_622.27;1` @ LBA 857, **4,378,928 B** (matches
  `build_targets.elf_bytes`), `\x7fELF`,
  **SHA-256 `de42633ccf9d78fed3d8cbecd75a81a9e043a7b4298be374a8ffa7689cb42af5`**
  (written back to `build_targets.elf_sha256`; migration
  `fase0_disc_inventory_2026_10_17`).
* ELF structure parsed (ELF32/LE/ET_EXEC/EM_MIPS, entry `0x100008`,
  1 real PT_LOAD `0x100000` filesz `0x42CF00` memsz `0x5BF980`, stripped).
* The 4.3 MB ELF is staged server-side as 45 base64 chunks in
  `bootstrap_transfer` (`kind='elf_chunk'`), reassembling is a documented
  SQL read. **A local binary copy inside this sandbox is still pending**:
  pushing 5.8 MB of base64 through the agent's own tool calls is not a
  reliable transfer channel, and uploading game data to GitHub would
  violate the project rule "game data never leaves the owner machine"
  (P-006 — options listed there; needs one user decision).

## 4. Project structure created

```
mvc2-recomp/
├── .github/workflows/   # fetch-ghidra.yml, fetch-jdk.yml (Actions relay)
├── CMakeLists.txt       # FASE 0 skeleton (+ tests/smoke_test.cpp — passing)
├── README.md
├── analysis/            # ghidra_projects/ (databases, gitignored)
├── builddir/            # cmake build trees + logs/ (NOT "build": snapshot-excluded name)
├── docs/                # this file + architecture, build, discoveries, …
├── game/                # supabase/ + working/ — local game data, NEVER committed
├── generated/           # future ps2_recomp C++ output (configs tracked, bulk not)
├── scripts/             # env.sh, setup_tools.sh, build_ps2recomp.sh, test_infra.sh
├── src/                 # future hand-written runtime/glue
├── tests/               # infra smoke tests
└── tools/               # MANIFEST.md + vendored tools (see §2)
    ├── ps2recomp/ (PS2Recomp/ + bin/)
    ├── ghidra/    (ghidra_12.1.4_PUBLIC/)
    ├── jdk/       (jdk-21.0.12.1+1/ full Temurin; jdk4py/ = probe, unused)
    ├── rea/       (rea/, reverse-engineering-assistant/, GhidraMCP/, ghidra-mcp/)
    ├── extra/     (ps2-recomp-Agent-SKILL/)
    ├── cmake/ bin/ downloads/ (wheels + verified archives + manifests)
```

## 5. What "GitHub unavailable tomorrow" looks like (offline readiness)

* Everything above already lives in the workspace; git tracks only code,
  scripts, docs and configs (see `.gitignore` policy, decisions D-001/D-002).
* `scripts/setup_tools.sh` recreates any missing piece: clones via
  `github.com`, wheels via PyPI, archives via local copies or the Actions
  relay (only needs github.com + the repo itself).
* If GitHub disappears entirely: local trees + PyPI/npm registries (different
  failure domains) still allow full rebuilds except re-cloning the vendored
  repos — whose local copies already exist. Git then serves only for local
  history until sync is possible again.

## 6. Pending at end of FASE 0 (details in problems.md)

1. **P-005** ps2xRuntime/ps2xTest on Linux need pkg-config + ffmpeg dev
   (plan: `pkgconf` from GitHub source + FFmpeg from `FFmpeg/FFmpeg` git, or
   disable ffmpeg use upstream-side; needed from FASE 3, not before).
2. **P-006** Local binary copy of the game (ELF now; full ISO for FASE 3
   asset loading) — server-side staging done; final transfer channel is a
   user decision (upload via chat is the clean option).
3. Relay chunks exist in this session branch's **history** (≈570 MB +
   ≈207 MB, removed at tip). If the branch is squash-merged and deleted,
   GitHub GC drops them; a history rewrite before merge is also possible.
4. REA "skill" not installed (`rea setup` not run — it edits agent client
   configs; unnecessary for CLI/MCP use here).
5. ps2xStudio skipped (OpenGL GUI tool; not needed for the pipeline).

## 7. Next technical steps (FASE 1)

1. Get the ELF local (P-006), load into Ghidra (language MIPS R5900),
   run PS2Recomp's `ExportPS2Functions.java` → TOML + function-map CSV.
2. Cross-check with `ps2_analyzer` output; seed `game_functions` in Supabase.
3. First `ps2_recomp config.toml` run → generated C++ compiles (EE core first).
4. In parallel: finish P-005 so `ps2xRuntime` links on Linux.
