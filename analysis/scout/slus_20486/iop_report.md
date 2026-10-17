# USA IOP / assets review — 2026-10-17

## Verified inventory, not a runtime claim

Read-only inspection of the current owner-uploaded files found **26
external IRX** and **15 ELF modules** inside `IOPRP255.IMG` (18 ROMDIR
entries including RESET, ROMDIR and EXTINFO). All 41 modules are MIPS
ELF32 LE `ET_SCE_IOPRELEXEC` (`0xFF80`). Their content hashes were checked
again during the corrected v2 pass. Full per-table ordinals/relocation
metadata remain in Supabase `bootstrap_transfer` kinds
`us_iop_module_v2` / `us_rom_module_v2`.

Local canonical summary: `iop_modules_compact.txt`, rows
`path|bytes|sha256|elf_type|imports|exports`. Table entries use
`library@hex_version:ordinal_count` for imports and
`library@hex_version:slot_count` for exports. After removing its final
newline, SHA-256 matches the independently computed SQL value
`7b89ca2f9885c781169629c312fab25483e5ed4b91f13eaaa984940fc983704a`.
This contains metadata, not game binary bytes.

### Parser correction that matters

The first pass misread raw zero export pointers as table terminators.
In relocatable IRX, a zero pointer with **R_MIPS_32** may be the valid
link-time address of `_start`, becoming nonzero after load. The corrected
parser preserved **16** such slots and reprocessed/rehashed every module.
For example MODHSYN has **29** export slots, not zero; THREADMAN's
`thbase` has **52**, not three. **Do not use v1 export counts.** A synthetic
regression test covers this condition. This parser still does not apply
relocations, load images or prove exported functions execute successfully.

## TSNDDRV sound chain

`TSNDDRV.IRX` is 45,103 bytes, SHA-256
`f2e6aeb8972a1228d757a92a58ea83f3929c483b89ac6bf7e67570ba7bc0ddc1`.
It imports **61 ordinals through 14 libraries**, with no export table
found. Detailed versions/ordinals: `tsnddrv_imports.json`.

- `libsd` 1.5 → supplied `LIBSD.IRX` (34 export slots).
- `modhsyn` 1.4 → supplied `MODHSYN.IRX` (29).
- `modmidi` 1.5 → supplied `MODMIDI.IRX` (26).
- `modmsin` 1.1 → supplied `MODMSIN.IRX` (10).
- Other requirements: `loadcore`, `sifcmd`, `stdio`, `thbase`, `thevent`,
  `thsemap`, `thmsgbx`, `timrman`, `sysmem`, `intrman`.

Twelve TSNDDRV library requirements have supplied candidate ordinal spans;
`sysmem` / `intrman` need core/ROM/HLE paths. A matching library name,
major version and slot count is not proof of initialization, HLE fidelity,
RPC registration, sound-driver compatibility or audible output. No RPC SID
has been established for TSNDDRV in this pass.

## Static dependency coverage and source audit

Across 41 images: **284 import tables**, **41 export tables**.

- **226 import tables** have at least one supplied provider with the same
  major version and all requested ordinals within its parsed export span.
- **58 import tables** require libraries without an export in these 41
  uploaded images: `dmacman`, `heaplib`, `intrman`, `secrman`, `sysmem`,
  `vblank`. That is not proof they are absent from a real PS2 ROM.
- No additional major-version/ordinal-span gap was found among libraries
  that *are* supplied. Pinned upstream lookup compares major versions and
  chooses a newer minor; it does not enforce provider minor >= requested.
  This matters for MCMAN's `sio2man` 2.4 request vs supplied 2.3 export.

Audit of PS2Recomp pin `eb8688b` (not an execution test):

- Required `sysmem`, `intrman`, `heaplib`, `vblank` ordinals appear in the
  respective HLE switch cases. This is case coverage only.
- **MCMAN imports `secrman:6`**, but the direct emulator branch handles
  only 4 and 5 and these uploads supply no `secrman` export. This is a
  concrete unresolved-import risk, not a proven crash or executed path.
- **`dmacman` returns zero unconditionally** in the current dispatcher.
  Do not present that placeholder as a DMA implementation.

No return-zero stub, game patch or runtime workaround was added.
Reproducible SQL: `scripts/supabase/iop_coverage.sql`. Detailed source paths
and ordinal sets: `iop_dependency_report.json`.

## Shared EE wrapper, now examined locally

A fifth individually SHA-checked window covers **384 bytes** at
`0x003DCAD0`, with **96** Ghidra-decoded instructions including following
code. Ghidra inferred a 212-byte function body for the entry.
Within that body, two direct calls target `0x0010BB98`; a diagnostic call
targets `0x0011EB60`, using the independently read US string at
`0x004BA4F0`: `Can't load module %s\n`.

The partial decompiler output suggests a module-load retry wrapper:
arg4 zero retries while result is negative; nonzero arg4 bounds retries
and stops on positive result, otherwise reaching the diagnostic. Types,
ABI, SDK names and global runtime load order remain unverified.
Raw bytes and pseudocode stay ignored; bounded facts are in
`helper_window.json` and `helper_call_facts.json`.
Re-run with `bash scripts/fase1_helper.sh` when the ignored window exists.

## Proven asset gap (USA evidence, not a JP assumption)

The uploaded **44-byte `PS2/0FLIST.DIR`** lists:
`afs00.afs`, `afs01.afs`, `afs02.afs`, `afs03.afs`.
A case-insensitive Storage lookup found **no AFS00 or AFS02 object**.
Thus the uploaded asset set is not complete relative to its own US list.
Their expected byte sizes/hashes and the cause of absence are unknown.

The two present AFS files have valid magic and directory payload extents
within their object lengths:

| Object | Bytes | Payload entries | Last required payload end |
|---|---:|---:|---:|
| `PS2/AFS01.AFS` | 9,263,104 | 63 | 9,257,408 |
| `PS2/AFS03.AFS` | 579,584 | 1 | 575,832 |

This is not full filename-table/content validation. Missing AFS files do
**not** block ELF analysis/codegen, but prevent claiming a complete game
asset set for runtime. No upload-size-limit cause has been verified.

## Cleanup / phase boundary

Requests 11 and 12 completed successfully. Both temporary Edge Functions
were deleted and their tokens removed. Storage originals were read only.
A separate metadata migration added 41 USA IOP rows with runtime status
`unknown`; no instruction counts or runtime load bases were guessed.

The full US EE ELF is still not in the sandbox. Local verified scope is
now **five windows / 1,376 bytes / 342 decoded instructions**. This does
not replace authoritative full-ELF export or game C++ generation (P-006).
