#!/bin/bash
set -e

echo "=== Checking connectivity to required external services ==="

# Retries use exponential backoff (5s, 10s, 20s, ... by default) so a brief
# outage or a rate-limited response does not fail the job.
CONNECTIVITY_RETRIES="${CONNECTIVITY_RETRIES:-5}"
CONNECTIVITY_RETRY_DELAY="${CONNECTIVITY_RETRY_DELAY:-5}"

# Track if any checks fail
CONNECTIVITY_OK=true
FAILED_SERVICES=()

# probe <url> <timeout>: HEAD request, following redirects. On failure, sets
# PROBE_ERROR to the HTTP status or curl error so the log says why.
PROBE_ERROR=""
probe() {
  local url="$1" timeout="$2" http_code rc=0
  http_code=$(curl -sS -L -I -o /dev/null -w '%{http_code}' \
    --connect-timeout "$timeout" --max-time "$timeout" "$url" 2>"$PROBE_ERR_FILE") || rc=$?
  if [ "$rc" -eq 0 ] && [[ "$http_code" =~ ^[23] ]]; then
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    PROBE_ERROR="curl exit $rc: $(tr '\n' ' ' <"$PROBE_ERR_FILE" | sed 's/ *$//')"
  else
    PROBE_ERROR="HTTP $http_code"
  fi
  return 1
}

PROBE_ERR_FILE=$(mktemp)
trap 'rm -f "$PROBE_ERR_FILE"' EXIT

# check_with_retries <url> <timeout>
check_with_retries() {
  local url="$1" timeout="$2"
  local attempt delay="$CONNECTIVITY_RETRY_DELAY"
  for attempt in $(seq 1 "$CONNECTIVITY_RETRIES"); do
    if probe "$url" "$timeout"; then
      echo "✓ OK"
      return 0
    fi
    echo ""
    echo "  attempt $attempt/$CONNECTIVITY_RETRIES failed ($PROBE_ERROR)"
    if [ "$attempt" -lt "$CONNECTIVITY_RETRIES" ]; then
      echo -n "  retrying in ${delay}s... "
      sleep "$delay"
      delay=$((delay * 2))
    fi
  done
  return 1
}

# Function to check connectivity to a required service
check_service() {
  local service_name="$1"
  local url="$2"
  local timeout="${3:-10}"

  echo -n "Checking $service_name... "
  if check_with_retries "$url" "$timeout"; then
    return 0
  fi
  echo "✗ FAILED"
  CONNECTIVITY_OK=false
  FAILED_SERVICES+=("$service_name ($url): $PROBE_ERROR")
}

# Non-fatal connectivity check (warns but does not fail the script)
check_optional_service() {
  local service_name="$1"
  local url="$2"
  local timeout="${3:-10}"

  echo -n "Checking $service_name (optional)... "
  if check_with_retries "$url" "$timeout"; then
    return 0
  fi
  echo "✗ FAILED (non-fatal, continuing)"
  echo "::warning::$service_name is unreachable ($PROBE_ERROR); continuing"
}

# Check OpenShift Mirror (primary dependency for CRC download)
check_service "OpenShift Mirror" "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/release.txt" 15

# Check GitHub API (used for CRC version detection — non-fatal since version
# detection has its own fallback logic)
check_optional_service "GitHub API" "https://api.github.com" 10

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
    echo "::error::Cannot reach $service"
  done
  echo ""
  echo "This action requires internet access to external services."
  echo "Please check your network connection and try again."
  echo ""
  echo "Common causes:"
  echo "  - Network connectivity issues"
  echo "  - Firewall blocking access to required endpoints"
  echo "  - Service temporarily unavailable"
  echo "  - DNS resolution problems"
  echo ""
  exit 1
fi
