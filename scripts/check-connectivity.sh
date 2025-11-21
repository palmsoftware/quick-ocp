#!/bin/bash
set -e

echo "=== Checking connectivity to required external services ==="

# Track if any checks fail
CONNECTIVITY_OK=true
FAILED_SERVICES=()

# Function to check connectivity to a service
check_service() {
  local service_name="$1"
  local url="$2"
  local timeout="${3:-10}"

  echo -n "Checking $service_name... "

  # Use curl with timeout and follow redirects
  # -s: silent, -f: fail on HTTP errors, -L: follow redirects, -I: HEAD request only
  # --max-time: maximum time for the operation
  # --connect-timeout: maximum time for connection
  if curl -s -f -L -I --connect-timeout "$timeout" --max-time "$timeout" "$url" >/dev/null 2>&1; then
    echo "✓ OK"
    return 0
  else
    echo "✗ FAILED"
    CONNECTIVITY_OK=false
    FAILED_SERVICES+=("$service_name")
    return 1
  fi
}

# Check OpenShift Mirror (primary dependency)
# Test with a known stable endpoint
check_service "OpenShift Mirror" "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/release.txt" 15

echo ""
echo "=== Connectivity Check Summary ==="

if [ "$CONNECTIVITY_OK" = true ]; then
  echo "✓ All required services are accessible"
  echo ""
  exit 0
else
  echo "✗ Connectivity check FAILED"
  echo ""
  echo "The following services could not be reached:"
  for service in "${FAILED_SERVICES[@]}"; do
    echo "  - $service"
  done
  echo ""
  echo "This action requires internet access to the OpenShift mirrors."
  echo "Please check your network connection and try again."
  echo ""
  echo "Common causes:"
  echo "  - Network connectivity issues"
  echo "  - Firewall blocking access to mirror.openshift.com"
  echo "  - OpenShift Mirror temporarily unavailable"
  echo "  - DNS resolution problems"
  echo ""
  exit 1
fi
