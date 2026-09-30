#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/install-telco-operators.sh"
TLS_COMPLIANCE_OPERATOR_URL="https://github.com/sebrandon1/tls-compliance-operator/releases/latest/download/install.yaml"
IMAGE_CERT_INFO_OPERATOR_URL="https://github.com/sebrandon1/imagecertinfo-operator/releases/latest/download/install.yaml"

setup() {
  TEST_ROOT=$(mktemp -d)
  export OC_CALL_LOG="$TEST_ROOT/oc-calls"
  export INSTALL_TLS_COMPLIANCE_OPERATOR=false
  export INSTALL_IMAGE_CERT_INFO_OPERATOR=false
  export PATH="$TEST_ROOT/bin:$PATH"

  mkdir -p "$TEST_ROOT/bin"
  cat >"$TEST_ROOT/bin/oc" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$OC_CALL_LOG"
exit "${MOCK_OC_EXIT_CODE:-0}"
EOF
  chmod +x "$TEST_ROOT/bin/oc"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "installs only the TLS Compliance Operator when selected" {
  export INSTALL_TLS_COMPLIANCE_OPERATOR=true

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -Fq "apply -f $TLS_COMPLIANCE_OPERATOR_URL" "$OC_CALL_LOG"
  ! grep -Fq "$IMAGE_CERT_INFO_OPERATOR_URL" "$OC_CALL_LOG"
}

@test "installs only the Image Cert Info Operator when selected" {
  export INSTALL_IMAGE_CERT_INFO_OPERATOR=true

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -Fq "apply -f $IMAGE_CERT_INFO_OPERATOR_URL" "$OC_CALL_LOG"
  ! grep -Fq "$TLS_COMPLIANCE_OPERATOR_URL" "$OC_CALL_LOG"
}

@test "installs both operators when both are selected" {
  export INSTALL_TLS_COMPLIANCE_OPERATOR=true
  export INSTALL_IMAGE_CERT_INFO_OPERATOR=true

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(wc -l <"$OC_CALL_LOG")" -eq 2 ]
  grep -Fq "apply -f $TLS_COMPLIANCE_OPERATOR_URL" "$OC_CALL_LOG"
  grep -Fq "apply -f $IMAGE_CERT_INFO_OPERATOR_URL" "$OC_CALL_LOG"
}

@test "does not install operators when neither is selected" {
  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ ! -s "$OC_CALL_LOG" ]
}

@test "fails when oc apply fails for a selected operator" {
  export MOCK_OC_EXIT_CODE=1

  for variable in INSTALL_TLS_COMPLIANCE_OPERATOR INSTALL_IMAGE_CERT_INFO_OPERATOR; do
    export "$variable=true"
    run bash "$SCRIPT"

    [ "$status" -eq 1 ]
    if [[ "$variable" == INSTALL_TLS_COMPLIANCE_OPERATOR ]]; then
      grep -Fq "apply -f $TLS_COMPLIANCE_OPERATOR_URL" "$OC_CALL_LOG"
    else
      grep -Fq "apply -f $IMAGE_CERT_INFO_OPERATOR_URL" "$OC_CALL_LOG"
    fi

    export "$variable=false"
  done
}
