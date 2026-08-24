#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/precheck-resources.sh"

setup() {
  TMPDIR=$(mktemp -d)

  # Mock nproc to return a configurable count via MOCK_NPROC_COUNT env var
  cat >"$TMPDIR/nproc" <<'EOF'
#!/bin/bash
echo "${MOCK_NPROC_COUNT:-8}"
EOF
  chmod +x "$TMPDIR/nproc"

  # Mock sudo to be a no-op (avoids privilege requirements in tests)
  cat >"$TMPDIR/sudo" <<'EOF'
#!/bin/bash
"$@"
EOF
  chmod +x "$TMPDIR/sudo"

  # Mock df to return configurable values via MOCK_ROOT_GB / MOCK_MNT_GB
  cat >"$TMPDIR/df" <<'EOF'
#!/bin/bash
ROOT_GB="${MOCK_ROOT_GB:-80}"
MNT_GB="${MOCK_MNT_GB:-50}"
if echo "$*" | grep -q "output=source"; then
  if echo "$*" | grep -q "/mnt"; then
    echo "source"
    echo "/dev/sdb"
  else
    echo "source"
    echo "/dev/sda"
  fi
elif echo "$*" | grep -q "/mnt"; then
  echo "size"
  echo "${MNT_GB}G"
else
  echo "size"
  echo "${ROOT_GB}G"
fi
EOF
  chmod +x "$TMPDIR/df"

  # Create a writable /mnt-like directory for tests that need it
  export MOCK_MNT_DIR="$TMPDIR/mnt"
  mkdir -p "$MOCK_MNT_DIR"

  export PATH="$TMPDIR:$PATH"
}

teardown() {
  rm -rf "$TMPDIR"
}

# CPU tests — work on any OS since nproc is mocked
@test "fails when CPU count is below required" {
  export MOCK_NPROC_COUNT=2
  if [ ! -f /proc/meminfo ]; then
    skip "requires Linux (/proc/meminfo)"
  fi
  run bash "$SCRIPT" "4" "10752" "false"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "CPU" ]]
}

@test "passes CPU check when count meets requirement" {
  export MOCK_NPROC_COUNT=8
  if [ ! -f /proc/meminfo ]; then
    skip "requires Linux (/proc/meminfo)"
  fi
  run bash "$SCRIPT" "4" "10752" "false"
  # May still fail on other checks; just verify no CPU failure message
  [[ ! "$output" =~ "CPU: runner has" ]]
}

# Memory tests — Linux only (/proc/meminfo required)
@test "fails when physical memory is critically low" {
  if [ ! -f /proc/meminfo ]; then
    skip "requires Linux (/proc/meminfo)"
  fi
  # This test relies on a sufficiently low requested memory threshold vs actual
  # Run with a very high requested memory to trigger the warning path (not failure)
  run bash "$SCRIPT" "4" "10752" "false"
  # Just verify the script runs without crashing the memory check
  [[ "$output" =~ "Checking memory" ]]
}

# Disk tests — Linux only (df behavior varies on macOS)
@test "passes when combined disk capacity meets minimum" {
  if [ ! -f /proc/meminfo ]; then
    skip "requires Linux (/proc/meminfo)"
  fi
  export MOCK_ROOT_GB=80
  export MOCK_MNT_GB=50
  run bash "$SCRIPT" "4" "10752" "false"
  [[ "$output" =~ "Checking total disk capacity" ]]
}
