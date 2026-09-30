#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/validate-boolean-inputs.sh"
INPUTS=(
  bundleCache:BUNDLE_CACHE
  waitForOperatorsReady:WAIT_FOR_OPERATORS_READY
  enableTelemetry:ENABLE_TELEMETRY
  disableConnectivityCheck:DISABLE_CONNECTIVITY_CHECK
  disableResourcePrecheck:DISABLE_RESOURCE_PRECHECK
  enableClusterMonitoring:ENABLE_CLUSTER_MONITORING
  installTLSComplianceOperator:INSTALL_TLS_COMPLIANCE_OPERATOR
  installImageCertInfoOperator:INSTALL_IMAGE_CERT_INFO_OPERATOR
)

check_input() {
  local variable="$1"
  local value="$2"

  run env \
    BUNDLE_CACHE=false \
    WAIT_FOR_OPERATORS_READY=false \
    ENABLE_TELEMETRY=true \
    DISABLE_CONNECTIVITY_CHECK=false \
    DISABLE_RESOURCE_PRECHECK=false \
    ENABLE_CLUSTER_MONITORING=false \
    INSTALL_TLS_COMPLIANCE_OPERATOR=false \
    INSTALL_IMAGE_CERT_INFO_OPERATOR=false \
    "$variable=$value" \
    bash "$SCRIPT"
}

@test "accepts lowercase true and false for every boolean input" {
  for input in "${INPUTS[@]}"; do
    variable="${input#*:}"
    for value in true false; do
      check_input "$variable" "$value"
      [ "$status" -eq 0 ]
    done
  done
}

@test "rejects uppercase, empty, and misspelled values for every boolean input" {
  for input in "${INPUTS[@]}"; do
    name="${input%%:*}"
    variable="${input#*:}"
    for value in TRUE '' flase; do
      check_input "$variable" "$value"
      [ "$status" -eq 1 ]
      [[ "$output" == *"::error::Invalid value for input '$name'"* ]]
    done
  done
}
