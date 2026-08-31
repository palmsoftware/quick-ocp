#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/validate-runner.sh"

setup() {
  TMPDIR=$(mktemp -d)

  cat >"$TMPDIR/lsb_release" <<'EOF'
#!/bin/bash
echo "${MOCK_UBUNTU_VERSION:-22.04}"
EOF
  chmod +x "$TMPDIR/lsb_release"

  export PATH="$TMPDIR:$PATH"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "passes on supported Ubuntu 22.04" {
  export MOCK_UBUNTU_VERSION=22.04
  run bash "$SCRIPT" "4.19"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Runner compatibility check passed" ]]
}

@test "passes on supported Ubuntu 24.04" {
  export MOCK_UBUNTU_VERSION=24.04
  run bash "$SCRIPT" "4.21"
  [ "$status" -eq 0 ]
}

@test "passes on Ubuntu 26.04 with OCP 4.22" {
  export MOCK_UBUNTU_VERSION=26.04
  run bash "$SCRIPT" "4.22"
  [ "$status" -eq 0 ]
}

@test "passes on Ubuntu 26.04 with latest OCP" {
  export MOCK_UBUNTU_VERSION=26.04
  run bash "$SCRIPT" "latest"
  [ "$status" -eq 0 ]
}

@test "rejects unsupported Ubuntu 20.04" {
  export MOCK_UBUNTU_VERSION=20.04
  run bash "$SCRIPT" "4.19"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "Ubuntu 20.04 is not supported" ]]
}

@test "rejects Ubuntu 26.04 with OCP 4.19" {
  export MOCK_UBUNTU_VERSION=26.04
  run bash "$SCRIPT" "4.19"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "not supported on ubuntu-26.04" ]]
}

@test "rejects Ubuntu 26.04 with OCP 4.21" {
  export MOCK_UBUNTU_VERSION=26.04
  run bash "$SCRIPT" "4.21"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not supported on ubuntu-26.04" ]]
}

@test "normalizes YAML float 4.2 on Ubuntu 26.04 and rejects as OCP 4.20" {
  export MOCK_UBUNTU_VERSION=26.04
  run bash "$SCRIPT" "4.2"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Normalized version from 4.2 to 4.20" ]]
  [[ "$output" =~ "not supported on ubuntu-26.04" ]]
}
