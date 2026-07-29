#!/bin/bash
set -e

# When CRC start retries after a first-attempt failure, it may short-circuit
# and skip updating /etc/hosts. This leaves the cluster unreachable because
# api.crc.testing does not resolve. Add the entries as a fallback.

CRC_HOSTS="api.crc.testing host.crc.testing oauth-openshift.apps-crc.testing console-openshift-console.apps-crc.testing downloads-openshift-console.apps-crc.testing canary-openshift-ingress-canary.apps-crc.testing default-route-openshift-image-registry.apps-crc.testing"

if getent hosts api.crc.testing &>/dev/null; then
  echo "=== CRC DNS entries already present ==="
  exit 0
fi

echo "=== CRC DNS entries missing from /etc/hosts, adding fallback ==="
echo "127.0.0.1 ${CRC_HOSTS}" | sudo tee -a /etc/hosts
echo "=== Verifying DNS resolution ==="
getent hosts api.crc.testing
