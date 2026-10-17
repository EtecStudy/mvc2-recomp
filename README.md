# mvc2-recomp

Native PC port of **Marvel vs. Capcom 2: New Age of Heroes** (PlayStation 2,
NTSC-U **SLUS-204.86**) via **static recompilation** with
[PS2Recomp](https://github.com/ran-j/PS2Recomp), reverse-engineered with
Ghidra 12.1.4 + [REA](https://github.com/morluto/rea).

> Active target: **SLUS_204.86 (USA)**, selected by the owner on 2026-10-17.
> Extracted files are in Supabase bucket `ps2recomp`. The executable's
> verified size is 3,942,320 bytes; SHA-256 is pinned in `scripts/target.sh`.
> FASE 1: server-side ELF verified, five local windows decoded in Ghidra;
> full-ELF analysis and US game C++ generation remain pending.
> Earlier Japanese inventory/scouting is historical only, not US evidence.
> Toolchain tested: synthetic Ghidra → independent analyzer comparison → C++.
> Infrastructure 31/31; full US ELF transfer is still the blocking step.
> IOP: 41 images inventoried; AFS00/AFS02 missing from uploaded US list.
> USA findings: [`analysis/scout/slus_20486/`](analysis/scout/slus_20486/).

## Quick start (this sandbox)

```bash
source scripts/env.sh        # vendored cmake/ninja/JDK21/Ghidra paths
scripts/test_infra.sh        # validate every tool end-to-end
scripts/build_ps2recomp.sh   # (re)build ps2_recomp + ps2_analyzer
scripts/setup_tools.sh       # recreate any missing tool piece (idempotent)
```

## Documentation (`docs/`)

| File | Contents |
|---|---|
| `bootstrap.md` | FASE 0 report: tools, tests, Supabase inventory, offline plan |
| `architecture.md` | Pipeline, runtime components, phases |
| `reverse_engineering.md` | Target facts (ELF/ISO), RE method, FASE 1 procedure |
| `build.md` | Build commands for everything |
| `discoveries.md` | Dated, evidence-based findings |
| `problems.md` | Problem log with diagnoses and resolutions (P-001…) |
| `decisions.md` | Architecture/process decisions (D-001…) |

`tools/MANIFEST.md` pins every vendored tool (URLs, commit SHAs, archive
SHA-256s) so the environment can be rebuilt without depending on GitHub
being reachable in future sessions.

## Rules of the repo

* **Game data never enters git** (copyrighted; lives only in `game/` locally
  and in the owner's Supabase bucket). See decision D-002.
* Vendored tools under `tools/` are local-only; git tracks the pins and
  rebuild scripts (D-001).
* Structured game facts (disc files, functions, components) are tracked in
  the project's Supabase; work items in Linear; narrative knowledge in `docs/`.
