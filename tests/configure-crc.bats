#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/configure-crc.sh"

setup() {
  TMPDIR=$(mktemp -d)
  # Mock crc as a no-op so tests don't require a running CRC install
  cat >"$TMPDIR/crc" <<'EOF'
#!/bin/bash
echo "crc $*"
EOF
  chmod +x "$TMPDIR/crc"
  export PATH="$TMPDIR:$PATH"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "rejects non-integer crcCpu" {
  run bash "$SCRIPT" "abc" "10752" "31" "false" "false"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "crcCpu must be a positive integer" ]]
}

@test "rejects crcCpu below minimum (4)" {
  run bash "$SCRIPT" "2" "10752" "31" "false" "false"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "crcCpu must be at least 4" ]]
}

@test "rejects non-integer crcMemory" {
  run bash "$SCRIPT" "4" "bad" "31" "false" "false"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "crcMemory must be a positive integer" ]]
}

@test "rejects crcMemory below minimum (10752)" {
  run bash "$SCRIPT" "4" "8192" "31" "false" "false"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "crcMemory must be at least 10752" ]]
}

@test "rejects crcDiskSize below minimum (31)" {
  run bash "$SCRIPT" "4" "10752" "20" "false" "false"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "crcDiskSize must be at least 31" ]]
}

@test "succeeds with minimum valid configuration" {
  run bash "$SCRIPT" "4" "10752" "31" "false" "false"
  [ "$status" -eq 0 ]
}

@test "cluster monitoring enforces 14336MB memory floor" {
  run bash "$SCRIPT" "4" "10752" "31" "false" "true"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "14336MB memory" ]]
}
