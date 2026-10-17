# mvc2-recomp

Native PC port of **Marvel vs. Capcom 2: New Age of Heroes** (PlayStation 2,
NTSC-J **SLPM-622.27**) via **static recompilation** with
[PS2Recomp](https://github.com/ran-j/PS2Recomp), reverse-engineered with
Ghidra 12.1.4 + [REA](https://github.com/morluto/rea).

> Status: **FASE 0 (bootstrap) complete — 2026-10-17.** Full local toolchain
> built and validated (22/22 infra checks): PS2Recomp compiled and passing
> its test suite, Ghidra headless analysing, REA↔Ghidra integration proven,
> game disc inventoried and boot ELF extracted/verified in Supabase.
> Next: FASE 1 — Ghidra analysis of the ELF and first recompilation.

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
