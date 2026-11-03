#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/ensure-kubeconfig.sh"

setup() {
  TEST_ROOT=$(mktemp -d)
  export TEST_ROOT
  mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/state/contexts" "$TEST_ROOT/crc"
  export STATE="$TEST_ROOT/state"
  export CRC_MACHINE_DIR="$TEST_ROOT/crc"
  export ENSURE_KUBECONFIG_INTERVAL=0
  export ENSURE_KUBECONFIG_TIMEOUT=60
  printf 'kubeadmin-secret' >"$CRC_MACHINE_DIR/kubeadmin-password"
  printf 'admin kubeconfig' >"$CRC_MACHINE_DIR/kubeconfig"
  printf '0\n' >"$STATE/login-count"
  touch "$STATE/logins" "$STATE/embedded"

  # Fake oc: contexts are files in $STATE/contexts, the current context is
  # $STATE/current. MOCK_LOGIN_FAIL_N makes the first N logins fail;
  # MOCK_DEVELOPER_FAIL makes developer logins always fail.
  cat >"$TEST_ROOT/bin/oc" <<'EOF'
#!/usr/bin/env bash
current() { cat "$STATE/current" 2>/dev/null; }
# Context names contain "/", so encode them as flat file names.
cf() { echo "$STATE/contexts/${1//\//%}"; }
args=("$@")
if [[ "${args[0]}" == --context ]]; then
  ctx=${args[1]}
  [[ -f "$(cf "$ctx")" ]] || { echo "error: context \"$ctx\" does not exist" >&2; exit 1; }
  [[ "$(cat "$(cf "$ctx")")" == broken ]] && { echo "error: Unauthorized" >&2; exit 1; }
  [[ "$*" == *whoami* ]] && cat "$(cf "$ctx")"
  exit 0
fi
case "$1 $2" in
  "config view")
    if [[ "$*" == *certificate-authority-data* ]]; then
      [[ -f "${KUBECONFIG:-/nonexistent}" ]] || exit 1
      printf 'FAKE-CA' | base64
    else
      echo "api-crc-testing:6443"
    fi
    ;;
  "config current-context") current ;;
  "config set-cluster")
    ca=""
    for a in "$@"; do [[ "$a" == --certificate-authority=* ]] && ca=${a#*=}; done
    echo "$3 $(tr '\n' '+' <"$ca")" >>"$STATE/embedded"
    ;;
  "config delete-context") rm -f "$(cf "$3")" ;;
  "config rename-context")
    mv "$(cf "$3")" "$(cf "$4")"
    [[ "$(current)" == "$3" ]] && printf '%s' "$4" >"$STATE/current"
    ;;
  "config use-context") printf '%s' "$3" >"$STATE/current" ;;
  "login "*)
    user="" password="" ca=""
    while (($#)); do
      case "$1" in
        -u) user=$2; shift ;;
        -p) password=$2; shift ;;
        --certificate-authority=*) ca=${1#*=} ;;
      esac
      shift
    done
    count=$(($(cat "$STATE/login-count") + 1))
    printf '%s\n' "$count" >"$STATE/login-count"
    if ((count <= ${MOCK_LOGIN_FAIL_N:-0})) ||
      { [[ "$user" == developer ]] && [[ -n "${MOCK_DEVELOPER_FAIL:-}" ]]; }; then
      echo "error: EOF from oauth-openshift.apps-crc.testing" >&2
      exit 1
    fi
    echo "$user $password $(tr '\n' '+' <"$ca")" >>"$STATE/logins"
    ctx="default/api-crc-testing:6443/$user"
    if [[ "$user" == kubeadmin ]]; then echo "kube:admin"; else echo "$user"; fi >"$(cf "$ctx")"
    printf '%s' "$ctx" >"$STATE/current"
    ;;
  "whoami "*) cat "$(cf "$(current)")" ;;
  "get configmap")
    [[ -f "${KUBECONFIG:-/nonexistent}" ]] && [[ -z "${MOCK_NO_INGRESS_CA:-}" ]] || exit 1
    printf 'INGRESS-CA'
    ;;
  "get "*) echo "fake oc $*" ;;
  *) exit 1 ;;
