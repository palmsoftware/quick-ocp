#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/set-adm-policy.sh"

setup() {
  TMPDIR=$(mktemp -d)
  export MOCK_OC_COUNT_FILE="$TMPDIR/oc-count"
  export MOCK_OC_ARGS_FILE="$TMPDIR/oc-args"
  export MOCK_OC_FAILURES=0
  export SET_ADM_POLICY_ATTEMPTS=3
  export SET_ADM_POLICY_INTERVAL=0

  cat >"$TMPDIR/oc" <<'EOF'
#!/bin/bash
echo "$*" >>"$MOCK_OC_ARGS_FILE"
count=0
if [[ -f "$MOCK_OC_COUNT_FILE" ]]; then
  count=$(<"$MOCK_OC_COUNT_FILE")
fi
count=$((count + 1))
echo "$count" >"$MOCK_OC_COUNT_FILE"
if ((count <= MOCK_OC_FAILURES)); then
  echo "read: connection reset by peer" >&2
  exit 1
fi
echo "clusterrole.rbac.authorization.k8s.io/system:openshift:scc:privileged added"
EOF
  chmod +x "$TMPDIR/oc"
  export PATH="$TMPDIR:$PATH"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "applies both policies on the first try" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(<"$MOCK_OC_COUNT_FILE")" -eq 2 ]
  grep -q "add-scc-to-user privileged user --request-timeout=30s" "$MOCK_OC_ARGS_FILE"
  grep -q "add-scc-to-group privileged system:authenticated --request-timeout=30s" "$MOCK_OC_ARGS_FILE"
  [[ "$output" != *"::warning::"* ]]
}

@test "retries a transient connection reset and succeeds" {
  export MOCK_OC_FAILURES=2
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(<"$MOCK_OC_COUNT_FILE")" -eq 4 ]
  [[ "$output" == *"::warning::"*"attempt 1/3"*"connection reset by peer"* ]]
  [[ "$output" == *"attempt 2/3"* ]]
}

@test "fails after exhausting all attempts" {
  export MOCK_OC_FAILURES=99
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(<"$MOCK_OC_COUNT_FILE")" -eq 3 ]
  [[ "$output" == *"failed after 3 attempts"*"connection reset by peer"* ]]
}
