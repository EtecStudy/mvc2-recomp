#!/usr/bin/env bash
# Active target only. Hash independently verified by Edge crypto and SQL reassembly.
MVC2_TARGET_SERIAL="SLUS_204.86"
MVC2_TARGET_STORAGE_BYTES=3942320
MVC2_TARGET_SHA256="48ebf907d8149122ca9bd622ed11c290d5f93173078ea5bd570e1ac5566f13d7"

mvc2_verify_target() {
  local elf="$1"
  if [ ! -f "$elf" ]; then
    echo "[target] Missing active ELF: $elf (SLUS_204.86; see P-006)" >&2
    return 2
  fi
  if [ "$(basename "$elf")" != "$MVC2_TARGET_SERIAL" ]; then
    echo "[target] Refusing non-active target: $elf; expected SLUS_204.86" >&2
    return 3
  fi
  if [ -z "$MVC2_TARGET_SHA256" ]; then
    echo "[target] US SHA-256 not verified yet; refusing analysis (no bypass)." >&2
    return 3
  fi
  if [ "$(wc -c < "$elf")" -ne "$MVC2_TARGET_STORAGE_BYTES" ]; then
    echo "[target] Wrong US ELF size; expected $MVC2_TARGET_STORAGE_BYTES bytes." >&2
    return 3
  fi
  echo "$MVC2_TARGET_SHA256  $elf" | sha256sum -c - || return 3
}
