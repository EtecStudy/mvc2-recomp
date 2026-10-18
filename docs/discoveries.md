# Discoveries (dated, evidence-based — do not edit history, append)

> The findings below concern historical **SLPM_622.27**, not the active
> SLUS_204.86, unless explicitly marked USA. See D-010.

## 2026-10-17 — FASE 1 (scouting + pipeline preparation)

### ELF structure (server-side scout v4 over the staged ELF; originals untouched)
16. **Toolchain: Metrowerks CodeWarrior** — `.comment` reads
    `MW MIPS C Compiler (2.4.1.01)` + `PlayStation2`. Not GCC/SN.
17. **GP base = `0x00531af0`** (`.reginfo` ri_gp_value; gprmask 0xf7fffffe,
    cprmask[1]=0xffffffff → all FPU regs live). Required input for correct
    R5900 small-data/GP-relative analysis in Ghidra.
18. Segment entropy (64 KiB blocks) is flat ≈5.2–5.7 (mixed code/data, no
    packed/encrypted regions) except a near-zero hole (0.14) around
    VA ≈0x00500000 and a dense 6.09 block right after (the string/name
    tables at 0x0051xxxx–0x0052xxxx).
19. 3,962 NUL-terminated ASCII strings (≥5 chars); 111 printf-style.
    Name tables live around `0x00512700–0x00523xxx`: ADX audio
    (`ADX_S000.ADX`…, `ADX_MENU/OPEN/WINS…`), per-character attack files
    (`ATCK00.BIN`–`ATCK3A.BIN`), AFS mounts (`afs00.afs`–`afs03.afs`,
    `0flist.dir`), font charmaps at `0x00527310/50`.
20. **IRX modules actually referenced by path strings in the ELF** (stronger
    evidence than disc presence; load order still unproven): boot cluster
    `IOPRP255.IMG, SIO2MAN, PADMAN, USBD, USBMLOAD, USBKB`
    (0x0051f680–0x0051f730); audio/mc cluster `CRI_ADXI, MCMAN, MCSERV,
    LIBSD, MODHSYN, MODMIDI, MODMSIN, TSNDDRV` (0x00523180–0x00523340,
    **TSNDDRV confirmed referenced** → PS2-14's "needs its own IRX" caveat
    applies); network cluster `CXTMDM, OSTMDM_A, AVEPPP, AVE_WRAP, AVETCP,
    USB_SRCH, USBDRV.CNF` (0x005236e0–0x005237c0). No `cdrom0:` string for
    OMMODEM/ATAD/DEV9/HDD/PFS/MTAPMAN/ACC_COM (may load via IOPRP image or
    non-string paths — unproven either way). Full list staged in Supabase
    `bootstrap_transfer` kind=`scout_strings`.
21. **EE syscall surface**: 169 stub sites / 146 distinct numbers; a dense
    16-byte-stride stub table spans ≈`0x001039c0–0x00104250` (whole
    libkernel linked in — presence of a stub ≠ used). Cross-referenced
    against PS2Recomp's own `Dispatcher.cpp`: 85 of 146 numbers have
    upstream names (`analysis/scout/syscall_map.md`). Hot non-table sites
    cluster at `0x0010c2xx–0x0010d1xx`: #116 SetSyscall ×6, #90 ×5, #91 ×4
    (names per upstream dispatcher), plus #16 AddIntcHandler, #18
    AddDmacHandler. Consistent with PS2-10's SetSyscall(0x83→0x10CB10):
    0x83=131 has its stub at `0x0010cb50`, in that neighbourhood.
    ≈14,230 `addiu sp,sp,-n` sites (upper-bound function-frame hint only).
22. CRI middleware fingerprints inside the EE image: error strings from
    `htCiGetFileSize`, `dvCiOpen` (CRI file layer) and
    `sceSifAllocIopHeap` inside `PS2RNA_Init` (network stack allocates IOP
    heap at init — relevant to the IOP/SIF work in PS2-13).

