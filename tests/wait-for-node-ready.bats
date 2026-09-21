#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/wait-for-node-ready.sh"

setup() {
  TMPDIR=$(mktemp -d)
  export WAIT_FOR_NODE_READY_TIMEOUT=10
  export MOCK_OC_MODE=true
  export MOCK_OC_COUNT_FILE="$TMPDIR/oc-count"
  export REAL_JQ
  REAL_JQ=$(command -v jq)

  cat >"$TMPDIR/oc" <<'EOF'
#!/bin/bash
if [[ "$*" != *"-o json"* ]]; then
  exit 0
fi

case "${MOCK_OC_MODE:-true}" in
  true)
    echo '{"items":[{"metadata":{"name":"api.crc.testing"},"status":{"conditions":[{"reason":"KubeletReady","status":"True"}]}}]}'
    ;;
  false)
    echo '{"items":[{"metadata":{"name":"api.crc.testing"},"status":{"conditions":[{"reason":"KubeletReady","status":"False"}]}}]}'
    ;;
  missing-node)
    echo '{"items":[]}'
    ;;
  missing-condition)
    echo '{"items":[{"metadata":{"name":"api.crc.testing"},"status":{"conditions":[]}}]}'
    ;;
  malformed)
    echo 'not-json'
    ;;
  oc-failure)
    exit 42
    ;;
  unknown-then-true)
    count=0
    if [[ -f "$MOCK_OC_COUNT_FILE" ]]; then
      count=$(<"$MOCK_OC_COUNT_FILE")
    fi
    count=$((count + 1))
    echo "$count" >"$MOCK_OC_COUNT_FILE"
    if [[ "$count" -eq 1 ]]; then
      echo '{"items":[{"metadata":{"name":"api.crc.testing"},"status":{"conditions":[{"reason":"KubeletReady","status":"Unknown"}]}}]}'
    else
      echo '{"items":[{"metadata":{"name":"api.crc.testing"},"status":{"conditions":[{"reason":"KubeletReady","status":"True"}]}}]}'
    fi
    ;;
esac
EOF

  cat >"$TMPDIR/jq" <<'EOF'
#!/bin/bash
if [[ "${MOCK_JQ_MODE:-}" == "fail" ]]; then
  echo "mock jq failure" >&2
  exit 2
fi
exec "$REAL_JQ" "$@"
EOF

  for command in crc curl free getent journalctl sleep sudo; do
    cat >"$TMPDIR/$command" <<'EOF'
#!/bin/bash
exit 0
EOF
  done

  chmod +x "$TMPDIR"/*
  export PATH="$TMPDIR:$PATH"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "succeeds when KubeletReady is True" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"KubeletReady status unknown"* ]]
}

@test "waits and times out when KubeletReady is False" {
  export MOCK_OC_MODE=false
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "KubeletReady=False" ]]
  [[ "$output" =~ "Timeout reached: Node not ready" ]]
}

@test "waits and times out when the CRC node is missing" {
  export MOCK_OC_MODE=missing-node
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "api.crc.testing or its KubeletReady condition is missing" ]]
  [[ "$output" =~ "KubeletReady status unknown" ]]
}

@test "waits and times out when the KubeletReady condition is missing" {
  export MOCK_OC_MODE=missing-condition
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "api.crc.testing or its KubeletReady condition is missing" ]]
}

@test "waits and times out when node JSON is malformed" {
  export MOCK_OC_MODE=malformed
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "jq could not parse the node data" ]]
  [[ "$output" =~ "KubeletReady status unknown" ]]
}

@test "waits and times out when jq fails" {
  export MOCK_JQ_MODE=fail
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "mock jq failure" ]]
  [[ "$output" =~ "jq could not parse the node data" ]]
}

@test "waits and times out when oc fails" {
  export MOCK_OC_MODE=oc-failure
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "oc get nodes failed" ]]
  [[ "$output" =~ "KubeletReady status unknown" ]]
}

@test "continues polling after an unknown status and succeeds on True" {
  export MOCK_OC_MODE=unknown-then-true
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "KubeletReady status unknown" ]]
}
