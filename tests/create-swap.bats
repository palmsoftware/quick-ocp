#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/create-swap.sh"

setup() {
  TEST_ROOT=$(mktemp -d)
  mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/mnt"
  export PROC_SWAPS_FILE="$TEST_ROOT/proc-swaps"
  export SWAP_DIR="$TEST_ROOT/mnt"
  export SWAPFILE_BASE="$SWAP_DIR/swapfile"
  export TEST_ROOT
  printf 'Filename Type Size Used Priority\n/swapfile file 3145728 0 -2\n' >"$PROC_SWAPS_FILE"

  cat >"$TEST_ROOT/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
  cat >"$TEST_ROOT/bin/fallocate" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_ROOT/fallocate.log"
printf '%s\n' "$2" >"$TEST_ROOT/fallocate-size"
touch "${@: -1}"
EOF
  cat >"$TEST_ROOT/bin/mkswap" <<'EOF'
#!/bin/bash
exit 0
EOF
  cat >"$TEST_ROOT/bin/swapon" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "--show" ]; then
  printf 'NAME TYPE SIZE USED PRIO\n'
  awk 'NR > 1 { printf "%s file %s 0 -2\n", $1, $3 * 1024 }' "$PROC_SWAPS_FILE"
  exit 0
fi
size_mb=$(sed 's/M$//' "$TEST_ROOT/fallocate-size")
printf '%s file %s 0 -2\n' "$1" "$((size_mb * 1024))" >>"$PROC_SWAPS_FILE"
EOF
  cat >"$TEST_ROOT/bin/sysctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_ROOT/sysctl.log"
if [ "${1:-}" = "-w" ]; then
  printf '%s\n' "${2#*=}"
fi
EOF
  cat >"$TEST_ROOT/bin/df" <<'EOF'
#!/bin/bash
printf 'Avail\n100000000\n'
EOF
  chmod +x "$TEST_ROOT/bin/"*
  export PATH="$TEST_ROOT/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "tops up existing swap to 8 GiB and raises swappiness" {
  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Active swap is 3072MiB; adding 5120MiB"* ]]
  grep -q -- '-l 5120M' "$TEST_ROOT/fallocate.log"
  grep -q -- '-w vm.swappiness=100' "$TEST_ROOT/sysctl.log"
  grep -q "$SWAPFILE_BASE file 5242880" "$PROC_SWAPS_FILE"
}

@test "does not add swap when the 8 GiB target is already met" {
  printf 'Filename Type Size Used Priority\n/swapfile file 8388608 0 -2\n' >"$PROC_SWAPS_FILE"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"target 8GiB already met"* ]]
  [ ! -e "$TEST_ROOT/fallocate.log" ]
  grep -q -- '-w vm.swappiness=100' "$TEST_ROOT/sysctl.log"
}