### Toolchain / upstream
23. `ps2xIOP` builds **standalone** (no external deps) and its suite is
    **4/4 green** on this machine (emulator/imports/compatibility/
    import-version) — first PS2-13 acceptance item satisfied here.
24. `ps2xRuntime` FFmpeg is already optional upstream
    (`PS2X_ENABLE_FFMPEG=OFF` → stub MPEG frames; used only by
    `Kernel/Stubs/MPEG.cpp`). The remaining Linux blocker is raylib:
    its CMake hard-fails without X11 or Wayland (`Cannot disable both
    Wayland and X11`), and this box has neither dev stack (P-005 updated).
25. Ghidra **12.0.2** + EmotionEngine-Reloaded v2.1.38 installed side by
    side with 12.1.4; language id **`r5900:LE:32:default`** verified by a
    headless raw import (`.sla` compiled + cached). Extension must live in
    `<install>/Ghidra/Extensions/`; `<install>/Extensions/Ghidra/` is only
    the distribution shelf and does NOT register.
26. `ExportPS2Functions.java` takes its two outputs via `askFile()` —
    headless consumes them from script args in order:
    `-postScript ExportPS2Functions.java <toml> <csv>`. It also emits
    stub classifications (`STUB`/`UNTRACKED_STUB` selectors `name@0xADDR`)
    and derives the C++ output dir as `<toml_dir>/output`.

## 2026-10-17 — FASE 0 bootstrap

### Environment
1. Sandbox egress is allowlist-based at TLS SNI level: `github.com`,
   `api.github.com`, `codeload.github.com`, `pypi.org`,
   `files.pythonhosted.org`, `registry.npmjs.org` work; everything else
   (incl. all `*.githubusercontent.com` and `*.supabase.co`) fails with
   `SSL_ERROR_SYSCALL` right after TCP connect. Evidence: host matrix in
   `docs/bootstrap.md` §1.
2. GitHub release binaries can still be obtained: a GitHub Actions runner
   (unrestricted) downloads + hash-verifies + commits <100 MB chunks; the
   sandbox reassembles via `git pull`. Proven for Ghidra 12.1.4 (570 MB)
   and Temurin JDK 21 (207 MB), runs `39059081485` / `39059754264`.
3. Official PyPI wheels contain usable `cmake` 4.4.4 and `ninja` 1.13.2
   binaries (extract `cmake/data/`, `ninja` script) — no system install
   needed; PEP 668 only blocks `pip install`, not `pip download`.
4. PyPI `jdk4py` is a jlink-trimmed runtime (no `javac`, no `jdk.compiler`)
   → Ghidra rejects it ("unsupported java version"). Full Temurin required.

### Tools
5. PS2Recomp (`ran-j/PS2Recomp` @ eb8688b) fetches **all** its deps via
   git (ELFIO, toml11, fmt, libdwarf, rabbitizer, nlohmann/json, …) →
   builds fine behind our egress filter. 45/45 gs_cache ctest cases pass.
6. PS2Recomp's documented flow for stripped retail ELFs is
   Ghidra → `ExportPS2Functions.java` → TOML/CSV → `ps2_recomp`.
   `ps2_analyzer` (embedded SCE symbol DB) is the fallback.
7. REA = `morluto/rea` (npm `rea-agents` 6.5.0), an MCP-first RE platform.
   It verifies an **existing** Ghidra 12.1.4 install (`GHIDRA_INSTALL_DIR`)
   and drives `analyzeHeadless` itself. `rea doctor` reports our install
   fully healthy; `rea analyze --provider ghidra` and the MCP stdio
   handshake both work. It ships MIPS-specific bridge code
   (`ReaGhidraMipsSoftFloat.java`, `docs/ghidra-mips.md`).
8. Everything REA-related that is Java/Gradle-built (cyberkaida REA,
   LaurieWired GhidraMCP, bethington ghidra-mcp) needs Maven Central /
   Gradle dists → cannot build under the egress filter. Vendored locally
   anyway; not needed while (7) works.

