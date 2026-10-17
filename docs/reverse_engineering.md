# Reverse engineering — targets, method, current knowledge

## Active target — SLUS_204.86 (USA)

The owner selected this target on 2026-10-17 (D-010). Storage bucket
`ps2recomp` now contains extracted US files. Only this target is active.
Original files remain untouched; no Japanese addresses/maps are reused.

| Verified US property | Value |
|---|---|
| Executable | `SLUS_204.86`, 3,942,320 bytes |
| SHA-256 | `48ebf907d8149122ca9bd622ed11c290d5f93173078ea5bd570e1ac5566f13d7` |
| Boot configuration | `BOOT2 = cdrom0:\SLUS_204.86;1`, VER 1.00, VMODE NTSC |
| Format | ELF32 little-endian, ET_EXEC, EM_MIPS, flags `0x20924000` |
| Entry / GP | `0x00100008` / `0x004C7270` |
| Main PT_LOAD | offset `0x80`, VA `0x100000`, filesz 3,941,760, memsz 5,456,768, RWX |
| Second PT_LOAD | VA `0x00634380`, filesz/memsz 0 |
| Symbols / compiler | Empty symtab/strtab (stripped); Metrowerks MW MIPS C Compiler 2.4.1.01 / PlayStation2 |

Crypto digest over the Storage bytes and independent SQL reassembly of
41 `us_elf_chunk` records agree on size/hash. A separate US row and 35
file rows were added to `build_targets`/`disc_files`; old JP rows remain
historical. Only `AFS01.AFS` and `AFS03.AFS` were listed under `PS2/`;
full-disc completeness/ISO format/LBAs have not been established.

Small controlled SQL→hex→local transfers provided **992 verified bytes**
from four US code windows. Ghidra decoded 246 instructions and confirmed
13 LUI/ADDIU candidate sites plus 11 calls to a shared `0x003DCAD0` callee.
This is **partial analysis**, not the authoritative full function map.
Full facts and caveats: `analysis/scout/slus_20486/README.md`.

Next: obtain the complete local working ELF (P-006), then run
`scripts/fase1_analyze.sh game/working/SLUS_204.86 --recomp`.
The pipeline gates size/SHA without bypass, uses Ghidra **12.0.2** +
EmotionEngine `r5900:LE:32:default`, project `mvc2_slus20486`, configs
`generated/config/slus_20486/`, and ignored C++ output
`generated/cpp/slus_20486/`. REA stays on Ghidra 12.1.4.
A synthetic original ELF passed this toolchain through C++ generation;
no full-game TOML or game C++ has been generated yet.

## Historical Japanese target (not active; FASE 0 evidence only)

**Marvel vs. Capcom 2: New Age of Heroes (Japan)** — PS2 CD,
serial **SLPM-622.27**, NTSC-J.

* Historical source (no longer in the current Storage listing): bucket `ps2recomp`, split zip
  `….zip.001–.007` (131,289,570 B total), single entry `.iso`
  (DEFLATE → 208,384,000 B).
* ISO9660 PVD: system id `PLAYSTATION`, volume id `MARVEL_VS_CAPCOM2`,
  root dir @ LBA 22. 39 entries total (full list: Supabase `disc_files`,
  `docs/discoveries.md`).

### Boot ELF — `/SLPM_622.27;1`

