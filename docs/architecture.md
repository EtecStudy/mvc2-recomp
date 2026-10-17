# Architecture — mvc2-recomp

Native PC port of **Marvel vs. Capcom 2: New Age of Heroes (PS2, NTSC-U,
SLUS-204.86)** by **static recompilation** with PS2Recomp, plus a
hand-written runtime modelled on the God of War native port approach
(AOT VU1, OpenGL GS, native IOP/IRX handling) — see the restart note in
Supabase `build_targets` (2026-10-17) and decisions D-003/D-004.

## Pipeline

```
 game disc (Supabase storage, owner-only)
   │  ISO9660
   ▼
 SLUS_204.86 (EE ELF) ──► Ghidra 12.0.2 + EmotionEngine ──► ExportPS2Functions.java ──► config.toml + functions.csv
   │                        ▲   │                                        │
   │                        │   └─ REA 6.5 (MCP/CLI, Ghidra provider) — assisted RE
   │                        │                                            ▼
   └────────────────────────┘                              ps2_recomp (PS2Recomp)
      ps2_analyzer (fallback TOML, SCE symbol DB)                        │
                                                                         ▼
                                                    generated C++ (R5900 -&gt; C++)
                                                                         │
 MODULES/*.IRX (IOP) ──► ps2xIOP / AOT compile ──┐                       ▼
                                                  └──►  runtime (src/ + ps2xRuntime)
 PS2/*.AFS (assets) ──► native file services ────┘      EE · VU1 · GS(GL) · SIF
                                                         IOP · SPU2 · PAD · CDVD
                                                                         │
                                                                         ▼
                                                              native executable
                                                     (target_os windows-x64 per Supabase)
```

Key PS2Recomp workflow rule (upstream README): for stripped retail ELFs the
**preferred** path is Ghidra + `ExportPS2Functions.java` (function
boundaries from real analysis), **not** the heuristic analyzer. Our ELF is
stripped (empty symtab) → Ghidra path is mandatory (docs/reverse_engineering.md).

## Runtime components (mirrors Supabase `runtime_components`)

| Component | Blocking | Approach (from Supabase, still valid) |
|---|---|---|
| EE_CPU | yes | PS2Recomp static recompilation of R5900 → C++ |
| VU1 | yes | Microprograms compiled ahead-of-time to C++; macro+micro modes |
| GS | yes | OpenGL 4.5 render-target renderer, no VRAM emulation (PS2Recomp ships none) |
| IOP | yes | AOT-compile the disc's IRX modules (GoW approach) or HLE services; without IOP the EE never sees SIF CMDINIT |
| SIF | yes | Real FIFO + DMA engine driven by the IOP handshake |
| TIMERS | yes | EE/IOP counters and interrupt delivery |
| CDVD | no | Read extracted disc files from disk, no ISO emulation |
| SPU2 | no | Native sound engine driven by LIBSD calls (CRI ADX → see AFS) |
| PAD | no | Native input service (XInput on Windows), no SIO2 model |
| MEMCARD | no | Native file-backed saves |

Status of every component at FASE 0 end: `missing` (unchanged — FASE 0 was
infrastructure only, by design).

## Repository layout

See `docs/bootstrap.md` §4 for the annotated tree. Principles:

* `tools/` — vendored third-party tools, **local-only** (never committed;
  reproducible via `scripts/setup_tools.sh`, pinned in `tools/MANIFEST.md`).
* `game/` — the owner's copyrighted game data, **never in git**.
* `generated/` — ps2_recomp output. Configs (TOML/CSV) are tracked; the
  bulk C++ is regenerated, not hand-edited.
* `src/` — hand-written runtime/glue code of this project (from FASE 2/3).
* `analysis/` — Ghidra projects and RE evidence exports (databases local-only).
* `docs/` — persistent knowledge: bootstrap, architecture,
  reverse_engineering, build, discoveries, problems, decisions.
* Supabase remains the structured tracker (targets, disc files, ELF modules,
  functions, SDK symbols, probe runs, component status); Linear tracks work.

## Host targets

* Development/validation host today: this Linux x86-64 sandbox (tools build
  and run here; the recompiled game will also build here first).
* Product target per Supabase `build_targets.target_os`: **windows-x64**.
  PS2Recomp is MSVC-first; final packaging will need an MSVC (or
  MinGW-w64/clang) build — decision when FASE 3 starts. No Windows tooling
  exists in the sandbox (no MSVC, no wine) — nothing to install for FASE 0/1.

## Phases

| Phase | Scope | Status |
|---|---|---|
| 0 | Infrastructure bootstrap (this document set) | ✅ done 2026-10-17 |
| 1 | ELF RE in Ghidra/REA → function map; first full ps2_recomp run; IRX inventory deep-dive | next |
| 2 | Generated EE C++ compiles + links against minimal runtime skeleton; first boot attempt (probe) | |
| 3 | Runtime components in dependency order: memory/dispatch → IOP+SIF → TIMERS → CDVD/files → VU1 → GS → SPU2/PAD/MEMCARD | |
| 4 | Boot to first frame; menu; gameplay correctness/perf | |
| 5 | Audio/input/saves polish; windows-x64 packaging | |
