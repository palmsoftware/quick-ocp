#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/preload-images.sh"

setup() {
  TEST_ROOT=$(mktemp -d)
  mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/home/.docker" "$TEST_ROOT/runner-temp"
  export TEST_ROOT
  export HOME="$TEST_ROOT/home"
  export RUNNER_TEMP="$TEST_ROOT/runner-temp"
  export TEST_TOKEN=registry-test-token
  export TEST_AUTHFILE_PATH="$TEST_ROOT/authfile-path"
  export TEST_PODMAN_ARGS="$TEST_ROOT/podman-args"
  export FAIL_LOGIN=false
  export FAIL_MIRROR=false
  touch "$TEST_AUTHFILE_PATH" "$TEST_PODMAN_ARGS"
  printf '{"auths":{"existing.example":{"auth":"existing"}}}\n' >"$HOME/.docker/config.json"
  cp "$HOME/.docker/config.json" "$TEST_ROOT/docker-config.before"

  cat >"$TEST_ROOT/bin/podman" <<'EOF'
#!/usr/bin/env bash
command_name=$1
shift
case "$command_name" in
  login)
    original_args="$*"
    authfile=""
    saw_password_stdin=false
    while (($#)); do
      case "$1" in
        --compat-auth-file) shift; authfile=$1 ;;
        --password-stdin) saw_password_stdin=true ;;
      esac
      shift
    done
    password=$(cat)
    [[ "$password" == "$TEST_TOKEN" ]] || exit 1
    [[ "$saw_password_stdin" == true ]] || exit 1
    [[ -f "$authfile" ]] || exit 1
    [[ "$(cat "$authfile")" == '{"auths":{}}' ]] || exit 1
    printf '%s\n' "$authfile" >"$TEST_AUTHFILE_PATH"
    printf '%s\n' 'temporary auth data' >"$authfile"
    printf '%s\n' "$original_args" >"$TEST_PODMAN_ARGS"
    [[ "$FAIL_LOGIN" != true ]]
    ;;
  *) exit 1 ;;
esac
EOF

  cat >"$TEST_ROOT/bin/oc" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  patch) exit 0 ;;
  get)
    if [[ " $* " == *" -o "* ]]; then
      printf 'registry.example.test\n'
    fi
    exit 0
    ;;
  whoami)
    printf '%s\n' "$TEST_TOKEN"
    ;;
  image)
    [[ "${2:-}" == mirror ]] || exit 1
    shift 2
    authfile=""
    while (($#)); do
      if [[ "$1" == --registry-config ]]; then
        shift
        authfile=$1
      fi
      shift
    done
    [[ -n "$authfile" && -f "$authfile" ]] || exit 1
    [[ "$(cat "$authfile")" == 'temporary auth data' ]] || exit 1
    printf '%s\n' "$authfile" >>"$TEST_ROOT/oc-authfiles"
    if [[ "$FAIL_MIRROR" == true ]]; then
      echo "error: mirror failed" >&2
      exit 1
    fi
    ;;
  *) exit 1 ;;
esac
EOF

  chmod +x "$TEST_ROOT/bin/podman" "$TEST_ROOT/bin/oc"
  export PATH="$TEST_ROOT/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "uses an action-scoped authfile and removes it after successful mirroring" {
  run bash "$SCRIPT" $'quay.io/example/app:latest\n'

  [ "$status" -eq 0 ]
  [[ "$output" == *"Image preload complete"* ]]
  authfile=$(cat "$TEST_AUTHFILE_PATH")
  [[ "$authfile" == "$RUNNER_TEMP"/quick-ocp-registry-auth.* ]]
  [[ "$(cat "$TEST_PODMAN_ARGS")" == *"--password-stdin"* ]]
  [[ "$(cat "$TEST_PODMAN_ARGS")" == *"--compat-auth-file"* ]]
  [[ "$(cat "$TEST_PODMAN_ARGS")" != *"--password "* ]]
  [ ! -e "$authfile" ]
  [ "$(cat "$TEST_ROOT/oc-authfiles")" = "$authfile" ]
  cmp -s "$HOME/.docker/config.json" "$TEST_ROOT/docker-config.before"
}

@test "removes the authfile after a registry mirror failure" {
  export FAIL_MIRROR=true

  run bash "$SCRIPT" 'quay.io/example/app:latest'

  [ "$status" -eq 1 ]
  [[ "$output" == *"Image preload summary"* ]]
  authfile=$(cat "$TEST_AUTHFILE_PATH")
  [ ! -e "$authfile" ]
  cmp -s "$HOME/.docker/config.json" "$TEST_ROOT/docker-config.before"
}

@test "removes the authfile when registry login fails" {
  export FAIL_LOGIN=true

  run bash "$SCRIPT" 'quay.io/example/app:latest'

  [ "$status" -ne 0 ]
  authfile=$(cat "$TEST_AUTHFILE_PATH")
  [ -n "$authfile" ]
  [ ! -e "$authfile" ]
  cmp -s "$HOME/.docker/config.json" "$TEST_ROOT/docker-config.before"
}

@test "does not create credentials when there are no images to preload" {
  run bash "$SCRIPT" ''

  [ "$status" -eq 0 ]
  [[ "$output" == *"No images to preload"* ]]
  [ ! -s "$TEST_AUTHFILE_PATH" ]
  [ -z "$(find "$RUNNER_TEMP" -mindepth 1 -print -quit)" ]
}
