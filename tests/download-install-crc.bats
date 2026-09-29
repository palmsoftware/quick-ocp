#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/download-install-crc.sh"

setup() {
  TEST_ROOT=$(mktemp -d)
  mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/install"
  export TEST_ROOT
  export TEST_INSTALL_DIR="$TEST_ROOT/install"
  export EXPECTED_HASH=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
  export ACTUAL_HASH=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  export CHECKSUM_MODE=match
  export INSTALL_SOURCE_FILE="$TEST_ROOT/install-source"

  cat >"$TEST_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env bash
output_file=""
url=""
while (($#)); do
  if [[ "$1" == -o ]]; then
    shift
    output_file=$1
  elif [[ "$1" == https://* ]]; then
    url=$1
  fi
  shift
done

if [[ "$url" == */sha256sum.txt ]]; then
  case "$CHECKSUM_MODE" in
    unavailable) exit 1 ;;
    missing) printf '%s  crc-linux-amd64.tar.xz.backup\n' "$EXPECTED_HASH" >"$output_file" ;;
    invalid) printf 'not-a-checksum  crc-linux-amd64.tar.xz\n' >"$output_file" ;;
    duplicate)
      printf '%s  crc-linux-amd64.tar.xz\n%s  crc-linux-amd64.tar.xz\n' "$EXPECTED_HASH" "$EXPECTED_HASH" >"$output_file"
      ;;
    match) printf '%s *crc-linux-amd64.tar.xz\n' "$EXPECTED_HASH" >"$output_file" ;;
    *) exit 1 ;;
  esac
else
  : >"$output_file"
fi
EOF

  cat >"$TEST_ROOT/bin/uname" <<'EOF'
#!/usr/bin/env bash
echo x86_64
EOF

  cat >"$TEST_ROOT/bin/stat" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == -c%s ]]; then
  echo 1048577
else
  exec /usr/bin/stat "$@"
fi
EOF

  cat >"$TEST_ROOT/bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
printf '%s  %s\n' "$ACTUAL_HASH" "$1"
EOF

  cat >"$TEST_ROOT/bin/tar" <<'EOF'
#!/usr/bin/env bash
destination=""
while (($#)); do
  if [[ "$1" == -C ]]; then
    shift
    destination=$1
  fi
  shift
done
mkdir -p "$destination/crc-linux-amd64"
: >"$destination/crc-linux-amd64/crc"
EOF

  cat >"$TEST_ROOT/bin/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == mv ]]; then
  cp "$2" "$TEST_INSTALL_DIR/crc"
  printf '%s\n' "$2" >"$INSTALL_SOURCE_FILE"
else
  exec "$@"
fi
EOF

  cat >"$TEST_ROOT/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  chmod +x "$TEST_ROOT/bin/"*
  export PATH="$TEST_ROOT/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "fails after retries when the checksum endpoint is unavailable" {
  export CHECKSUM_MODE=unavailable

  run bash "$SCRIPT" 2.54.0

  [ "$status" -eq 1 ]
  [[ "$output" == *"checksum verification is required"* ]]
  [[ "$output" == *"Failed to download CRC after 3 attempts"* ]]
  [ ! -e "$TEST_INSTALL_DIR/crc" ]
}

@test "fails when the checksum file has no exact entry for the archive" {
  export CHECKSUM_MODE=missing

  run bash "$SCRIPT" 2.54.0

  [ "$status" -eq 1 ]
  [[ "$output" == *"No checksum found for crc-linux-amd64.tar.xz"* ]]
  [ ! -e "$TEST_INSTALL_DIR/crc" ]
}

@test "fails when the checksum is malformed or ambiguous" {
  for mode in invalid duplicate; do
    export CHECKSUM_MODE="$mode"
    run bash "$SCRIPT" 2.54.0
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_INSTALL_DIR/crc" ]
  done
}

@test "fails after retries when the archive digest does not match" {
  export CHECKSUM_MODE=match
  export ACTUAL_HASH=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

  run bash "$SCRIPT" 2.54.0

  [ "$status" -eq 1 ]
  [[ "$output" == *"SHA256 mismatch"* ]]
  [ ! -e "$TEST_INSTALL_DIR/crc" ]
}

@test "installs CRC only after an exact SHA256 match" {
  run bash "$SCRIPT" 2.54.0

  [ "$status" -eq 0 ]
  [[ "$output" == *"SHA256 verified"* ]]
  [ -f "$TEST_INSTALL_DIR/crc" ]
  [ -s "$INSTALL_SOURCE_FILE" ]
}