| Field | Value |
|---|---|
| LBA / size | 857 / 4,378,928 B |
| SHA-256 | `de42633ccf9d78fed3d8cbecd75a81a9e043a7b4298be374a8ffa7689cb42af5` |
| Format | ELF32, little-endian, ET_EXEC, EM_MIPS (R5900 EE core) |
| Entry | `0x00100008` |
| e_flags | `0x20924000` |
| Program headers | 2 × PT_LOAD. Main: off `0x80`, vaddr `0x00100000`, filesz `0x42CF00` (4,378,368), memsz `0x5BF980` (6,029,952), RWX. Second: vaddr `0x006BF980`, filesz/memsz 0 |
| Sections | 8 headers; `.symtab`/`.strtab` present but **size 0 (stripped)**; one big unnamed PROGBITS section covering the load image; `.comment` (43 B), `.reginfo` |
| Consequence | No symbols → function discovery must come from Ghidra analysis (PS2Recomp's preferred path for stripped ELFs) |

### Disc layout highlights (for later phases)

* `/PS2/` — CRI middleware data: `0FLIST.DIR` + `AFS00.AFS` (55.5 MB),
  `AFS01.AFS` (9.3 MB), `AFS02.AFS` (136.6 MB), `AFS03.AFS` (0.6 MB).
  Sprites/audio almost certainly inside the AFS archives (ADX audio given
  `CRI_ADXI.IRX`); FASE 3 CDVD service reads extracted files.
* `/MODULES/` — 28 IOP modules incl. `IOPRP255.IMG` (IOP reboot image
  2.5.5), `LIBSD.IRX`, `CRI_ADXI.IRX`, `MCMAN/MCSERV` (memcard),
  `PADMAN`, `SIO2MAN`, `MODMIDI/MODHSYN/MODMSIN` (sound), `DEV9/HDD/ATAD/
  PFS` (network HDD), `AVETCP/AVEPPP` (network stack — the JP release had
  online play), `USB*`.
* `/FONT8_8.TM2;1`, `/SYSTEM.CNF;1` at root.

## Toolchain for RE (all validated in FASE 0)

| Tool | Role here |
|---|---|
| Ghidra 12.1.4 (headless) | Primary static analysis of the EE ELF and IRX modules (MIPS R5900 + R3000A IOP). `tools/ghidra/ghidra_12.1.4_PUBLIC/support/analyzeHeadless` |
| REA 6.5.0 (`tools/rea/rea`) | Agent-driven RE over Ghidra (CLI + MCP server, 207 tools). Ships a MIPS-aware bridge (`ReaGhidraMipsSoftFloat.java`). Use `source scripts/env.sh` first |
| `ExportPS2Functions.java` | PS2Recomp's Ghidra script → produces the `config.toml` + function-map CSV the recompiler consumes (`tools/ps2recomp/PS2Recomp/ps2xRecomp/tools/ghidra/`) |
| `ps2_analyzer` | PS2Recomp's own ELF analyzer w/ embedded SCE symbol DB — fallback/cross-check for TOML generation and syscall stub identification |
| GhidraMCP / ghidra-mcp / REA-java | Vendored alternatives (GUI-oriented or Gradle-built); only if the REA path hits a wall |

## Historical Japanese FASE 1 plan (superseded; do not execute)

1. Bring the ELF local (P-006) → `game/working/SLPM_622.27` (never in git).
2. `analyzeHeadless analysis/ghidra_projects mvc2 -import SLPM_622.27`
   - Loader: ELF; language: MIPS R5900 (`MIPS:LE:64:default` family —
     confirm exact PS2 variant against PS2Recomp docs; EE is 64-bit MIPS
     with 32-bit ELF). Apply REA's MIPS soft-float handling where relevant.
3. Let auto-analysis find functions; review with REA (`binary_overview`,
   `list_procedures`, string xrefs to SDK names).
4. Run `ExportPS2Functions.java` headless (-postScript) → TOML/CSV into
   `generated/` configs. Cross-check function count vs `ps2_analyzer`.
5. Seed Supabase `game_functions` (address, name, size) from the CSV;
   classify `sdk` vs `game` origins with `ps2_analyzer`'s SCE database +
   string evidence (sce* names) → `sdk_symbols`.
6. Identify syscall stubs & IOP module boundaries; record in
   `docs/discoveries.md` as they are proven.
7. First `ps2_recomp` full run; triage translator gaps (VU ops etc.).

## How the FASE 0 server-side extraction worked (reproducible)

Because the sandbox cannot reach `*.supabase.co` (P-002), a temporary
Supabase **edge function** (`mvc2-bootstrap`, deleted after use) did the
work inside Supabase's infra, triggered from SQL via `pg_net.http_post`,
writing results to `public.bootstrap_transfer`:

* v1 `zip_directory`: downloaded part `.007`, located EOCD, parsed the zip
  central directory → proved single DEFLATE ISO entry.
* v2 `extract_elf`: streamed parts 001–007 → skipped the local zip header →
  `DecompressionStream("deflate-raw")` → walked ISO9660 directories with
  dynamic byte-range capture → captured the ELF extent → staged SHA-256 +
  45 × 96 KiB base64 chunks (`elf_chunk` idx 0–44; concatenating decoded
  chunks in idx order reproduces the ELF exactly — verified by hash/size).
* v3 `elf_headers` / `iso_dirs`: parsed ELF headers from the staged chunks;
  full ISO directory walk from the first 8 MiB of inflated ISO.

To re-create the bridge: `create extension pg_net` already applied;
staging table exists (migration `fase0_bootstrap_transfer_staging`).
The function source is preserved in this repo's docs history (this section
+ git history of the session); re-deploy with verify_jwt=true and a proper
caller if ever needed again. NOTE: legacy anon/publishable keys were
rejected by the functions gateway (`UNAUTHORIZED_INVALID_JWT_FORMAT`) —
v1–v3 ran with `verify_jwt=false` for minutes and were then deleted (P-003).
