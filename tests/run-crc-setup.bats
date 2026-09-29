#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/run-crc-setup.sh"

setup() {
  TEST_ROOT=$(mktemp -d)
  mkdir -p "$TEST_ROOT/bin"
  export TEST_ROOT
  export TEST_CRC_START_COUNT="$TEST_ROOT/start-count"
  export TEST_CRC_START_PATHS="$TEST_ROOT/start-paths"
  printf '0\n' >"$TEST_CRC_START_COUNT"
  touch "$TEST_CRC_START_PATHS"

  cat >"$TEST_ROOT/bin/sudo" <<'EOF'
#!/usr/bin/env bash
shift 2
exec "$@"
EOF

  cat >"$TEST_ROOT/bin/crc" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  setup)
    [[ "${2:-}" == --check-only ]] && exit 1
    exit 0
    ;;
  start)
    secret_file=""
    while (($#)); do
      if [[ "$1" == --pull-secret-file ]]; then
        shift
        secret_file=$1
      fi
      shift
    done
    [[ -f "$secret_file" ]] || exit 1
    printf '%s\n' "$secret_file" >>"$TEST_CRC_START_PATHS"
    start_count=$(cat "$TEST_CRC_START_COUNT")
    start_count=$((start_count + 1))
    printf '%s\n' "$start_count" >"$TEST_CRC_START_COUNT"
    if [[ "$start_count" -eq 1 ]]; then
      echo "Failed to connect to the CRC VM with SSH" >&2
      exit 1
    fi
    exit 0
    ;;
  stop) exit 0 ;;
  *) exit 1 ;;
esac
EOF

  cat >"$TEST_ROOT/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  chmod +x "$TEST_ROOT/bin/sudo" "$TEST_ROOT/bin/crc" "$TEST_ROOT/bin/sleep"
  export PATH="$TEST_ROOT/bin:$PATH"
}

teardown() {
  rm -f /tmp/crc-start-attempt-1.log /tmp/crc-start-attempt-2.log /tmp/crc-start-attempt-3.log
  rm -rf "$TEST_ROOT"
}

@test "uses the supplied pull secret file across CRC start retries" {
  secret_file="$TEST_ROOT/pull-secret.json"
  printf '{"auths":{"example.com":{"auth":"secret"}}}' >"$secret_file"
  export PULL_SECRET_FILE="$secret_file"
  export USER="$(id -un)"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_CRC_START_COUNT")" -eq 2 ]
  printf -v expected_paths '%s\n%s' "$secret_file" "$secret_file"
  [ "$(cat "$TEST_CRC_START_PATHS")" = "$expected_paths" ]
  [ -f "$secret_file" ]
  [ ! -e pull-secret.json ]
}

@test "fails before CRC setup when the supplied pull secret file is missing" {
  export PULL_SECRET_FILE="$TEST_ROOT/missing-pull-secret.json"
  export USER="$(id -un)"

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Pull secret file not found"* ]]
  [ "$(cat "$TEST_CRC_START_COUNT")" -eq 0 ]
}
