#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/verify-image-cache-content.sh"
IMAGE_TAG="quay.io/bapalm/quick-ocp-cache:4.20-amd64"

setup() {
  TEST_ROOT=$(mktemp -d)
  mkdir -p "$TEST_ROOT/crc-bin" "$TEST_ROOT/mock-bin" "$TEST_ROOT/pins"

  # The pinned crc binary reports the z-version quick-ocp would install.
  cat >"$TEST_ROOT/crc-bin/crc" <<'EOF'
#!/bin/bash
printf '{"version":"2.57.0","openshiftVersion":"4.20.5"}\n'
EOF

  cat >"$TEST_ROOT/pins/crc-version-pins.json" <<'EOF'
{"version_pins": {"latest": "auto", "4.20": "2.57.0"}}
EOF

  cat >"$TEST_ROOT/mock-bin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_ROOT/docker-args"
case "$1" in
  manifest)
    [ "${MOCK_DOCKER_MANIFEST_FAIL:-0}" = "1" ] && exit 1
    exit 0
    ;;
  pull) exit 0 ;;
  create) echo mock-container ;;
  cp) cp "$TEST_ROOT/metadata.json" "$3" ;;
  rm | rmi) exit 0 ;;
  *) exit 2 ;;
esac
EOF

  chmod +x "$TEST_ROOT/crc-bin/crc" "$TEST_ROOT/mock-bin/docker"
  touch "$TEST_ROOT/docker-args"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

# Writes the metadata.json the docker cp mock serves: ocp, arch, crc, bundle
# name, bundle size.
write_metadata() {
  jq -n --arg ocp "$1" --arg arch "$2" --arg crc "$3" --arg bundle "$4" \
    --argjson size "$5" \
    '{ocp_version: $ocp, architecture: $arch, crc_version: $crc, bundle_name: $bundle, bundle_size: $size}' \
    >"$TEST_ROOT/metadata.json"
}

# Extra env assignments can be passed as arguments to override the defaults.
run_verify() {
  run env \
    OCP_VERSION=4.20 ARCH=amd64 \
    CRC_BINARY_DIR="$TEST_ROOT/crc-bin" \
    PINS_FILE="$TEST_ROOT/pins/crc-version-pins.json" \
    TEST_ROOT="$TEST_ROOT" \
    PATH="$TEST_ROOT/mock-bin:$PATH" \
    "$@" \
    bash "$SCRIPT"
}

@test "verifies an image that matches the runtime contract" {
  write_metadata 4.20 amd64 2.57.0 crc_libvirt_4.20.5_amd64.crcbundle 5900000000

  run_verify

  [ "$status" -eq 0 ]
  [[ "$output" == *"matches the runtime contract"* ]]
  grep -q "rmi ${IMAGE_TAG}" "$TEST_ROOT/docker-args"
}

@test "fails when the image carries a stale bundle" {
  write_metadata 4.20 amd64 2.57.0 crc_libvirt_4.20.0_amd64.crcbundle 5900000000

  run_verify

  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match the runtime contract"* ]]
}

@test "fails when the image was built with a different crc version than the pin" {
  write_metadata 4.20 amd64 2.56.0 crc_libvirt_4.20.5_amd64.crcbundle 5900000000

  run_verify

  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ crc_version: expected 2.57.0, got 2.56.0"* ]]
}

@test "fails when the bundle size is under 1 GiB" {
  write_metadata 4.20 amd64 2.57.0 crc_libvirt_4.20.5_amd64.crcbundle 1000000

  run_verify

  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ bundle_size"* ]]
}

@test "fails when the architecture does not match" {
  write_metadata 4.20 arm64 2.57.0 crc_libvirt_4.20.5_amd64.crcbundle 5900000000

  run_verify

  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ architecture: expected amd64, got arm64"* ]]
}

@test "fails when the cache image is missing from Quay" {
  write_metadata 4.20 amd64 2.57.0 crc_libvirt_4.20.5_amd64.crcbundle 5900000000

  run_verify MOCK_DOCKER_MANIFEST_FAIL=1

  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing cache image"* ]]
}

@test "skips verification when no pin entry exists for the minor" {
  write_metadata 4.20 amd64 2.57.0 crc_libvirt_4.20.5_amd64.crcbundle 5900000000

  run_verify OCP_VERSION=4.19

  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::No pin entry"* ]]
}

@test "verifies against a CRC_VERSION override instead of the pin" {
  jq '.version_pins["4.20"] = "2.56.0"' \
    "$TEST_ROOT/pins/crc-version-pins.json" >"$TEST_ROOT/pins/pins.tmp" &&
    mv "$TEST_ROOT/pins/pins.tmp" "$TEST_ROOT/pins/crc-version-pins.json"
  write_metadata 4.20 amd64 2.57.0 crc_libvirt_4.20.5_amd64.crcbundle 5900000000

  run_verify CRC_VERSION=2.57.0

  [ "$status" -eq 0 ]
  [[ "$output" == *"matches the runtime contract"* ]]
}
