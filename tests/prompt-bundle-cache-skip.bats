#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/prompt-bundle-cache-skip.sh"

@test "emits warning on GitHub-hosted runners" {
  export RUNNER_ENVIRONMENT=github-hosted
  export GITHUB_ACTIONS=true
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Skipping cache restore due to bundleCache being false" ]]
  [[ "$output" =~ "::warning::" ]]
  [[ "$output" =~ "bundleCache is disabled" ]]
}

@test "emits warning when GITHUB_ACTIONS is true and runner is not self-hosted" {
  unset RUNNER_ENVIRONMENT
  export GITHUB_ACTIONS=true
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "::warning::" ]]
}

@test "does not emit warning on self-hosted runners" {
  export RUNNER_ENVIRONMENT=self-hosted
  export GITHUB_ACTIONS=true
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Skipping cache restore due to bundleCache being false" ]]
  [[ ! "$output" =~ "::warning::" ]]
}

@test "does not emit warning outside GitHub Actions" {
  unset RUNNER_ENVIRONMENT
  unset GITHUB_ACTIONS
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Skipping cache restore due to bundleCache being false" ]]
  [[ ! "$output" =~ "::warning::" ]]
}