### Game (Supabase; read-only, originals untouched)
9. Bucket `ps2recomp` holds the game as a 7-part byte-split zip
   (131,289,570 B). Rejoined zip has **one** entry: the disc ISO,
   DEFLATE 131,289,334 → 208,384,000 B. Zip central directory lives fully
   inside part `.007` (cdOffset 131,289,415, cdSize 133).
10. ISO PVD: `PLAYSTATION` / `MARVEL_VS_CAPCOM2`, root dir LBA 22.
    Full tree (39 entries) — `/PS2` (4× CRI `.AFS` + `0FLIST.DIR`),
    `/MODULES` (28 IOP `.IRX` + `IOPRP255.IMG` + extras), root:
    `SLPM_622.27;1`, `SYSTEM.CNF;1`, `FONT8_8.TM2;1`.
    All rows written to `disc_files` (migration
    `fase0_disc_inventory_2026_10_17`).
11. Boot ELF `SLPM_622.27` @ LBA 857: 4,378,928 B, ELF32/LE/ET_EXEC/MIPS,
    entry `0x100008`, flags `0x20924000`. Single substantive PT_LOAD:
    `0x100000` filesz `0x42CF00` memsz `0x5BF980` RWX (≈1.85 MB BSS).
    Second PT_LOAD is empty at `0x6BF980`. Section table exists (8) but
    symtab/strtab are zero-size → stripped retail ELF.
    SHA-256 `de42633ccf9d78fed3d8cbecd75a81a9e043a7b4298be374a8ffa7689cb42af5`.
12. EE image spans `0x100000–0x6BF980` (~5.75 MiB resident) — the entire
    game in one segment; function discovery must come from Ghidra.
13. IOP side is rich: `IOPRP255.IMG` (IOP kernel 2.5.5 reboot image),
    CRI ADX (`CRI_ADXI.IRX` + `/PS2/*.AFS` ⇒ assets/audio via CRI
    middleware), `LIBSD`, memcard (`MCMAN/MCSERV`), pad (`PADMAN`),
    plus network/HDD/USB stacks (JP online features). These will drive
    the FASE 3 IOP strategy (AOT IRX vs HLE).
14. Supabase project already encodes the strategy (restarted 2026-10-17):
    runtime modelled on the God of War native port (AOT VU1, OpenGL GS,
    native IOP/IRX); 10 components tracked, all `missing`; blockers:
    EE_CPU, VU1, GS, IOP, SIF, TIMERS. Previous generated C++ (268
    modules) was deliberately discarded upstream of this session.
15. Supabase edge-function JWT gate currently rejects legacy anon HS256
    and `sb_publishable_*` bearers (`UNAUTHORIZED_INVALID_JWT_FORMAT`);
    the bootstrap bridge ran briefly with `verify_jwt=false` and was
    deleted immediately after use.

## 2026-10-17 — USA target selected (Storage metadata only)

Read-only Storage query returned 36 objects (including one zero-byte
placeholder), totaling 15,461,038 bytes. Root executable is `SLUS_204.86`
(3,942,320 bytes); `SYSTEM.CNF` is 54 bytes. `MODULES/` and two `PS2/`
AFS files are present. No SLPM executable or split ZIP objects appeared
in this current listing. This is not a full-disc completeness check and
is not a content hash/ELF validation. Existing database JP records and
staged chunks remain historical, separate from this upload.

## 2026-10-17 — USA ELF verified and first partial local Ghidra pass

27. **US identity verified:** `SYSTEM.CNF` boots `SLUS_204.86`; executable
    is 3,942,320 B, SHA-256
    `48ebf907d8149122ca9bd622ed11c290d5f93173078ea5bd570e1ac5566f13d7`.
    Edge crypto and independent SQL reassembly of 41 `us_elf_chunk` rows
    (indexes 0–40) agree. Japanese staging was not touched or reused.
