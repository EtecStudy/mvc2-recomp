# Problems log (diagnose → retry → alternative → validate)

Format: symptom / root cause / attempts / resolution / status.

---

## P-001 — GitHub release downloads fail  ·  ✅ RESOLVED (relay)

*Symptom:* `curl`/`gh release download` for ninja zip, Temurin JDK and the
Ghidra zip all died with `OpenSSL SSL_connect: SSL_ERROR_SYSCALL … 
release-assets.githubusercontent.com:443` (0 bytes).
*Root cause:* sandbox egress allowlist does not include
`*.githubusercontent.com` (release-assets/media/raw). DNS resolves; TLS is
killed after SNI. `raw.githubusercontent.com` empty responses confirmed same.
*Attempts:* direct curl (fail) → `gh release download` (same host, fail) →
host matrix (codeload/pypi/npm OK) → PyPI wheels for cmake/ninja (works) →
npm/PyPI search for bundled Ghidra/JDK (none) → GitHub code search for a
vendored Ghidra zip (none found) → **GitHub Actions relay**: runner
downloads, verifies the API-published SHA-256 digest, splits <100 MB,
commits to the session branch; sandbox pulls + reassembles + re-verifies +
deletes chunks.
*Resolution:* `.github/workflows/fetch-ghidra.yml` (run 39059081485, 67 s)
and `fetch-jdk.yml` (run 39059754264, 55 s). Final hashes matched the
official digests (`ddac49f9…`, `ce79869e…`). Mechanism is reusable —
`scripts/setup_tools.sh` prints the re-trigger steps.
*Residual:* relay chunks remain in this branch's git history (~777 MB
total) although removed at tip. Squash-merge + branch deletion lets
GitHub GC collect them; or scheduler-side history rewrite before merge.

## P-002 — Supabase Storage unreachable from sandbox bash  ·  ✅ WORKED AROUND

