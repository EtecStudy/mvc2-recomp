#!/usr/bin/env bash
# Synthetic fixtures only; no copyrighted ELF bytes.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/target.sh
mkdir -p builddir/tests
TMP=$(mktemp -d "$PWD/builddir/tests/target.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
expect_status() {
  local expected="$1"; shift
  local actual=0
  "$@" > "$TMP/output" 2>&1 || actual=$?
  if [ "$actual" -ne "$expected" ]; then
    cat "$TMP/output"; echo "Expected $expected, got $actual"; exit 1
  fi
}
[ "$MVC2_TARGET_SERIAL" = SLUS_204.86 ]
[ "$MVC2_TARGET_SHA256" = 48ebf907d8149122ca9bd622ed11c290d5f93173078ea5bd570e1ac5566f13d7 ]
expect_status 2 mvc2_verify_target "$TMP/missing"
touch "$TMP/SLPM_622.27" "$TMP/SLUS_204.86"
expect_status 3 mvc2_verify_target "$TMP/SLPM_622.27"
expect_status 3 mvc2_verify_target "$TMP/SLUS_204.86"
truncate -s "$MVC2_TARGET_STORAGE_BYTES" "$TMP/SLUS_204.86"
expect_status 3 mvc2_verify_target "$TMP/SLUS_204.86"
MVC2_SKIP_HASH=1 expect_status 3 mvc2_verify_target "$TMP/SLUS_204.86"
# Exercise successful comparison with a synthetic hash, not a fake game ELF.
MVC2_TARGET_SHA256=$(sha256sum "$TMP/SLUS_204.86" | cut -d' ' -f1)
expect_status 0 mvc2_verify_target "$TMP/SLUS_204.86"
MVC2_TARGET_SHA256=""
expect_status 3 mvc2_verify_target "$TMP/SLUS_204.86"
echo 'PASS: active serial/hash pins; missing, wrong serial, size, hash, bypass refusal, valid synthetic fixture, missing hash'
