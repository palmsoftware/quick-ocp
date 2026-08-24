#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/write-pull-secret.sh"

setup() {
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "fails when PULL_SECRET is unset" {
  unset PULL_SECRET
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "PULL_SECRET environment variable is not set" ]]
}

@test "fails when PULL_SECRET is empty" {
  export PULL_SECRET=""
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "PULL_SECRET environment variable is not set" ]]
}

@test "fails when PULL_SECRET is not valid JSON" {
  export PULL_SECRET="not-json"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not valid JSON" ]]
}

@test "fails when PULL_SECRET has no auths key" {
  export PULL_SECRET='{"other": "value"}'
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "auths" ]]
}

@test "fails when PULL_SECRET has empty auths" {
  export PULL_SECRET='{"auths": {}}'
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "auths" ]]
}

@test "succeeds and writes file with valid pull secret" {
  export PULL_SECRET='{"auths":{"registry.example.com":{"auth":"dXNlcjpwYXNz"}}}'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "pull-secret.json" ]
  [ "$(cat pull-secret.json)" = "$PULL_SECRET" ]
}
