#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/wait-for-operators.sh"

setup() {
  TMPDIR=$(mktemp -d)
  export MOCK_OC_MODE=ready
  export MOCK_OC_EXCLUDED=""
  export MOCK_OC_COUNT_FILE="$TMPDIR/oc-count"

  cat >"$TMPDIR/oc" <<'EOF'
#!/bin/bash
if [[ "$1" == "get" && "$2" == clusterversion/* ]]; then
  if [[ -n "${MOCK_OC_EXCLUDED:-}" ]]; then
    printf '%s\n' $MOCK_OC_EXCLUDED
  fi
  exit 0
fi

ready_rows() {
  echo "authentication 4.18.2 True False False 1m"
  echo "kube-apiserver 4.18.2 True False False 1m"
}

count=0
if [[ -f "$MOCK_OC_COUNT_FILE" ]]; then
  count=$(<"$MOCK_OC_COUNT_FILE")
fi
count=$((count + 1))
echo "$count" >"$MOCK_OC_COUNT_FILE"

case "${MOCK_OC_MODE:-ready}" in
  ready)
    ready_rows
    ;;
  progressing)
    echo "authentication 4.18.2 False True False 1m"
    echo "kube-apiserver 4.18.2 True False False 1m"
    ;;
  failure)
    echo "connection reset by peer" >&2
    exit 1
    ;;
  failure-then-ready)
    if [[ "$count" -eq 1 ]]; then
      echo "connection reset by peer" >&2
      exit 1
    fi
    ready_rows
    ;;
  empty)
    exit 0
    ;;
esac
EOF

  cat >"$TMPDIR/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF

  chmod +x "$TMPDIR"/*
  export PATH="$TMPDIR:$PATH"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "succeeds when all operators are ready" {
  run bash "$SCRIPT" 30
  [ "$status" -eq 0 ]
  [[ "$output" =~ "All operators are available" ]]
}

@test "rejects an invalid timeout" {
  run bash "$SCRIPT" abc
  [ "$status" -eq 1 ]
  [[ "$output" =~ "invalid timeout value" ]]
}

@test "waits and times out when an operator is not available" {
  export MOCK_OC_MODE=progressing
  run bash "$SCRIPT" 30
  [ "$status" -eq 1 ]
  [[ "$output" =~ "authentication Available=False Progressing=True Degraded=False" ]]
  [[ "$output" =~ "Timeout reached" ]]
}

@test "retries after a transient oc failure and succeeds" {
  export MOCK_OC_MODE=failure-then-ready
  run bash "$SCRIPT" 30
  [ "$status" -eq 0 ]
  [[ "$output" =~ "oc get co failed; retrying" ]]
  [[ "$output" =~ "All operators are available" ]]
}

@test "keeps retrying oc failures until the timeout" {
  export MOCK_OC_MODE=failure
  run bash "$SCRIPT" 30
  [ "$status" -eq 1 ]
  [[ "$output" =~ "oc get co failed; retrying" ]]
  [[ "$output" =~ "Timeout reached" ]]
}

@test "does not report ready when oc returns no operators" {
  export MOCK_OC_MODE=empty
  run bash "$SCRIPT" 30
  [ "$status" -eq 1 ]
  [[ "$output" =~ "No cluster operators returned" ]]
  [[ "$output" =~ "Timeout reached" ]]
}

@test "ignores excluded unmanaged operators" {
  export MOCK_OC_MODE=progressing
  export MOCK_OC_EXCLUDED="authentication"
  run bash "$SCRIPT" 30
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Excluding unmanaged operators from readiness check: authentication" ]]
  [[ "$output" =~ "All operators are available" ]]
}

@test "waits when every operator is excluded" {
  export MOCK_OC_EXCLUDED="authentication kube-apiserver"
  run bash "$SCRIPT" 30
  [ "$status" -eq 1 ]
  [[ "$output" =~ "No cluster operators returned" ]]
}