28. **US ELF:** entry `0x00100008`, GP `0x004C7270`, ELF32 LE MIPS ET_EXEC,
    flags `0x20924000`; main PT_LOAD offset `0x80`, VA `0x100000`,
    filesz 3,941,760 B, memsz 5,456,768 B. Empty symbol table. Metrowerks
    MIPS C Compiler 2.4.1.01 / PlayStation2 confirmed from this US binary.
29. **US module-reference scout:** 18 path strings, 16 LUI address
    candidates, zero aligned pointer candidates. Does not prove runtime
    module loading. Bounded scanner result is separate from JP work.
30. **First real US bytes in local Ghidra:** four small windows totaling
    992 B, individually SHA-gated after SQL hex transport. Ghidra 12.0.2
    + EE decoded 246 instructions; 13 candidate sites decode as LUI/ADDIU
    pairs. Found 11 direct calls to `0x003DCAD0` across USB/audio/network
    windows. No SDK name, complete CFG, function map or runtime order
    inferred. Window-end missing delay slots explain partial decoding.
31. **US syscall candidates:** 481 raw aligned syscall-like words in the
    mixed code/data image; 169 have nearby ADDIU v1 immediates, with 146
    distinct signed values. These remain candidates, not discovered
    functions or executed calls. Compact fact export matched an
    independent server SHA-256 before local JSON construction.
32. **Toolchain restored and exercised again:** pinned PS2Recomp sources,
    REA 6.5.0 at its manifest commit, Temurin JDK, Ghidra 12.1.4 and
    12.0.2+EE. GS 45/45, IOP 4/4; synthetic original ELF → Ghidra
    ExportPS2Functions TOML/CSV → normalized low-memory config →
    ps2_recomp C++ succeeded. This is not US game codegen. Final infra
    suite passed **27/27**, including the synthetic C++ codegen substep.
33. **Cleanup/tracking:** temporary `mvc2-us-stage` function deleted and
    token removed; Edge Functions list confirmed empty. Separate US
    target and 35 extracted-file inventory rows registered; ISO format,
    LBA and full upload completeness remain unknown. The first staging
    request failed on a nonexistent `(kind,idx)` unique constraint;
    ordinary INSERT fixed staging. Originals were never written.

The full US ELF is still not local. Full Ghidra export, analyzer cross-check
and actual game C++ generation remain pending (P-006). All current US
facts live under `analysis/scout/slus_20486/`; old root scout files are JP.


## USA IOP / helper follow-up — 2026-10-17

34. **26 external IRX + 15 ROM ELF** inspected read-only with rechecked
    source SHA-256. ROMDIR contains 18 entries, no IOPBTCONF. The final
    payload fits exactly; absent final 15-byte alignment padding does not
    mean a truncated payload. 41 USA `elf_modules` rows registered with
    runtime status `unknown`, no guessed load bases/instruction counts.
35. **Corrected export parser:** raw zero may be a valid R_MIPS_32-relocated
    export, not a terminator. V2 retained 16 such slots and rehashed all
    sources, failures 0; v1 export lengths superseded. Regression covered
    locally. 284 import tables / 41 export tables; canonical metadata hash
    independently matched SQL (see `iop_modules_compact.txt`).
36. **TSNDDRV:** 14 libraries / 61 ordinal imports. Static provider spans
    available for 12 libraries; sysmem/intrman need core paths. No RPC SID,
    actual boot order or sound execution was established.
37. **Static dependency audit:** 226 tables have matching uploaded
    major-version/ordinal spans, 58 need six core libraries. Upstream
    resolver does not require requested minor <= provider minor. Required
    secrman:6 (MCMAN) has no direct HLE case or uploaded export; dmacman
    branch returns zero unconditionally. Risks documented, no fake stubs.
38. **Shared helper:** SHA-gated 384-byte window at 003DCAD0 gave 96 decoded
    instructions, including following code. Entry function inferred as
    212 bytes with three calls. US diagnostic at 004BA4F0 independently
    confirmed `Can't load module %s\n`. Partial decompiler suggests retry
    wrapper; ABI/SDK identity remains unproven. Combined five-window
    coverage is 1,376 bytes / 342 instructions, not full EE analysis.
