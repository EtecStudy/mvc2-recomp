# USA module-load chain — bounded static evidence, 2026-10-17

This is new **US game evidence**, not another synthetic probe. It is still
only partial static analysis: no full ELF, boot trace, successful RPC or
actual module execution is claimed.

## Capture and reproducibility

Three SHA-256-gated SQL slices of the already verified US executable:

| Window | VA | Bytes | Purpose |
|---|---|---:|---|
| load_core | `0010B970` | 552 | Implementation called by the thin entry |
| load_entry | `0010BB98` | 160 | Wrapper's direct callee and following code |
| load_bind | `0010B198` | 400 | Binder + following version-comparison helper |

The 1,112 bytes were independently checked locally against server hashes.
Ghidra12.0.2+EE decoded **278 instructions**, and decompiled four specified
entries without assigning SDK names. Together with the prior windows:
**8 non-overlapping windows / 2,488 bytes / 620 decoded instructions**.
This is not an authoritative whole-game function map.

- `scripts/supabase/capture_us_load_chain.sql`: read-only capture.
- `load_chain_windows.json`: identities/hashes/entry offsets (no bytes).
- `bash scripts/fase1_load_chain.sh`: local SHA checks → Ghidra → signatures
  → independent native fragment scan → derived fact report.
- `load_chain_facts.json`: precise hashes, candidates, calls and limitations.

Original bytes, derived fragment ELF, analyzer outputs and pseudocode
stay ignored. No original Storage object was written, and no temporary
Edge Function/token was needed.

## SDK evidence — do not flatten the confidence levels

Pinned source: PS2Recomp `eb8688b`, embedded symbol header SHA-256
`0fdd1168a815c8af2529cae9076ae813a1304c5c3a41e48d88d38e21e7b5833d`.
The matcher extracts/verifies the header's JSON chunk lengths, normalizes
only declared relocation bits, then compares the **entire database
signature**. Unknown/out-of-range relocations are rejected. Matching
SHA-1 is a database signature check, not original-byte integrity proof;
that remains SHA-256. Database matches do not establish an exact SDK version.

| Entry | Matched database identity | Signature bytes | Unmasked bits | Interpretation |
|---|---|---:|---:|---|
| `0010B970` | `libkernl::_sceSifLoadModule` | 548 | 4,046 | Unique full normalized hash at this entry |
| `0010BB98` | `libkernl::sceSifLoadModule` | 32 | 230 | **Short candidate**, supported by its call into the matched implementation; no automatic assignment |
| `0010B198` | `libkernl::_lf_bind` | 256 | 1,820 | Unique full normalized hash at this entry |
| `0010B298` | `_lf_version` **and** `_fs_version` | 140 | 930 | **Ambiguous**: identical normalized bytes, do not choose a name merely from the hash |

The actual upstream native analyzer independently names the core
`_sceSifLoadModule` when run on a clearly labeled **derived fragment ELF**
containing only these 552 original US bytes at their original VA. It
extends the matching signature over one trailing NOP (552-byte native
extent vs 548-byte signature/Ghidra body). No full-game gate was bypassed,
and no C++ was generated from this fragment.

The game-specific retry wrapper at `003DCAD0` is still not assigned an SDK
identity. Its calls at `003DCB30` / `003DCB54` reach `0010BB98`, whose call
at `0010BBA4` reaches the hash-matched implementation. Earlier USB/audio/
network call sites reach the retry wrapper. These static edges are **not
an executed boot order**.

## Actual observed LOADFILE protocol constants

The matched binder constructs **SID `0x80000006`** with LUI/ORI at
`0010B1C0` / `0010B1C8`, then calls `00106C98` at `0010B1CC`.
Its signature annotates that target as `sceSifBindRpc`; the target body
itself was not hashed in this pass.

Partial Ghidra decompilation, checked against instruction operands:

- Client structure address: `004C7080`.
- Send/receive buffer address: `004C6E80`.
- Initial version/bootstrap RPC: function `0xFF`, zero send bytes,
  four receive bytes, then a stored version-comparison value.
- Module-load RPC site `0010BB4C` → `00106E68`, annotated
  `sceSifCallRpc` by both core/binder signatures. Again, no independent
  target-body hash yet.
- The thin entry sets `t0=0`; the core preserves it in `s3`, then moves
  `s3` to RPC argument `a1`. Thus this ordinary-load static path requests
  **RPC function 0**, with **512 send / 8 receive bytes**.
- The inferred 512-byte request uses arg-length at offset0, path at
  offset8 (252-byte capacity), arguments at offset260 (252-byte capacity).
  These are static packet-layout observations, not tested marshalling.

**This is the shared module loader's LOADFILE SID, NOT TSNDDRV's own sound
RPC SID.** That driver's own registration/SID is still unknown. Decompiled
parameter types/ABI/globals remain inferred; no successful bind or reply
has been observed.

## Runtime implication to validate, not patch around

Pinned `ps2xIOP/src/iop_subsystem.cpp` constructs MCSERV, DBCMAN and LIBSD
core services, not a LOADFILE HLE service. `canBindRpc` succeeds through an
active route or an actually registered emulated server. Therefore a
recompiled guest loader path needs a real LOADFILE server/bootstrap, or a
separately reviewed exact HLE hook; supplied `IOPRP255.IMG#LOADFILE` alone
does not prove registration. Runtime testing remains pending.

No fake server descriptor, return-zero stub, automatic SDK rename or
runtime patch was added. Full US Ghidra export/analyzer comparison/game
C++ generation remain blocked by the absent complete local ELF.
