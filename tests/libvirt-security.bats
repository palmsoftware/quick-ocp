#!/usr/bin/env bats

CONFIGURE_SCRIPT="$BATS_TEST_DIRNAME/../scripts/configure-libvirt-security.sh"
RESTORE_SCRIPT="$BATS_TEST_DIRNAME/../scripts/restore-libvirt-security.sh"

setup() {
  TEST_ROOT=$(mktemp -d)
  mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/runner-temp" "$(dirname "$TEST_ROOT/qemu.conf")"
  export TEST_ROOT
  export RUNNER_TEMP="$TEST_ROOT/runner-temp"
  export GITHUB_ENV="$TEST_ROOT/github-env"
  export LIBVIRT_QEMU_CONF="$TEST_ROOT/qemu.conf"
  export RUNNER_ENVIRONMENT=github-hosted
  export TEST_LIBVIRT_SERVICE_STATE="$TEST_ROOT/libvirtd.state"
  export TEST_LIBVIRT_SOCKET_ACTIVE="$TEST_ROOT/libvirtd-socket.active"
  export TEST_LIBVIRT_SOCKET_ENABLED="$TEST_ROOT/libvirtd-socket.enabled"
  export TEST_SYSTEMCTL_LOG="$TEST_ROOT/systemctl.log"
  touch "$GITHUB_ENV" "$TEST_SYSTEMCTL_LOG"
  printf 'active\n' >"$TEST_LIBVIRT_SERVICE_STATE"
  printf 'inactive\n' >"$TEST_LIBVIRT_SOCKET_ACTIVE"
  printf 'disabled\n' >"$TEST_LIBVIRT_SOCKET_ENABLED"

  cat >"$TEST_ROOT/bin/sudo" <<'EOF'
#!/usr/bin/env bash
command_name=$1
shift
case "$command_name" in
  install)
    mode=644
    while (($#)); do
      case "$1" in
        -o | -g) shift 2 ;;
        -m) mode=$2; shift 2 ;;
        *) break ;;
      esac
    done
    source_file=$1
    destination=$2
    cp "$source_file" "$destination"
    chmod "$mode" "$destination"
    ;;
  systemctl) exec systemctl "$@" ;;
  mv) exec mv "$@" ;;
  rm) exec rm "$@" ;;
  *) exec "$command_name" "$@" ;;
esac
EOF

  cat >"$TEST_ROOT/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
command_name=$1
shift
case "$command_name" in
  list-unit-files)
    printf 'libvirtd.service enabled\nlibvirtd.socket disabled\n'
    ;;
  is-active)
    [[ "${1:-}" == --quiet ]] && shift
    case "$1" in
      libvirtd) [[ "$(cat "$TEST_LIBVIRT_SERVICE_STATE")" == active ]] ;;
      libvirtd.socket) [[ "$(cat "$TEST_LIBVIRT_SOCKET_ACTIVE")" == active ]] ;;
      *) exit 1 ;;
    esac
    ;;
  is-enabled)
    [[ "${1:-}" == --quiet ]] && shift
    [[ "$(cat "$TEST_LIBVIRT_SOCKET_ENABLED")" == enabled ]]
    ;;
  restart | start | stop | enable | disable)
    printf '%s %s\n' "$command_name" "$1" >>"$TEST_SYSTEMCTL_LOG"
    if [[ "$command_name" == restart && "${FAIL_RESTART:-false}" == true ]]; then
      exit 1
    fi
    case "$1" in
      libvirtd)
        if [[ "$command_name" == stop ]]; then
          printf 'inactive\n' >"$TEST_LIBVIRT_SERVICE_STATE"
        else
          printf 'active\n' >"$TEST_LIBVIRT_SERVICE_STATE"
        fi
        ;;
      libvirtd.socket)
        case "$command_name" in
          start) printf 'active\n' >"$TEST_LIBVIRT_SOCKET_ACTIVE" ;;
          stop) printf 'inactive\n' >"$TEST_LIBVIRT_SOCKET_ACTIVE" ;;
          enable) printf 'enabled\n' >"$TEST_LIBVIRT_SOCKET_ENABLED" ;;
          disable) printf 'disabled\n' >"$TEST_LIBVIRT_SOCKET_ENABLED" ;;
        esac
        ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF

  chmod +x "$TEST_ROOT/bin/sudo" "$TEST_ROOT/bin/systemctl"
  export PATH="$TEST_ROOT/bin:$PATH"
}

teardown() {
  state_dir=$(sed -n 's/^LIBVIRT_SECURITY_STATE_DIR=//p' "$GITHUB_ENV" 2>/dev/null || true)
  if [[ -n "$state_dir" ]]; then
    LIBVIRT_SECURITY_STATE_DIR="$state_dir" bash "$RESTORE_SCRIPT" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEST_ROOT"
}

state_dir_from_env() {
  sed -n 's/^LIBVIRT_SECURITY_STATE_DIR=//p' "$GITHUB_ENV" | tail -1
}

