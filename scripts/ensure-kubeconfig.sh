#!/bin/bash
set -eo pipefail

# `crc start` adds the crc-admin and crc-developer contexts to ~/.kube/config
# by logging in through the cluster's OAuth route. When that route is not
# ready yet, crc logs "Cannot update kubeconfig: ..." and still exits 0, so
# the cluster is up but ~/.kube/config has no working context and every later
# `oc` call fails. Recreate the contexts the same way crc does: OAuth token
# logins as kubeadmin and developer. The OAuth route only needs time, so
# logins are retried.

API_URL="${CRC_API_URL:-https://api.crc.testing:6443}"
CRC_MACHINE_DIR="${CRC_MACHINE_DIR:-$HOME/.crc/machines/crc}"
ADMIN_KUBECONFIG="${CRC_MACHINE_DIR}/kubeconfig"
TIMEOUT="${ENSURE_KUBECONFIG_TIMEOUT:-600}"
INTERVAL="${ENSURE_KUBECONFIG_INTERVAL:-15}"

if oc --context crc-admin --request-timeout=30s whoami >/dev/null 2>&1; then
  echo "kubeconfig context crc-admin works; nothing to recover"
  exit 0
fi

echo "::warning::kubeconfig context crc-admin is missing or not working (crc start can log 'Cannot update kubeconfig' and still succeed); recreating crc-admin and crc-developer"

CREDENTIALS_JSON=""
credentials_json() {
  if [ -z "$CREDENTIALS_JSON" ]; then
    CREDENTIALS_JSON=$(crc console --credentials -o json 2>/dev/null || echo '{}')
  fi
  echo "$CREDENTIALS_JSON"
}

KUBEADMIN_PASSWORD=""
if [ -s "${CRC_MACHINE_DIR}/kubeadmin-password" ]; then
  KUBEADMIN_PASSWORD=$(cat "${CRC_MACHINE_DIR}/kubeadmin-password")
else
  KUBEADMIN_PASSWORD=$(credentials_json | jq -r '.clusterConfig.adminCredentials.password // empty' 2>/dev/null || true)
fi
if [ -z "$KUBEADMIN_PASSWORD" ]; then
  echo "::error::Cannot recreate kubeconfig: no kubeadmin password in ${CRC_MACHINE_DIR}/kubeadmin-password or 'crc console --credentials'"
  exit 1
fi
echo "::add-mask::$KUBEADMIN_PASSWORD"
DEVELOPER_PASSWORD=$(credentials_json | jq -r '.clusterConfig.developerCredentials.password // empty' 2>/dev/null || true)
DEVELOPER_PASSWORD="${DEVELOPER_PASSWORD:-developer}"

# oc login talks to both the API server and the OAuth route, which the
# ingress router serves with a certificate from the ingress CA. Trust the API
# CA from crc's admin kubeconfig plus the router CA, read through that same
# certificate-based kubeconfig (it does not depend on OAuth).
API_CA=$(KUBECONFIG="$ADMIN_KUBECONFIG" oc config view --raw \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null |
  base64 -d 2>/dev/null) || true
if [ -z "$API_CA" ]; then
  echo "::error::Cannot recreate kubeconfig: no cluster CA in ${ADMIN_KUBECONFIG}"
  exit 1
fi
CA_FILE=$(mktemp)
trap 'rm -f "$CA_FILE"' EXIT
INGRESS_CA_ADDED=false
refresh_ca_bundle() {
  local ingress_ca
  [ "$INGRESS_CA_ADDED" = true ] && return 0
  printf '%s\n' "$API_CA" >"$CA_FILE"
  ingress_ca=$(KUBECONFIG="$ADMIN_KUBECONFIG" oc get configmap default-ingress-cert \
    -n openshift-config-managed --request-timeout=30s \
    -o jsonpath='{.data.ca-bundle\.crt}' 2>/dev/null) || true
  if [ -n "$ingress_ca" ]; then
    printf '%s\n' "$ingress_ca" >>"$CA_FILE"
    INGRESS_CA_ADDED=true
  fi
}

LAST_ERROR=""
# login_as <user> <password> <context>: OAuth login, then give the context
# crc's name and embed the CA so the kubeconfig does not reference $CA_FILE.
login_as() {
  local user="$1" password="$2" context="$3" cluster
  refresh_ca_bundle
  if ! LAST_ERROR=$(oc login "$API_URL" -u "$user" -p "$password" \
    --certificate-authority="$CA_FILE" --request-timeout=30s 2>&1); then
    return 1
  fi
  cluster=$(oc config view --minify -o jsonpath='{.clusters[0].name}')
  oc config set-cluster "$cluster" --certificate-authority="$CA_FILE" --embed-certs=true >/dev/null
  oc config delete-context "$context" >/dev/null 2>&1 || true
  oc config rename-context "$(oc config current-context)" "$context" >/dev/null
}

deadline=$((SECONDS + TIMEOUT))
until login_as kubeadmin "$KUBEADMIN_PASSWORD" crc-admin; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "::error::Could not log in as kubeadmin after ${TIMEOUT}s; the OAuth route never became ready"
    echo "Last oc login error: ${LAST_ERROR}"
    echo ""
    echo "=== Cluster state via crc's admin kubeconfig ==="
    KUBECONFIG="$ADMIN_KUBECONFIG" oc get nodes --request-timeout=30s 2>&1 || true
    KUBECONFIG="$ADMIN_KUBECONFIG" oc get clusteroperators authentication ingress --request-timeout=30s 2>&1 || true
    exit 1
  fi
  echo "kubeadmin login not ready yet, retrying in ${INTERVAL}s: ${LAST_ERROR##*$'\n'}"
  sleep "$INTERVAL"
done
echo "Recreated context crc-admin"

# crc-developer is a convenience context; failing to recreate it is non-fatal.
if login_as developer "$DEVELOPER_PASSWORD" crc-developer; then
  echo "Recreated context crc-developer"
else
  echo "::warning::Could not recreate context crc-developer: ${LAST_ERROR##*$'\n'}"
fi

oc config use-context crc-admin >/dev/null
echo "kubeconfig recovered; current context crc-admin ($(oc whoami))"
