#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/pull-bundle-from-image-cache.sh"
IMAGE_TAG_PREFIX="quay.io/bapalm/quick-ocp-cache"

setup() {
  TEST_ROOT=$(mktemp -d)
  mkdir -p "$TEST_ROOT/home/.crc" "$TEST_ROOT/crc-cache" "$TEST_ROOT/mock-bin"
  ln -s "$TEST_ROOT/crc-cache" "$TEST_ROOT/home/.crc/cache"

  # Records every invocation so tests can assert on the image tag used.
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
  cp)
    [ "${MOCK_DOCKER_CP_FAIL:-0}" = "1" ] && exit 1
    cp "$TEST_ROOT/bundle.tar" "$3"
    ;;
  rm | rmi) exit 0 ;;
  *) exit 2 ;;
esac
EOF
  cat >"$TEST_ROOT/mock-bin/du" <<'EOF'
#!/bin/bash
printf '1024\t%s\n' "$2"
EOF
  chmod +x "$TEST_ROOT/mock-bin/docker" "$TEST_ROOT/mock-bin/du"
  touch "$TEST_ROOT/docker-args"

  ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
}

teardown() {
  rm -rf "$TEST_ROOT"
  rm -f /tmp/bundle.tar
}

# Builds the bundle.tar the docker cp mock serves, containing a bundle
# named "$1".
make_bundle_tar() {
  printf 'bundle payload' >"$TEST_ROOT/$1"
  tar -cf "$TEST_ROOT/bundle.tar" -C "$TEST_ROOT" "$1"
}

# Usage: run_pull <fallback|preseed> [extra env assignments...].
# GITHUB_OUTPUT is pinned to a per-test file so assertions can read the
# emitted result and a bats run inside a CI step can never append to the
# runner's real output file.
run_pull() {
  local mode="$1"
  shift
  run env \
    HOME="$TEST_ROOT/home" OCP_VERSION=4.20 TEST_ROOT="$TEST_ROOT" \
    GITHUB_OUTPUT="$TEST_ROOT/gh-output" \
    PATH="$TEST_ROOT/mock-bin:$PATH" \
    "$@" \
    bash "$SCRIPT" "$mode"
}

@test "recognizes an existing bundle through the CRC cache symlink (fallback mode)" {
  touch "$TEST_ROOT/crc-cache/crc_libvirt_4.20.8_${ARCH}.crcbundle"

  run_pull fallback

  [ "$status" -eq 0 ]
  [[ "$output" == *"Bundle already present"* ]]
  [[ "$output" != *"pulling from Quay image cache"* ]]
  [ ! -s "$TEST_ROOT/docker-args" ]
}

@test "reports skipped-existing when a bundle is already present (preseed mode)" {
  touch "$TEST_ROOT/crc-cache/crc_libvirt_4.20.8_${ARCH}.crcbundle"
  run_pull preseed

  [ "$status" -eq 0 ]
  [[ "$output" == *"Bundle already present"* ]]
  [ "$(cat "$TEST_ROOT/gh-output")" = "result=skipped-existing" ]
}

@test "finds a bundle extracted through the CRC cache symlink using the arch-suffixed tag" {
  make_bundle_tar "crc_libvirt_4.20.8_${ARCH}.crcbundle"

  run_pull fallback

  [ "$status" -eq 0 ]
  [[ "$output" == *"Bundle extracted successfully"* ]]
  grep -q "manifest inspect ${IMAGE_TAG_PREFIX}:4.20-${ARCH}" "$TEST_ROOT/docker-args"
}

@test "preseed mode treats a missing Quay image as non-fatal" {
  make_bundle_tar "crc_libvirt_4.20.8_${ARCH}.crcbundle"
  run_pull preseed MOCK_DOCKER_MANIFEST_FAIL=1

  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [ "$(cat "$TEST_ROOT/gh-output")" = "result=skipped-unavailable" ]
}

@test "fallback mode fails when the Quay image is missing" {
  make_bundle_tar "crc_libvirt_4.20.8_${ARCH}.crcbundle"

  run_pull fallback MOCK_DOCKER_MANIFEST_FAIL=1

  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Quay image"* ]]
}

@test "preseed mode deletes a stale bundle and skips" {
  make_bundle_tar "crc_libvirt_4.20.0_${ARCH}.crcbundle"
  run_pull preseed EXPECTED_OCP_Z_VERSION=4.20.5

  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Image cache is stale"* ]]
  [ "$(cat "$TEST_ROOT/gh-output")" = "result=skipped-stale" ]
  [ ! -e "$TEST_ROOT/crc-cache/crc_libvirt_4.20.0_${ARCH}.crcbundle" ]
}

