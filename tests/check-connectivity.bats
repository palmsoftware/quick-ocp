#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/check-connectivity.sh"

setup() {
  TEST_ROOT=$(mktemp -d)
  export TEST_ROOT
  mkdir -p "$TEST_ROOT/bin"
  export CONNECTIVITY_RETRY_DELAY=5

  # Fake curl. MOCK_MIRROR / MOCK_GITHUB is a space-separated list of
  # per-attempt results: "ok", "http:<code>" or "fail:<exit code>". The last
  # entry repeats once the list runs out.
  cat >"$TEST_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env bash
url="${*: -1}"
case "$url" in
  *mirror.openshift.com*) key=mirror; results="${MOCK_MIRROR:-ok}" ;;
  *api.github.com*) key=github; results="${MOCK_GITHUB:-ok}" ;;
  *) exit 6 ;;
esac
count_file="$TEST_ROOT/$key.count"
n=$(($(cat "$count_file" 2>/dev/null || echo 0) + 1))
echo "$n" >"$count_file"
read -ra list <<<"$results"
idx=$((n - 1))
((idx >= ${#list[@]})) && idx=$((${#list[@]} - 1))
case "${list[$idx]}" in
  ok) printf '200' ;;
  http:*) printf '%s' "${list[$idx]#http:}" ;;
  fail:*)
    printf '000'
    echo "curl: (${list[$idx]#fail:}) Could not resolve host" >&2
    exit "${list[$idx]#fail:}"
    ;;
esac
EOF

  cat >"$TEST_ROOT/bin/sleep" <<'EOF'
#!/usr/bin/env bash
echo "$1" >>"$TEST_ROOT/sleeps"
EOF

  chmod +x "$TEST_ROOT/bin/"*
  export PATH="$TEST_ROOT/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "passes when every service answers" {
  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Checking OpenShift Mirror... ✓ OK"* ]]
  [[ "$output" == *"All required services are accessible"* ]]
  [ ! -f "$TEST_ROOT/sleeps" ]
}

@test "rides out a brief mirror outage with exponential backoff" {
  export MOCK_MIRROR="http:503 fail:6 http:503 ok"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"attempt 1/5 failed (HTTP 503)"* ]]
  [[ "$output" == *"attempt 2/5 failed (curl exit 6: curl: (6) Could not resolve host)"* ]]
  [ "$(cat "$TEST_ROOT/mirror.count")" -eq 4 ]
  [ "$(tr '\n' ' ' <"$TEST_ROOT/sleeps")" = "5 10 20 " ]
}

@test "fails with the reason and prints the summary when the mirror stays down" {
  export MOCK_MIRROR="http:503"

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  [ "$(cat "$TEST_ROOT/mirror.count")" -eq 5 ]
  [[ "$output" == *"Checking OpenShift Mirror..."*"✗ FAILED"* ]]
  [[ "$output" == *"=== Connectivity Check Summary ==="* ]]
  [[ "$output" == *"::error::Cannot reach OpenShift Mirror (https://mirror.openshift.com/"*"): HTTP 503"* ]]
  # The GitHub API check still runs after the mirror fails.
  [ "$(cat "$TEST_ROOT/github.count")" -eq 1 ]
}

@test "treats a 4xx response as a failure" {
  export MOCK_MIRROR="http:403"
  export CONNECTIVITY_RETRIES=2

  run bash "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"attempt 2/2 failed (HTTP 403)"* ]]
}

@test "GitHub API failure is only a warning" {
  export MOCK_GITHUB="fail:28"
  export CONNECTIVITY_RETRIES=2

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"FAILED (non-fatal, continuing)"* ]]
  [[ "$output" == *"::warning::GitHub API is unreachable (curl exit 28"* ]]
  [[ "$output" == *"All required services are accessible"* ]]
}
