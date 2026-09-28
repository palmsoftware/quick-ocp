#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/resolve-ocp-version.sh"
REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TMPDIR=$(mktemp -d)
  export GITHUB_OUTPUT="$TMPDIR/github_output"
  touch "$GITHUB_OUTPUT"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "redirects deprecated OCP 4.19 to 4.20 with a warning" {
  run bash "$SCRIPT" "4.19" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "::warning::desiredOCPVersion 4.19 is deprecated and will use 4.20." ]]
  grep -q "effective_version=4.20" "$GITHUB_OUTPUT"
  grep -q "crc_version_override=$" "$GITHUB_OUTPUT"
}

@test "ignores a CRC override for deprecated OCP 4.19" {
  run env CRC_VERSION_OVERRIDE="2.54.0" bash "$SCRIPT" "4.19" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "The crcVersion override was ignored." ]]
  grep -q "effective_version=4.20" "$GITHUB_OUTPUT"
  grep -q "crc_version_override=$" "$GITHUB_OUTPUT"
}

@test "leaves OCP 4.20 unchanged and preserves its CRC override" {
  run env CRC_VERSION_OVERRIDE="2.99.0" bash "$SCRIPT" "4.20" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "::warning::" ]]
  grep -q "effective_version=4.20" "$GITHUB_OUTPUT"
  grep -q "crc_version_override=2.99.0" "$GITHUB_OUTPUT"
}

@test "leaves OCP 4.18 unchanged" {
  run bash "$SCRIPT" "4.18" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "Normalized" ]]
  [[ ! "$output" =~ "::warning::" ]]
  grep -q "effective_version=4.18" "$GITHUB_OUTPUT"
}

@test "normalizes YAML float 4.2 to 4.20" {
  run bash "$SCRIPT" "4.2" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Normalized version from 4.2 to 4.20" ]]
  grep -q "effective_version=4.20" "$GITHUB_OUTPUT"
}

@test "leaves latest unchanged" {
  run bash "$SCRIPT" "latest" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "::warning::" ]]
  grep -q "effective_version=latest" "$GITHUB_OUTPUT"
}

@test "rejects unsupported OCP versions" {
  run bash "$SCRIPT" "4.17" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::Invalid desiredOCPVersion" ]]
}