esac
EOF

  cat >"$TEST_ROOT/bin/crc" <<'EOF'
#!/usr/bin/env bash
echo '{"clusterConfig":{"adminCredentials":{"password":"from-crc-console"},"developerCredentials":{"password":"dev-pass"}}}'
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

@test "does nothing when the crc-admin context already works" {
  echo "kube:admin" >"$STATE/contexts/crc-admin"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to recover"* ]]
  [ "$(cat "$STATE/login-count")" -eq 0 ]
}

@test "recreates crc-admin and crc-developer when crc start left no context" {
  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::kubeconfig context crc-admin is missing"* ]]
  [[ "$output" == *"::add-mask::kubeadmin-secret"* ]]
  [ -f "$STATE/contexts/crc-admin" ]
  [ -f "$STATE/contexts/crc-developer" ]
  [ "$(cat "$STATE/current")" = crc-admin ]
  grep -qx "kubeadmin kubeadmin-secret FAKE-CA+INGRESS-CA+" "$STATE/logins"
  grep -qx "developer dev-pass FAKE-CA+INGRESS-CA+" "$STATE/logins"
  grep -qx "api-crc-testing:6443 FAKE-CA+INGRESS-CA+" "$STATE/embedded"
  [[ "$output" == *"current context crc-admin (kube:admin)"* ]]
}

@test "replaces a stale crc-admin context that no longer works" {
  # Present but rejected by the API server (e.g. an expired token).
  echo "broken" >"$STATE/contexts/crc-admin"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(cat "$STATE/contexts/crc-admin")" = "kube:admin" ]
}

@test "retries the kubeadmin login until the OAuth route is ready" {
  export MOCK_LOGIN_FAIL_N=3

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(grep -c 'kubeadmin login not ready yet' <<<"$output")" -eq 3 ]
  [[ "$output" == *"EOF from oauth-openshift"* ]]
  [ -f "$STATE/contexts/crc-admin" ]
}

@test "fails with diagnostics when the OAuth route never becomes ready" {
  export MOCK_LOGIN_FAIL_N=999
  export ENSURE_KUBECONFIG_TIMEOUT=0

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not log in as kubeadmin after 0s"* ]]
  [[ "$output" == *"Last oc login error: error: EOF from oauth-openshift"* ]]
  [[ "$output" == *"Cluster state via crc's admin kubeconfig"* ]]
  [[ "$output" == *"fake oc get nodes"* ]]
}

@test "falls back to crc console for the kubeadmin password" {
  rm "$CRC_MACHINE_DIR/kubeadmin-password"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qx "kubeadmin from-crc-console FAKE-CA+INGRESS-CA+" "$STATE/logins"
}

@test "fails clearly when no kubeadmin password is available" {
  rm "$CRC_MACHINE_DIR/kubeadmin-password"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$TEST_ROOT/bin/crc"

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"no kubeadmin password"* ]]
  [ "$(cat "$STATE/login-count")" -eq 0 ]
}

@test "fails clearly when the admin kubeconfig has no cluster CA" {
  rm "$CRC_MACHINE_DIR/kubeconfig"

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"no cluster CA"* ]]
  [ "$(cat "$STATE/login-count")" -eq 0 ]
}

@test "keeps going when only the developer login fails" {
  export MOCK_DEVELOPER_FAIL=1

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Could not recreate context crc-developer"* ]]
  [ -f "$STATE/contexts/crc-admin" ]
  [ ! -f "$STATE/contexts/crc-developer" ]
  [ "$(cat "$STATE/current")" = crc-admin ]
}


@test "uses the API CA alone while the ingress CA is not readable yet" {
  export MOCK_NO_INGRESS_CA=1

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qx "kubeadmin kubeadmin-secret FAKE-CA+" "$STATE/logins"
}