@test "fallback mode fails on a stale bundle" {
  make_bundle_tar "crc_libvirt_4.20.0_${ARCH}.crcbundle"

  run_pull fallback EXPECTED_OCP_Z_VERSION=4.20.5

  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match the version required by the installed crc binary"* ]]
  [ ! -e "$TEST_ROOT/crc-cache/crc_libvirt_4.20.0_${ARCH}.crcbundle" ]
}

@test "fallback mode does not re-pull an image the pre-seed proved stale" {
  make_bundle_tar "crc_libvirt_4.20.5_${ARCH}.crcbundle"

  run_pull fallback PRESEED_RESULT=skipped-stale

  [ "$status" -eq 1 ]
  [[ "$output" == *"already found stale"* ]]
  [ ! -s "$TEST_ROOT/docker-args" ]
}

@test "preseed mode keeps a fresh bundle and reports preseeded" {
  make_bundle_tar "crc_libvirt_4.20.5_${ARCH}.crcbundle"
  run_pull preseed EXPECTED_OCP_Z_VERSION=4.20.5

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_ROOT/gh-output")" = "result=preseeded" ]
  [ -e "$TEST_ROOT/crc-cache/crc_libvirt_4.20.5_${ARCH}.crcbundle" ]
  grep -q "rmi ${IMAGE_TAG_PREFIX}:4.20-${ARCH}" "$TEST_ROOT/docker-args"
}

@test "keys the Quay tag off the resolved z-version for latest (preseed mode)" {
  make_bundle_tar "crc_libvirt_4.22.14_${ARCH}.crcbundle"

  run_pull preseed OCP_VERSION=latest EXPECTED_OCP_Z_VERSION=4.22.14

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_ROOT/gh-output")" = "result=preseeded" ]
  grep -q "manifest inspect ${IMAGE_TAG_PREFIX}:4.22-${ARCH}" "$TEST_ROOT/docker-args"
  [ -e "$TEST_ROOT/crc-cache/crc_libvirt_4.22.14_${ARCH}.crcbundle" ]
}

@test "skips the freshness check when EXPECTED_OCP_Z_VERSION is not set" {
  make_bundle_tar "crc_libvirt_4.20.0_${ARCH}.crcbundle"
  run_pull preseed

  [ "$status" -eq 0 ]
  [[ "$output" != *"Image cache is stale"* ]]
  [ "$(cat "$TEST_ROOT/gh-output")" = "result=preseeded" ]
  [ -e "$TEST_ROOT/crc-cache/crc_libvirt_4.20.0_${ARCH}.crcbundle" ]
}

@test "skips the freshness check when EXPECTED_OCP_Z_VERSION is unparseable" {
  make_bundle_tar "crc_libvirt_4.20.0_${ARCH}.crcbundle"
  run_pull preseed EXPECTED_OCP_Z_VERSION=not-a-version

  [ "$status" -eq 0 ]
  [[ "$output" != *"Image cache is stale"* ]]
  [ "$(cat "$TEST_ROOT/gh-output")" = "result=preseeded" ]
  [ -e "$TEST_ROOT/crc-cache/crc_libvirt_4.20.0_${ARCH}.crcbundle" ]
}

@test "extraction failure is non-fatal in preseed mode" {
  make_bundle_tar "crc_libvirt_4.20.5_${ARCH}.crcbundle"
  run_pull preseed MOCK_DOCKER_CP_FAIL=1

  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [ "$(cat "$TEST_ROOT/gh-output")" = "result=failed" ]
}

@test "removes the staged bundle.tar when extraction fails (preseed mode)" {
  printf 'not a tar archive' >"$TEST_ROOT/bundle.tar"
  run_pull preseed

  [ "$status" -eq 0 ]
  [[ "$output" == *"Failed to extract bundle.tar"* ]]
  [ "$(cat "$TEST_ROOT/gh-output")" = "result=failed" ]
  [ ! -e /tmp/bundle.tar ]
}

@test "extraction failure is fatal in fallback mode" {
  make_bundle_tar "crc_libvirt_4.20.5_${ARCH}.crcbundle"

  run_pull fallback MOCK_DOCKER_CP_FAIL=1

  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Failed to copy bundle.tar"* ]]
}
