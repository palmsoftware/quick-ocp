#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/set-crc-version.sh"
REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TMPDIR=$(mktemp -d)
  export GITHUB_OUTPUT="$TMPDIR/github_output"
  touch "$GITHUB_OUTPUT"

  # Minimal mock for fetch-ocp-crc-version.sh (not called in explicit-version tests)
  mkdir -p "$TMPDIR/scripts"
  cat >"$TMPDIR/scripts/fetch-ocp-crc-version.sh" <<'EOF'
#!/bin/bash
echo "2.99.0"
EOF
  chmod +x "$TMPDIR/scripts/fetch-ocp-crc-version.sh"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "normalizes YAML float 4.2 to 4.20" {
  run bash "$SCRIPT" "4.2" "$REPO_ROOT" "2.54.0"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Normalized version from 4.2 to 4.20" ]]
  grep -q "crc_version=2.54.0" "$GITHUB_OUTPUT"
}

@test "does not normalize 4.18 (already two digits)" {
  run bash "$SCRIPT" "4.18" "$REPO_ROOT" "2.54.0"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "Normalized" ]]
  grep -q "crc_version=2.54.0" "$GITHUB_OUTPUT"
}

@test "explicit CRC version bypasses version detection" {
  run bash "$SCRIPT" "4.19" "$REPO_ROOT" "2.54.0"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "explicitly specified CRC version: 2.54.0" ]]
  grep -q "crc_version=2.54.0" "$GITHUB_OUTPUT"
}

@test "latest OCP version sets crc_version=latest without pins" {
  run bash "$SCRIPT" "latest" "$TMPDIR" ""
  [ "$status" -eq 0 ]
  grep -q "crc_version=latest" "$GITHUB_OUTPUT"
}

@test "rejects unsupported OCP version (4.17)" {
  run bash "$SCRIPT" "4.17" "$TMPDIR" ""
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Only OpenShift versions 4.18 and above are supported" ]]
}

@test "rejects completely invalid OCP version string" {
  run bash "$SCRIPT" "invalid" "$TMPDIR" ""
  [ "$status" -eq 1 ]
}
