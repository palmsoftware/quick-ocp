#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/memory-pressure-monitor.sh"

setup() {
  TEST_ROOT=$(mktemp -d)
  mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/runner-temp"
  mkdir -p "$TEST_ROOT/proc/pressure" "$TEST_ROOT/cgroup"
  export RUNNER_TEMP="$TEST_ROOT/runner-temp"
  export PROC_ROOT="$TEST_ROOT/proc"
  export CGROUP_ROOT="$TEST_ROOT/cgroup"
  export CRC_MEMORY_SAMPLE_INTERVAL=1
  export TEST_ROOT
  printf 'MemTotal: 16384000 kB\nMemAvailable: 4800000 kB\nSwapTotal: 3145728 kB\nSwapFree: 2300000 kB\n' >"$PROC_ROOT/meminfo"
  printf 'pswpin 100\npswpout 200\n' >"$PROC_ROOT/vmstat"
  printf 'some avg10=0.00 avg60=0.00 avg300=0.00 total=1\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n' >"$PROC_ROOT/pressure/memory"
  printf '1048576\n' >"$CGROUP_ROOT/memory.current"
  printf 'max\n' >"$CGROUP_ROOT/memory.max"
  printf 'low 0\nhigh 0\nmax 0\noom 0\noom_kill 0\n' >"$CGROUP_ROOT/memory.events"

  cat >"$TEST_ROOT/bin/sudo" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "journalctl" ]; then
  exit 0
fi
exec "$@"
EOF
  chmod +x "$TEST_ROOT/bin/sudo"
  export PATH="$TEST_ROOT/bin:$PATH"
}

teardown() {
  pid_file="$RUNNER_TEMP/crc-memory-pressure.pid"
  if [ -f "$pid_file" ]; then
    kill "$(cat "$pid_file")" 2>/dev/null || true
  fi
  rm -rf "$TEST_ROOT"
}

@test "records host memory pressure and stops cleanly" {
  run bash "$SCRIPT" start
  [ "$status" -eq 0 ]
  sleep 0.2

  run bash "$SCRIPT" stop

  [ "$status" -eq 0 ]
  [[ "$output" == *"MemAvailable_kB="* ]]
  [[ "$output" == *"SwapFree_kB="* ]]
  [[ "$output" == *"psi_some="* ]]
  [ ! -e "$RUNNER_TEMP/crc-memory-pressure.pid" ]
}
