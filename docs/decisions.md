# Decisions (append-only; supersede by new entries, don't rewrite)

## D-001 — Vendored tools stay local; git tracks pins + rebuild scripts
*2026-10-17.* The ~350 MB of tool sources and ~2 GB of tool binaries are
kept in the workspace under `tools/` but **not committed** (nested `.git`
dirs, snapshot caps, repo hygiene). Reproducibility is guaranteed by
`tools/MANIFEST.md` (exact URLs + commit SHAs + archive SHA-256s) and the
idempotent `scripts/setup_tools.sh`. Rationale: the workspace itself is
the local copy FASE 0 demands; git remains fast and clean; every artifact
is re-creatable from at most github.com/PyPI/npm.

## D-002 — Game data NEVER enters git or third-party hosts
*2026-10-17.* Per the owner's rule already recorded in Supabase
(`build_targets.notes`: "Game data never leaves the owner machine") and
basic copyright hygiene: disc images/ELFs/AFS stay in `game/` (gitignored)
and in the owner's Supabase. Analysis *facts* (hashes, layouts, function
maps) are fine to store in docs/Supabase. This rule is why the ELF relay
through GitHub was rejected (problems P-006).

## D-003 — REA = morluto/rea (rea-agents 6.5.0) as the RE automation layer
*2026-10-17.* Among the REA-named candidates, `morluto/rea` is the one
matching "REA + MCP integration": MCP-first, drives a verified Ghidra
12.1.4 headless, builds purely from npm, and works today (validated).
cyberkaida's reverse-engineering-assistant, LaurieWired GhidraMCP and
bethington ghidra-mcp are vendored as fallbacks but are GUI/Gradle-bound
and currently unbuildable behind the egress filter.

## D-004 — Runtime modelled on the God of War native port (carried from Supabase)
*Pre-existing (2026-10-17 restart), kept.* Static-recompiled EE + AOT VU1
microprograms + OpenGL GS (render targets, no VRAM emulation) + native
IOP approach (AOT-compile the disc IRX set or HLE the services), real SIF
FIFO/DMA, file-backed CDVD. The previous 268-module generated C++ was
discarded by the owner; we start codegen fresh in FASE 1/2.

## D-005 — Ghidra path is the primary function-discovery route
*2026-10-17.* The ELF is stripped (empty symtab). Per PS2Recomp upstream
guidance, function boundaries come from Ghidra +
`ExportPS2Functions.java`; `ps2_analyzer` is a cross-check/fallback, not
the source of truth.

## D-006 — All tooling lives inside the repo; no system installs
*2026-10-17.* cmake/ninja/JDK/Ghidra/REA run from `tools/` via
`scripts/env.sh`. System had no cmake/JDK and PEP 668 blocks system pip;
in-repo tools keep the project self-contained and identical across
sessions. Consequence: always `source scripts/env.sh` before building.

## D-007 — Build dir is `builddir/`, never `build/`
*2026-10-17.* The name `build` is excluded from workspace snapshots;
`builddir/` persists (best-effort) and keeps incremental builds warm.

## D-008 — Supabase is the structured RE tracker; Linear tracks work
*2026-10-17.* Facts about the game (disc files, ELF modules, functions,
SDK symbols, component status, probe runs) go to the existing Supabase
schema (it already models this project well). Linear holds phases/tasks.
Local docs remain the narrative source of truth that works offline;
if Linear/Docs are unreachable, work continues locally and syncs later.

## D-009 — Temporary Supabase edge-function bridge: approved pattern, deleted after use
*2026-10-17.* Server-side extraction inside the owner's own Supabase
(pg_net → edge function → staging table) is the sanctioned way to inspect
Storage content from this sandbox. Constraints: read-only on originals,
stage only derived facts/chunks, `verify_jwt=false` only for minutes,
**delete the function afterwards**, log everything in docs. (Executed
exactly so in FASE 0.)

## D-010 — SLUS_204.86 is the only active game target
*2026-10-17, explicit owner instruction.* Stop SLPM_622.27 scouting and
use the USA executable `SLUS_204.86` now present as an extracted Storage
object. Preserve Japanese records solely as historical evidence; never
reuse their SHA, addresses, GP, function maps or codegen for the US build.
Verify the new executable independently before analysis. Original Storage
objects remain read-only. This supersedes earlier target selection.
