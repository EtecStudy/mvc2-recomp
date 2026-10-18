# SLUS_204.86 — USA-only evidence (2026-10-17)

This directory contains **derived analysis facts, not game binaries**.
Do not use the historical `../syscall_map.*` as US address evidence.

## Identity / verification

- `storage_inventory.json`: all 35 current uploaded file names/sizes
  (15,461,038 bytes); metadata transport checked against a server-computed
  canonical-listing hash. No full-ISO completeness claim.

- `elf_facts.json`: Storage executable bytes, SHA-256, ELF headers, GP,
  compiler and parsed `SYSTEM.CNF` fields. Main load mapping:
  `VA = file_offset + 0xFFF80` for file offsets `[0x80, 0x3C2600)`.
- Server-side staging uses **`us_elf_chunk`** (41 rows, indexes 0–40),
  not the Japanese `elf_chunk` rows. Independently decoding and joining
  the US chunks yields 3,942,320 bytes and the same SHA-256 as Edge crypto.
- `code_windows.json`: four window offsets/sizes/hashes (992 bytes total).
  Small SQL hex results were copied to ignored local `game/working/`
  files and each checked against its own server SHA-256 before Ghidra.
  One initially incomplete copy was rejected by the length assertion and
  corrected; no unchecked window reached Ghidra.

## Partial static analysis

- `module_xref_candidates.json`: 18 path strings, 16 candidate address
  constructions from a bounded straight-line LUI scan. Search stops at
  unknown operations/control flow/base overwrite. Aligned-pointer scan
  returned no matches. Strings / candidates do not prove runtime loading.
- `window_call_facts.json`: Ghidra 12.0.2 + EmotionEngine decoded **246
  instructions** from the four verified windows. Confirmed LUI/ADDIU
  instruction pairs at **13** of the candidate sites covered by these
  windows. It found **11 direct calls to `0x003DCAD0`** in USB/audio/network
  windows. This is a shared callee candidate; no SDK name is assigned.
  Window-ending branches without their delay slots may remain undecoded.
  No complete CFG, function boundaries or executed load order is claimed.
- `syscall_candidates.json`: 169 aligned encoding sites with nearby
  `ADDIU v1,zero,imm` candidates, 146 distinct signed numbers. The scan
  found 481 raw syscall-like words in the mixed RWX load image; 312 had no
  recovered immediate. Those may be data. Even recovered values require
  Ghidra review (notably the isolated `0x004398B0` candidate).
- `syscalls_compact.txt`: compact US-only fact transport. After stripping
  its final newline, SHA-256 is
  `885b063fffe5fa82a2af8a08a776d5f283f80eae56a6c0441f7a885f8eed8205`,
  independently obtained from SQL and matched locally. No JP sites copied.

## IOP, helper and asset follow-up

- `iop_report.md`: human-readable findings and scope/limitations.
- `iop_modules_compact.txt`: 41 SHA-rechecked v2 module summaries;
  `iop_dependency_report.json`: 226 provider-span matches / 58 core-only
  tables, plus pinned-source audit (`secrman:6`, DMA placeholder).
- `tsnddrv_imports.json`: all 61 requested ordinals / 14 libraries.
- `romdir.json`: 18 entries and valid payload extents; 15 ELF members.
- `asset_completeness.json`: AFS01/03 bounds and **AFS00/02 absence**
  against the US filelist; missing sizes/hashes/cause remain unknown.
- `helper_window.json`, `helper_call_facts.json`: fifth verified window
  (384 bytes / 96 instructions), entry's inferred 212-byte function body
  with three direct calls and corroborating module-load error string.
  `bash scripts/fase1_helper.sh` reproduces the partial local analysis.

Current combined window scope: **8 windows / 2,488 bytes / 620 decoded instructions**,
not a full executable. Raw bytes/pseudocode remain in ignored directories.

## Provenance / cleanup

Read-only Storage → temporary token-protected Edge Function
`mvc2-us-stage` → target-prefixed records in `bootstrap_transfer` →
connector SQL. The initial staging attempt failed because `(kind,idx)`
is not unique; an ordinary INSERT corrected the issue. Request 9 staged
and verified the US ELF; request 10 performed the bounded scout.
The function was **deleted**, its local token removed, and a subsequent
Edge Functions listing was empty. Storage originals were not written.
`register_active_us_slus20486` added a separate US target + 35 file rows;
no Japanese rows or staged originals were repurposed or deleted.

## Remaining work

The full US ELF has **not** reached the sandbox. The small-window route
is proven but is not yet an efficient full-binary delivery route.
Authoritative full-ELF Ghidra export, analyzer cross-check and game C++
generation remain pending. A synthetic original ELF passed the full
Ghidra → TOML/CSV → low-memory normalization → ps2_recomp C++ probe;
that validates tooling, **not a completed game recompilation**.

## Local repeat commands

```bash
bash scripts/fase1_windows.sh       # needs the four ignored .bin windows
bash scripts/test_ghidra_ee.sh       # original synthetic ELF through C++
bash scripts/test_infra.sh
```

`capture_us_windows.sql` and `verify_us_staging.sql` under
`scripts/supabase/` reproduce the read-only server proof/capture queries.
`fase1_windows.sh` checks local window files against the committed metadata
hashes before importing. Ghidra additionally checks mapped bytes. Raw
window disassembly stays in ignored `builddir/logs/`; only bounded facts
are recorded here. The full-ELF pipeline still requires its own SHA gate.

The subsequent IOP passes used temporary functions `mvc2-us-iop-inventory`
and `mvc2-us-iop-v2` (requests 11/12). Both were deleted; tokens removed;
Edge list rechecked empty. **v1 export counts are superseded** by v2,
which preserves 16 relocated-zero export slots. Local full-scan Edge
source is a reusable template, not the exact inline v2 reparse deployment
body; the live reparse also used v1 original source identities to recheck
all hashes. `build_iop_edge.py` assembles an ignored deployment copy;
never commit that token-bearing output. No new deployment is needed now.


## Module-load chain: new US evidence

`load_chain.md` / `load_chain_facts.json` add three SHA-gated windows
(1,112B/278instructions). Core entry0010B970 matches the full548-byte
`_sceSifLoadModule` signature; independent native fragment scan agrees.
Binder0010B198 matches `_lf_bind` and constructs SID80000006. This is
**LOADFILE, not TSNDDRV's own SID**. Thin0010BB98 remains a short candidate;
0010B298 matches both `_lf_version` and `_fs_version` and remains ambiguous.
No automatic Ghidra naming/stubs, executed boot order or whole-game map.
Run `bash scripts/fase1_load_chain.sh` when ignored window bytes exist.