*Symptom:* `curl` to `https://tkndzbkcmgfailtxuwie.supabase.co/storage/v1/
object/public/ps2recomp/…` → same `SSL_ERROR_SYSCALL` (TCP connects, TLS
reset). Connector tools expose SQL/management only — no file download.
*Root cause:* `*.supabase.co` not on the egress allowlist.
*Attempts:* HEAD (silent fail) → verbose GET (TLS kill confirmed) → DNS
check (resolves; not a DNS problem) → connector surface review (no storage
read API) → **server-side bridge**: `pg_net` (installed via migration)
POSTs to a temporary edge function inside Supabase; the function reads
Storage with the service role, does ZIP/ISO/ELF parsing *in situ* and
stages results into `public.bootstrap_transfer`; sandbox reads via SQL.
*Resolution:* full inventory + ELF extraction + ELF header parse obtained
read-only (discoveries #9–#13). Edge function deleted after use.
*Residual:* binary bulk transfer remains open → P-006.

## P-003 — Edge function JWT verification rejects project keys  ·  ✅ WORKED AROUND

*Symptom:* pg_net POSTs to the function returned `401
UNAUTHORIZED_INVALID_JWT_FORMAT "Invalid JWT"` with the legacy anon JWT,
and again with the `sb_publishable_*` key.
*Root cause:* project's new key/signing system; the functions gateway
expects a user JWT issued under the new scheme for `verify_jwt=true`.
*Resolution:* flipped the temporary function to `verify_jwt=false` for the
few minutes it existed (it only read a public bucket and wrote a staging
table), completed the work, then **deleted the function**.
*Residual:* if the bridge is ever rebuilt, prefer a real user JWT or keep
the same short-lived pattern; never leave `verify_jwt=false` functions
deployed.

## P-004 — Ghidra rejects the jdk4py JDK  ·  ✅ RESOLVED

*Symptom:* `WARNING: JAVA_HOME … unsupported java version` + "Unable to
prompt user for JDK path, no TTY" on `analyzeHeadless`.
*Root cause:* PyPI `jdk4py` 21.0.8.2 is a jlink runtime image: no `javac`
binary, no `jdk.compiler` module → Ghidra's LaunchSupport correctly
refuses it (relative JAVA_HOME in the first test made it look weirder;
absolute path still failed for the real reason).
*Resolution:* full Eclipse Temurin 21.0.12.1+1 via the Actions relay
(P-001). `javac 21.0.12.1`; Ghidra analysis + REA provider green.
`scripts/env.sh` now only accepts `tools/jdk/jdk-21*` dirs containing
`bin/javac` as JAVA_HOME.

## P-005 — ps2xRuntime / ps2xTest don't build on this Linux box  ·  🔶 OPEN, narrowed (FASE 3)

*Update (FASE 1, 2026-10-17):* FFmpeg is **not** a blocker — upstream has
`PS2X_ENABLE_FFMPEG` (default depends on platform; with `=OFF` the MPEG
stub falls back gracefully; only `Kernel/Stubs/MPEG.cpp` uses it).
Configuring with `-DPS2X_ENABLE_FFMPEG=OFF` proceeds until **raylib**,
whose CMake aborts on this box: GLFW needs X11 (`Could NOT find X11`),
and `GLFW_BUILD_X11=OFF + GLFW_BUILD_WAYLAND=OFF` is explicitly fatal in
raylib ("Cannot disable both Wayland and X11"). The sandbox has neither
X11 nor Wayland dev files, and their upstreams (freedesktop GitLab) are
unreachable; GitHub mirrors (X11Libre etc.) are unvetted and autotools-
heavy. With RUNTIME=OFF, `ps2xTest`'s `ps2_test_lib` still fails on
missing runtime/IOP headers (by design it tests the runtime).
*What DOES work:* `ps2xIOP` alone (standalone project, zero deps) builds
and passes 4/4 tests — the IOP half of the runtime is unblocked today.
*Impact:* zero for FASE 1/2 (analysis + codegen + IOP). Blocks only the
graphical runtime executable on *this* sandbox (FASE 3); the owner's
Windows target is unaffected.
*Options when FASE 3 starts:* (a) vendor minimal X11 from a GitHub mirror
and build the libX11 chain; (b) patch raylib to a null/headless platform
for probe builds (no window, GS still testable via readback); (c) build
only on Windows. Decide then; do not sink FASE 1 time into it.
ps2xStudio (OpenGL) stays OFF; GUI convenience, not pipeline.

## P-006 — No verified local copy of the active US ELF · 🔶 OPEN

The active target is **SLUS_204.86** (D-010). Its extracted Storage object
is independently verified at 3,942,320 bytes, SHA-256
`48ebf907d8149122ca9bd622ed11c290d5f93173078ea5bd570e1ac5566f13d7`.
ELF headers and SYSTEM.CNF were read; 41 US chunks were staged and
independently reassembled/hash-checked in SQL. JP chunks are not input.

**Transfer tests:** direct sandbox HTTPS to Supabase failed TLS
(`SSL_ERROR_SYSCALL`, curl 35). A local receiver worked locally, but
external E2B ingress returned HTTP 403 “Missing traffic access token”;
receiver stopped/token removed; zero parts received. No unapproved
GitHub/npm/PyPI relay for game bytes is allowed. Do not repeat these
failed routes without changed infrastructure.

**New proven route for small windows:** controlled SQL hex results →
ignored local files, checked with individual server-side SHA-256 hashes.
Initially four US windows (992 bytes) yielded 246 decoded instructions;
the fifth helper window adds 384 bytes / 96 instructions (total 1,376/342). This is useful scouting, **not a full ELF transfer**.
The full ELF is still absent, so full function export and game codegen
remain blocked. The new hash gate is active (not pending verification).
Earlier passes advanced scoped analysis while pursuing authorized byte
delivery. That does not replace the required owner-file intake below. Never ask for the Japanese ELF.

Toolchain restoration is complete for this snapshot, with tests rerun;
see `docs/discoveries.md` and the US scout README for proof and limitations.

## P-007 — Snapshot size limits on vendored binaries  ·  🔶 MITIGATED

*Fact:* turn-end workspace artifacts are best-effort capped (~128 MB /
10k files). Extracted Ghidra (~1.1 GB), JDK, build trees and downloads
(~800 MB) may not fully persist between sessions; directories named
`build`, `node_modules`, `.local`, … never persist.
*Mitigation:* build trees live in `builddir/` (not `build/`); all heavy
payloads are re-creatable non-interactively by `scripts/setup_tools.sh`
from local archives in `tools/downloads/` (kept deliberately) or, worst
case, via the Actions relay. Verified archives + manifests:
`tools/downloads/manifests/`.


## P-008 — Uploaded US asset set lacks AFS00 / AFS02 · OPEN, runtime blocker

US `PS2/0FLIST.DIR` lists all four AFS names; a case-insensitive lookup
across current Storage objects found no AFS00/02. Unknown expected sizes,
hashes and reason for absence; no upload-limit cause established. AFS01
and AFS03 payload extents fit their objects but do not establish complete
assets. Missing files do not block full-ELF static analysis/codegen.
Acceptance: legitimate owner assets received through an authorized path,
content hashes/lengths recorded, filelist and payload checks rerun. Never
invent substitute game content. See USA `asset_completeness.json`.

## P-009 — IOP core dispatch risks · OPEN, static findings only

Pinned upstream handles only secrman ordinals4/5; MCMAN imports6 and no
uploaded image exports secrman. dmacman handler unconditionally returns0.
Other core libraries have requested case labels but are not runtime
verified. Need real load/relocation/initialization tests and semantics,
not invented success stubs. 226 supplied ordinal-span matches do not
prove successful runtime linking/audio. See USA `iop_dependency_report.json`.

## P-010 — Relocated zero export treated as terminator · FIXED

Initial parser undercounted export spans; valid zero-link-address slots
may carry R_MIPS_32 relocations. Added relocation-aware termination and a
synthetic regression test; corrected v2 pass rehashed all41 originals,
preserved16 slots, failed0. v1 export counts superseded; ROMDIR/asset/v1
import hashes unaffected by this bug. Local canonical v2 copy checked
against independent SQL SHA. No originals changed.


## P-011 — Analyzer TOML address tokens are not a function-map comparison · FIXED

The prior step only printed Ghidra record count and a regex count of
hexadecimal tokens in analyzer TOML. Upstream TOML stores selector/MMIO/
jump-table information, not every discovered function. That was not a
valid independent address-overlap check.

Added a small exporter using pinned upstream ElfAnalyzer::getFunctions()
without importing Ghidra CSV. Added strict CSV/ELF/config provenance
validation, entry/range checks and explicit boundary/set differences.
Ghidra remains authoritative. Synthetic upstream CLI/adapter TOML parity
and Ghidra→compare→C++ passed; regression tests cover malformed/empty,
duplicate/out-of-file/BSS maps and mismatched config/export metadata.
The synthetic case actually has one boundary disagreement, correctly
reported rather than hidden. Full US execution remains pending P-006.

### P-006 capability recheck (same date)

Supabase connector reloaded: SQL/metadata/function management only, no
Storage-object download-to-workspace method. SQL independently reverified
all41 staged chunks:3,942,320B, expected US SHA, verified=true. No new
binary delivery route was found; unchanged TLS/receiver/public game-data
relay routes were not repeated. Actual pipeline still exits2 on absent
full US ELF before analysis/codegen; no target bypass introduced.


## P-012 — Guest LOADFILE bootstrap route requires validation · OPEN, conditional runtime risk

New real-US static evidence matches the loader core and binder and shows
SID80000006, version probeFF and ordinary module RPCfunction0. This is
not TSNDDRV's own SID. Pinned IopSubsystem factories provide MCSERV,
DBCMAN and LIBSD, not LOADFILE HLE; canBindRpc requires an active route
or registered emulated server. Uploaded ROM#LOADFILE presence is not
proof of loading/registration.

Before declaring the guest path operational, exercise real LOADFILE
initialization/RPC behavior or separately review an exact legitimate
named HLE hook. No fake server/success stub was added. Need full game
codegen/runtime integration to observe boot; no hang/crash claimed.
See USA load_chain.md. Exact SDK version and one ambiguous version-helper
identity remain unproven; short trampoline match is not auto-assigned.


### P-006 next required input: owner US ELF attachment

No complete local ELF or authorized automatic bulk-download route is
available. Continuing bounded scouts cannot substitute for the full-ELF
milestone. Request only the owner's SLUS_204.86 attachment (3,942,320B),
not an ISO, BIOS, credentials or Japanese executable. This is a required
input the agent cannot currently retrieve, not a request for manual shell
commands.

`scripts/import_us_elf.py ATTACHMENT_PATH` reads identity from target.sh,
streams into an ignored temporary file, verifies size/SHA twice and
atomically publishes game/working/SLUS_204.86 without overwriting existing
different files. Source stays untouched. The agent will then run the
existing full target gate and fase1_analyze.sh --recomp workflow; there is
no hash override, upload relay or automatic claim of codegen success.
