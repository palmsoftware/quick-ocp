#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/pull-bundle-from-image-cache.sh"

setup() {
  TEST_ROOT=$(mktemp -d)
  mkdir -p "$TEST_ROOT/home/.crc" "$TEST_ROOT/crc-cache"
  ln -s "$TEST_ROOT/crc-cache" "$TEST_ROOT/home/.crc/cache"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "recognizes an existing bundle through the CRC cache symlink" {
  touch "$TEST_ROOT/crc-cache/crc_libvirt_4.19.8_amd64.crcbundle"

  run env HOME="$TEST_ROOT/home" OCP_VERSION=4.19 bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Bundle already present"* ]]
  [[ "$output" != *"attempting Quay image cache fallback"* ]]
}

@test "finds a bundle extracted through the CRC cache symlink" {
  mkdir "$TEST_ROOT/mock-bin"
  printf 'bundle payload' > "$TEST_ROOT/crc_libvirt_4.19.8_amd64.crcbundle"
  tar -cf "$TEST_ROOT/bundle.tar" -C "$TEST_ROOT" crc_libvirt_4.19.8_amd64.crcbundle

  cat > "$TEST_ROOT/mock-bin/docker" <<'EOF'
#!/bin/bash
case "$1" in
  manifest|pull|rm) exit 0 ;;
  create) echo mock-container ;;
  cp) cp "$TEST_ROOT/bundle.tar" "$3" ;;
  *) exit 2 ;;
esac
EOF
  cat > "$TEST_ROOT/mock-bin/du" <<'EOF'
#!/bin/bash
printf '1024\t%s\n' "$2"
EOF
  chmod +x "$TEST_ROOT/mock-bin/docker" "$TEST_ROOT/mock-bin/du"

  run env HOME="$TEST_ROOT/home" OCP_VERSION=4.19 TEST_ROOT="$TEST_ROOT" PATH="$TEST_ROOT/mock-bin:$PATH" bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Bundle extracted successfully"* ]]
}