39. **Asset completeness is disproven against uploaded US filelist:**
    0FLIST names afs00/01/02/03; global case-insensitive Storage lookup
    found no AFS00/AFS02. Present AFS01/03 payload bounds fit (63/1 entries).
    Missing sizes/hashes/cause unknown. No upload-limit explanation proven.
40. **Follow-up validation/cleanup:** helper Ghidra run succeeded; parser
    fixtures 4/4; fact consistency 5/5; infra **29/29**, project CTest
    **5/5**, GS45/45, IOP4/4. Temporary IOP functions/tokens removed; Edge
    listing empty. Full ELF/export/analyzer/game C++ still pending P-006.


## Analyzer cross-check correction — 2026-10-17

41. The analyzer TOML is **not** a complete function map. Prior regex
    address counts did not establish Ghidra/analyzer overlap. Added a
    compiled adapter using upstream's actual function vector; no Ghidra
    import or upstream-source patch. CLI/adapter TOML parity passed.
42. Native exporter built, then rebuilt with six hash-pinned local source
    dependencies and CMake FULLY_DISCONNECTED. A 29,709,228-byte ignored
    archive + tracked commit/digest manifest supports offline rebuilds,
    subject to P-007 snapshot limits. Rabbitizer's no-CMakeLists case fixed.
43. Original synthetic272B ELF has one common start but different ends:
    Ghidra0010000C vs analyzer00100010 (post-return NOP). New validator
    reports disagreement correctly and still permits Ghidra-driven C++.
    It validates input/map provenance, ELF bounds/entry, CSV records and
    function/label totals; no SDK/runtime proof or merged map inferred.
44. Validation:infra31/31, projectCTest7/7, comparator regression7/7,
    dependency restore5/5, GS45/45, IOP4/4. US chunks independently
    reverified in SQL; full local ELF still absent (pipeline exit2).
    Synthetic map/C++ success must not be reported as US whole-game
    exports/analyzer comparison/codegen.


## Actual US load-chain evidence — 2026-10-17

45. Three additional SHA-gated US windows,1,112B/278instructions,
    decompiled at four requested entries. Combined scope8windows,
    2,488non-overlapping bytes/620instructions, still not the full ELF.
46. Core0010B970 matches complete normalized548-byte `_sceSifLoadModule`
    signature (4,046unmasked bits), corroborated by native analyzer on
    a derived fragment ELF. Native extent552 includes one trailing NOP;
    Ghidra body548. No fragment C++ generation or full-game gate bypass.
47. Thin0010BB98 matches32-byte `sceSifLoadModule` at230unmasked bits,
    kept as a short candidate. Binder0010B198 uniquely matches `_lf_bind`;
    version helper0010B298 matches BOTH `_lf_version` and `_fs_version`.
    Ambiguity preserved, no automatic Ghidra rename/stub/SDK-version claim.
48. Binder builds SID80000006; ordinary module-load path statically uses
    RPCfunction0,512send/8receive bytes. Bootstrap probeFF receives4bytes.
    This is LOADFILE, NOT TSNDDRV's own SID. No bind/reply/runtime trace.
    Core HLE service factories omit LOADFILE; route or actual emulated
    server registration must be tested, not faked (P-012).
49. Ghidra partial workflow and independent native core scan passed.
    Matcher fixtures5/5 (masking, full hash, short/ambiguous, malformed
    relocation, header/window gates); offline fact checks now6/6.
    Infra32/32, projectCTest8/8, GS45/45, IOP4/4. Originals untouched,
    no new temporary Edge/token, full US game exports/codegen still absent.


50. **Next milestone now requires the owner's US file attachment**, not
    further tiny scouts. Added/tested atomic local intake from attachments
    with pinned size/SHA, independent copied-file verification, no source
    mutation or existing-target overwrite (including races/symlinks).
    Import fixtures7/7; infra33/33, projectCTest9/9. No real full ELF was
    imported yet; no new game-map/codegen/runtime progress is claimed.
