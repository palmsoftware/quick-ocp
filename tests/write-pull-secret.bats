#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/write-pull-secret.sh"
CLEANUP_SCRIPT="$BATS_TEST_DIRNAME/../scripts/cleanup-pull-secret.sh"

setup() {
  TMPDIR=$(mktemp -d)
  export TMPDIR
  export RUNNER_TEMP="$TMPDIR/runner-temp"
  export GITHUB_ENV="$TMPDIR/github-env"
  export GITHUB_OUTPUT="$TMPDIR/github-output"
  mkdir -p "$RUNNER_TEMP"
  touch "$GITHUB_ENV" "$GITHUB_OUTPUT"
  cd "$TMPDIR"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "fails when PULL_SECRET is unset" {
  unset PULL_SECRET
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "PULL_SECRET environment variable is not set" ]]
}

@test "fails when PULL_SECRET is empty" {
  export PULL_SECRET=""
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "PULL_SECRET environment variable is not set" ]]
}

@test "fails when PULL_SECRET is not valid JSON" {
  export PULL_SECRET="not-json"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "not valid JSON" ]]
}

@test "fails when PULL_SECRET has no auths key" {
  export PULL_SECRET='{"other": "value"}'
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "auths" ]]
}

@test "fails when PULL_SECRET has empty auths" {
  export PULL_SECRET='{"auths": {}}'
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "auths" ]]
}

@test "fails before writing a secret when GitHub output registration is unavailable" {
  export PULL_SECRET='{"auths":{"registry.example.com":{"auth":"dXNlcjpwYXNz"}}}'
  unset GITHUB_OUTPUT

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"GITHUB_ENV and GITHUB_OUTPUT are required"* ]]
  [ -z "$(find "$RUNNER_TEMP" -mindepth 1 -print -quit)" ]
}

@test "succeeds and writes file with valid pull secret" {
  export PULL_SECRET='{"auths":{"registry.example.com":{"auth":"dXNlcjpwYXNz"}}}'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$PULL_SECRET"* ]]

  secret_file=$(sed -n 's/^path=//p' "$GITHUB_OUTPUT")
  state_dir=$(sed -n 's/^QUICK_OCP_PULL_SECRET_STATE_DIR=//p' "$GITHUB_ENV")
  [ -f "$secret_file" ]
  [[ "$secret_file" == "$RUNNER_TEMP"/quick-ocp-pull-secret.*/pull-secret.json ]]
  [ "$(cat "$secret_file")" = "$PULL_SECRET" ]

  directory_mode=$(stat -c '%a' "$state_dir" 2>/dev/null || stat -f '%Lp' "$state_dir")
  file_mode=$(stat -c '%a' "$secret_file" 2>/dev/null || stat -f '%Lp' "$secret_file")
  [ "$directory_mode" = "700" ]
  [ "$file_mode" = "600" ]

  run env QUICK_OCP_PULL_SECRET_STATE_DIR="$state_dir" bash "$CLEANUP_SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$secret_file" ]
  [ ! -d "$state_dir" ]
}

@test "refuses to clean paths outside the private runner temp directory" {
  run env QUICK_OCP_PULL_SECRET_STATE_DIR="$TMPDIR" bash "$CLEANUP_SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"unexpected pull secret state path"* ]]
  [ -d "$TMPDIR" ]
}
