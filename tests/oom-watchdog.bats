#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/protect-crc-from-oom.sh"
STOP_SCRIPT="$BATS_TEST_DIRNAME/../scripts/stop-oom-watchdog.sh"

setup() {
  TEST_ROOT=$(mktemp -d)
  PROC_ROOT="$TEST_ROOT/proc"
  RUNNER_TEMP="$TEST_ROOT/runner-temp"
  mkdir -p "$PROC_ROOT/4242" "$PROC_ROOT/4343" "$RUNNER_TEMP" "$TEST_ROOT/bin"
  export TEST_ROOT PROC_ROOT RUNNER_TEMP
  export CRC_OOM_PROC_ROOT="$PROC_ROOT"
  export GITHUB_ENV="$TEST_ROOT/github-env"
  touch "$GITHUB_ENV"

  local stat_rest=S
  local _
  for _ in {1..18}; do
    stat_rest+=" 0"
  done
  stat_rest+=" 12345"

  printf 'qemu-system-x86_64\n' >"$PROC_ROOT/4242/comm"
  printf 'qemu-system-x86_64\0-name\0guest=crc,debug-threads=on\0' >"$PROC_ROOT/4242/cmdline"
  printf '4242 (qemu-system-x86_64) %s\n' "$stat_rest" >"$PROC_ROOT/4242/stat"
  printf '0\n' >"$PROC_ROOT/4242/oom_score_adj"

  printf 'qemu-kvm\n' >"$PROC_ROOT/4343/comm"
  printf 'qemu-kvm\0-name\0guest=unrelated-vm,debug-threads=on\0' >"$PROC_ROOT/4343/cmdline"
  printf '4343 (qemu-kvm) %s\n' "$stat_rest" >"$PROC_ROOT/4343/stat"
  printf '0\n' >"$PROC_ROOT/4343/oom_score_adj"

  cat >"$TEST_ROOT/bin/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == tee ]]; then
  cat >"$2"
else
  exec "$@"
fi
EOF
  chmod +x "$TEST_ROOT/bin/sudo"
  export PATH="$TEST_ROOT/bin:$PATH"
}

teardown() {
  if [[ -f "$GITHUB_ENV" ]]; then
    state_dir=$(sed -n 's/^CRC_OOM_WATCHDOG_STATE_DIR=//p' "$GITHUB_ENV")
    if [[ -n "$state_dir" ]]; then
      CRC_OOM_WATCHDOG_STATE_DIR="$state_dir" bash "$STOP_SCRIPT" >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "$TEST_ROOT"
}

@test "protects only the CRC VM and stops its owned watchdog" {
  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"CRC OOM watchdog started"* ]]
  [ "$(cat "$PROC_ROOT/4242/oom_score_adj")" = "-500" ]
  [ "$(cat "$PROC_ROOT/4343/oom_score_adj")" = "0" ]

  state_dir=$(sed -n 's/^CRC_OOM_WATCHDOG_STATE_DIR=//p' "$GITHUB_ENV")
  [ -n "$state_dir" ]
  watchdog_pid=$(sed -n '1p' "$state_dir/watchdog")
  kill -0 "$watchdog_pid"

  run env CRC_OOM_WATCHDOG_STATE_DIR="$state_dir" bash "$STOP_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OOM watchdog stopped"* ]]
  [ ! -d "$state_dir" ]
  ! kill -0 "$watchdog_pid" 2>/dev/null
}

@test "does not signal an unrelated process when the recorded PID was reused" {
  state_dir=$(mktemp -d "$RUNNER_TEMP/crc-oom-watchdog.XXXXXX")
  chmod 700 "$state_dir"
  printf '%s\n' "$BASHPID" 1 0123456789abcdef0123456789abcdef >"$state_dir/watchdog"

  run env CRC_OOM_WATCHDOG_STATE_DIR="$state_dir" bash "$STOP_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"PID $BASHPID has been reused"* ]]
  kill -0 "$BASHPID"
  [ ! -d "$state_dir" ]
}

@test "does not signal a process without the watchdog ownership marker" {
  state_dir=$(mktemp -d "$RUNNER_TEMP/crc-oom-watchdog.XXXXXX")
  chmod 700 "$state_dir"
  start_time=$(ps -o lstart= -p "$BASHPID" | tr -d '[:space:]')
  printf '%s\n' "$BASHPID" "$start_time" 0123456789abcdef0123456789abcdef >"$state_dir/watchdog"

  run env CRC_OOM_WATCHDOG_STATE_DIR="$state_dir" bash "$STOP_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"does not have the expected ownership marker"* ]]
  kill -0 "$BASHPID"
  [ ! -d "$state_dir" ]
}

@test "skips OOM protection when the CRC VM cannot be identified uniquely" {
  printf 'qemu-system-x86_64\0-name\0guest=other-vm,debug-threads=on\0' >"$PROC_ROOT/4242/cmdline"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"found 0"* ]]
  [ "$(cat "$PROC_ROOT/4242/oom_score_adj")" = "0" ]
  [ ! -s "$GITHUB_ENV" ]
}

@test "skips OOM protection when multiple CRC VMs match" {
  printf 'qemu-kvm\0-name\0guest=crc,debug-threads=on\0' >"$PROC_ROOT/4343/cmdline"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"found 2"* ]]
  [ "$(cat "$PROC_ROOT/4242/oom_score_adj")" = "0" ]
  [ "$(cat "$PROC_ROOT/4343/oom_score_adj")" = "0" ]
  [ ! -s "$GITHUB_ENV" ]
}

@test "watchdog exits when the captured CRC PID no longer has the recorded start time" {
  run env \
    CRC_OOM_WATCHDOG_TARGET_PID=4242 \
    CRC_OOM_WATCHDOG_TARGET_START_TIME=54321 \
    CRC_OOM_WATCHDOG_TARGET_PROC_ROOT="$PROC_ROOT" \
    CRC_OOM_WATCHDOG_INTERVAL=0 \
    bash "$SCRIPT" --watchdog

  [ "$status" -eq 0 ]
  [ "$(cat "$PROC_ROOT/4242/oom_score_adj")" = "0" ]
}
