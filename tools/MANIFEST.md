# tools/MANIFEST — pinned tool sources (offline rebuild reference)

Everything below already exists locally under `tools/`. This manifest +
`scripts/setup_tools.sh` recreate it all. Recorded 2026-10-17 (FASE 0).

## Git clones (full history, github.com)

| Path | Origin | Pinned HEAD at bootstrap |
|---|---|---|
| `tools/ps2recomp/PS2Recomp` | https://github.com/ran-j/PS2Recomp | `eb8688b2fd191129f103a39543002c005b33409c` |
| `tools/rea/rea` | https://github.com/morluto/rea | `300905c11be1c25b98fda9e2b71dfa899fc2831c` |
| `tools/rea/reverse-engineering-assistant` | https://github.com/cyberkaida/reverse-engineering-assistant | `a05a6b0a18649efd6d74ec8447bdadf8d468c365` |
| `tools/rea/GhidraMCP` | https://github.com/LaurieWired/GhidraMCP | `1e980252087b2479a21b9ca6d82d5829538651a7` |
| `tools/rea/ghidra-mcp` | https://github.com/bethington/ghidra-mcp | `cf8b12db27eb139b28b90eaa3488306da910d759` |
| `tools/extra/ps2-recomp-Agent-SKILL` | https://github.com/hkmodd/ps2-recomp-Agent-SKILL | `a1cafc23ac2d37d16ce979d3d4987a0bb6989dda` |
| `tools/extra/ghidra-emotionengine-reloaded` | https://github.com/chaoticgd/ghidra-emotionengine-reloaded | `fcc5dea` (short; R5900 processor module — see PS2-16 note: releases cover Ghidra 12.0.x/11.4.2, not 12.1.4) |

PS2Recomp's own build additionally clones (FetchContent, into
`builddir/ps2recomp/_deps/`): ELFIO `Release_3.12`, toml11 `v4.4.0`,
fmt `12.1.0`, libdwarf `v2.2.0`, rabbitizer `1.14.3`, nlohmann/json
`v3.11.3` (runtime/studio deps — raylib, imgui, SDL2 — only when those
targets are enabled).

## Binary archives (SHA-256 verified against official digests)

| Archive (in `tools/downloads/`) | Bytes | SHA-256 | Official source |
|---|---|---|---|
| `ghidra_12.1.4_PUBLIC_20260921.zip` | 569,649,598 | `ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db` | NSA Ghidra release `Ghidra_12.1.4_build` |
| `OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz` | 207,473,347 | `ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94` | adoptium/temurin21-binaries `jdk-21.0.12.1+1` |

Both were fetched through the GitHub Actions relay (sandbox cannot reach
release-asset hosts): chunk manifests preserved in
`tools/downloads/manifests/`. Re-fetch: bump
`tools/ghidra/.fetch-ghidra-trigger` or `tools/jdk/.fetch-jdk-trigger`,
commit + push, let the workflow commit chunks, `git pull`,
`scripts/setup_tools.sh`.

## PyPI wheels (in `tools/downloads/wheels/`)

| Wheel | Used for |
|---|---|
| `cmake-4.4.4-…manylinux…whl` | `tools/cmake/` (cmake/ctest/cpack binaries) |
| `ninja-1.13.2-…whl` | `tools/bin/ninja` |
| `jdk4py-21.0.8.2-…whl` | probe only — **not** a full JDK, do not use for Ghidra (P-004) |

Re-fetch: `python3 -m pip download cmake==4.4.4 ninja==1.13.2 -d tools/downloads/wheels`.

## npm

REA is built from its clone: `(cd tools/rea/rea && npm ci && npm run build)`
→ `node scripts/rea.mjs` (6.5.0). Registry: `registry.npmjs.org`.
Equivalent published package: `rea-agents@6.5.0` (same source tree).

## Locally built binaries

| Binary | Built from | Via |
|---|---|---|
| `tools/ps2recomp/bin/ps2_recomp` (2.1 MB) | PS2Recomp @ eb8688b | `scripts/build_ps2recomp.sh` |
| `tools/ps2recomp/bin/ps2_analyzer` (14 MB) | PS2Recomp @ eb8688b | `scripts/build_ps2recomp.sh` |
| `builddir/ps2recomp/ps2xTest/gs_cache/ps2_gs_*_tests` | PS2Recomp tests | same build (`ctest --test-dir …/gs_cache`: 45/45) |
