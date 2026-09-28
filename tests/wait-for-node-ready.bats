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
    echo '{"items":[{"metadata":{"name":"crc-node"},"status":{"conditions":[{"type":"Ready","status":"True"}]}}]}'
    ;;
  false)
    echo '{"items":[{"metadata":{"name":"crc-node"},"status":{"conditions":[{"type":"Ready","status":"False"}]}}]}'
    ;;
  missing-node)
    echo '{"items":[]}'
    ;;
  missing-condition)
    echo '{"items":[{"metadata":{"name":"crc-node"},"status":{"conditions":[]}}]}'
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
      echo '{"items":[{"metadata":{"name":"crc-node"},"status":{"conditions":[{"type":"Ready","status":"Unknown"}]}}]}'
    else
      echo '{"items":[{"metadata":{"name":"crc-node"},"status":{"conditions":[{"type":"Ready","status":"True"}]}}]}'
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

@test "succeeds for a differently named CRC node with Ready=True" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Ready status unknown"* ]]
}

@test "waits and times out when the node Ready condition is False" {
  export MOCK_OC_MODE=false
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Ready=False; nodes: crc-node (Ready=False)"* ]]
  [[ "$output" =~ "Timeout reached: Node not ready" ]]
  [[ "$output" == *"observed nodes: crc-node (Ready=False)"* ]]
}

@test "waits and times out when the CRC node is missing" {
  export MOCK_OC_MODE=missing-node
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "No nodes returned by oc get nodes" ]]
  [[ "$output" =~ "Ready status unknown; nodes: none" ]]
  [[ "$output" =~ "observed nodes: none" ]]
}

@test "waits and times out when the Ready condition is missing" {
  export MOCK_OC_MODE=missing-condition
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Ready status unknown; nodes: crc-node (Ready=unknown)"* ]]
  [[ "$output" == *"observed nodes: crc-node (Ready=unknown)"* ]]
}

@test "waits and times out when node JSON is malformed" {
  export MOCK_OC_MODE=malformed
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "jq could not parse the node data" ]]
  [[ "$output" =~ "Ready status unknown" ]]
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
  [[ "$output" =~ "Ready status unknown" ]]
}

@test "continues polling after an unknown status and succeeds on True" {
  export MOCK_OC_MODE=unknown-then-true
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Ready status unknown" ]]
}