@test "temporarily overrides one security setting and restores it with service state" {
  printf '# keep this comment\nsecurity_driver = "selinux"\nremember_owner = 1\n' >"$LIBVIRT_QEMU_CONF"

  run bash "$CONFIGURE_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$(cat "$LIBVIRT_QEMU_CONF")" == *'security_driver = "none"'* ]]
  [[ "$(cat "$LIBVIRT_QEMU_CONF")" == *'# keep this comment'* ]]
  [[ "$(cat "$LIBVIRT_QEMU_CONF")" == *'remember_owner = 1'* ]]
  state_dir=$(state_dir_from_env)
  [ -n "$state_dir" ]
  state_dir_mode=$(stat -c '%a' "$state_dir" 2>/dev/null || stat -f '%Lp' "$state_dir")
  [ "$state_dir_mode" = "700" ]

  run env LIBVIRT_SECURITY_STATE_DIR="$state_dir" bash "$CONFIGURE_SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'quick-ocp temporary libvirt security setting' "$LIBVIRT_QEMU_CONF")" -eq 1 ]

  printf 'log_level = 2\n' >>"$LIBVIRT_QEMU_CONF"
  systemctl enable libvirtd.socket
  systemctl start libvirtd.socket
  run env LIBVIRT_SECURITY_STATE_DIR="$state_dir" bash "$RESTORE_SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(cat "$LIBVIRT_QEMU_CONF")" = $'# keep this comment\nsecurity_driver = "selinux"\nremember_owner = 1\nlog_level = 2' ]
  [ "$(cat "$TEST_LIBVIRT_SERVICE_STATE")" = active ]
  [ "$(cat "$TEST_LIBVIRT_SOCKET_ACTIVE")" = inactive ]
  [ "$(cat "$TEST_LIBVIRT_SOCKET_ENABLED")" = disabled ]
  [ ! -d "$state_dir" ]
}

@test "removes a qemu.conf created only for the temporary workaround" {
  run bash "$CONFIGURE_SCRIPT"

  [ "$status" -eq 0 ]
  [ -f "$LIBVIRT_QEMU_CONF" ]
  state_dir=$(state_dir_from_env)

  run env LIBVIRT_SECURITY_STATE_DIR="$state_dir" bash "$RESTORE_SCRIPT"

  [ "$status" -eq 0 ]
  [ ! -e "$LIBVIRT_QEMU_CONF" ]
  [ ! -d "$state_dir" ]
}

@test "fails closed outside GitHub-hosted runners without changing configuration" {
  printf 'security_driver = "selinux"\n' >"$LIBVIRT_QEMU_CONF"

  for runner_environment in self-hosted unknown; do
    export RUNNER_ENVIRONMENT="$runner_environment"
    run bash "$CONFIGURE_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" == *"limited to GitHub-hosted runners"* ]]
    [ "$(cat "$LIBVIRT_QEMU_CONF")" = 'security_driver = "selinux"' ]
  done
  [ ! -s "$GITHUB_ENV" ]
}

@test "refuses ambiguous duplicate active security settings" {
  printf 'security_driver = "selinux"\nsecurity_driver = "apparmor"\n' >"$LIBVIRT_QEMU_CONF"

  run bash "$CONFIGURE_SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Multiple active security_driver settings"* ]]
  [ "$(cat "$LIBVIRT_QEMU_CONF")" = $'security_driver = "selinux"\nsecurity_driver = "apparmor"' ]
  [ ! -s "$GITHUB_ENV" ]
}

@test "restores qemu.conf after setup fails while restarting libvirt" {
  printf 'security_driver = "selinux"\n' >"$LIBVIRT_QEMU_CONF"
  export FAIL_RESTART=true

  run bash "$CONFIGURE_SCRIPT"

  [ "$status" -eq 1 ]
  state_dir=$(state_dir_from_env)
  [ -n "$state_dir" ]
  export FAIL_RESTART=false

  run env LIBVIRT_SECURITY_STATE_DIR="$state_dir" bash "$RESTORE_SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(cat "$LIBVIRT_QEMU_CONF")" = 'security_driver = "selinux"' ]
  [ ! -d "$state_dir" ]
}

@test "restores a libvirt daemon that was inactive before setup" {
  printf 'security_driver = "selinux"\n' >"$LIBVIRT_QEMU_CONF"
  printf 'inactive\n' >"$TEST_LIBVIRT_SERVICE_STATE"

  run bash "$CONFIGURE_SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_LIBVIRT_SERVICE_STATE")" = active ]
  state_dir=$(state_dir_from_env)

  run env LIBVIRT_SECURITY_STATE_DIR="$state_dir" bash "$RESTORE_SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_LIBVIRT_SERVICE_STATE")" = inactive ]
}

@test "preserves a commented security_driver directive" {
  printf '# security_driver = "apparmor"\nlog_level = 2\n' >"$LIBVIRT_QEMU_CONF"

  run bash "$CONFIGURE_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$(cat "$LIBVIRT_QEMU_CONF")" == *'security_driver = "none"'* ]]
  state_dir=$(state_dir_from_env)

  run env LIBVIRT_SECURITY_STATE_DIR="$state_dir" bash "$RESTORE_SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(cat "$LIBVIRT_QEMU_CONF")" = $'# security_driver = "apparmor"\nlog_level = 2' ]
}
