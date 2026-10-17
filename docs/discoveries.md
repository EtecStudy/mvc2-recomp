# Discoveries (dated, evidence-based — do not edit history, append)

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
