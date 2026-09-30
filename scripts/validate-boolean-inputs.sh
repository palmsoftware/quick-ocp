#!/bin/bash
set -euo pipefail

validate_boolean() {
  local name="$1"
  local value="$2"

  case "$value" in
    true | false) ;;
    *)
      echo "::error::Invalid value for input '$name': expected lowercase 'true' or 'false'." >&2
      exit 1
      ;;
  esac
}

validate_boolean bundleCache "${BUNDLE_CACHE-}"
validate_boolean waitForOperatorsReady "${WAIT_FOR_OPERATORS_READY-}"
validate_boolean enableTelemetry "${ENABLE_TELEMETRY-}"
validate_boolean disableConnectivityCheck "${DISABLE_CONNECTIVITY_CHECK-}"
validate_boolean disableResourcePrecheck "${DISABLE_RESOURCE_PRECHECK-}"
validate_boolean enableClusterMonitoring "${ENABLE_CLUSTER_MONITORING-}"
