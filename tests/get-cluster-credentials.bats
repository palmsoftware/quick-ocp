#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/get-cluster-credentials.sh"

setup() {
  TMPDIR=$(mktemp -d)
  export GITHUB_OUTPUT="$TMPDIR/github_output"
  touch "$GITHUB_OUTPUT"

  cat >"$TMPDIR/crc" <<'EOF'
#!/bin/bash
if [ "$1" = "console" ] && [ "$2" = "--credentials" ]; then
  if [ -n "${MOCK_CRC_CREDENTIALS:-}" ]; then
    echo "$MOCK_CRC_CREDENTIALS"
    exit 0
  fi
fi
exit 1
EOF
  chmod +x "$TMPDIR/crc"
  export PATH="$TMPDIR:$PATH"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "fails when CRC credentials output is empty" {
  export MOCK_CRC_CREDENTIALS=""
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "Failed to extract kubeadmin password" ]]
}

@test "fails when JSON credentials have empty password" {
  export MOCK_CRC_CREDENTIALS='{"clusterConfig":{"adminCredentials":{"password":""}}}'
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "Failed to extract kubeadmin password" ]]
}

@test "fails when JSON credentials have null password" {
  export MOCK_CRC_CREDENTIALS='{"clusterConfig":{"adminCredentials":{"password":null}}}'
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "Failed to extract kubeadmin password" ]]
}

@test "fails when text credentials have no password line" {
  export MOCK_CRC_CREDENTIALS="No credentials available"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
  [[ "$output" =~ "Failed to extract kubeadmin password" ]]
}

@test "succeeds with text credentials from oc login format" {
  export MOCK_CRC_CREDENTIALS="To login as an admin, run 'oc login -u kubeadmin -p oc-login-pass https://api.crc.testing:6443'"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "kubeadmin-password=oc-login-pass" "$GITHUB_OUTPUT"
}

@test "succeeds with kubeadmin-password file fallback" {
  unset MOCK_CRC_CREDENTIALS
  mkdir -p "$TMPDIR/.crc/machines/crc"
  echo "file-fallback-pass" >"$TMPDIR/.crc/machines/crc/kubeadmin-password"
  export HOME="$TMPDIR"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "kubeadmin-password=file-fallback-pass" "$GITHUB_OUTPUT"
}

@test "succeeds with JSON credentials" {
  export MOCK_CRC_CREDENTIALS='{"clusterConfig":{"adminCredentials":{"password":"test-pass-123"}}}'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "kubeadmin-password=test-pass-123" "$GITHUB_OUTPUT"
  grep -q "api-url=https://api.crc.testing:6443" "$GITHUB_OUTPUT"
  grep -q "console-url=https://console-openshift-console.apps-crc.testing" "$GITHUB_OUTPUT"
}
