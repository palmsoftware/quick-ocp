#!/bin/bash
set -euo pipefail

IMAGE_LIST="${1:-}"

if [ -z "$IMAGE_LIST" ]; then
  echo "No images to preload"
  exit 0
fi

echo "=== Preloading container images into cluster registry ==="

# Enable the default route on the image registry
echo "Enabling default route on image registry..."
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type merge \
  -p '{"spec":{"defaultRoute":true}}'

# Wait for the route to appear
echo "Waiting for image registry route..."
timeout=120
elapsed=0
while ! oc get route default-route -n openshift-image-registry &>/dev/null; do
  echo "Waiting for image registry route... (${elapsed}s/${timeout}s)"
  sleep 5
  elapsed=$((elapsed + 5))
  if [ $elapsed -ge $timeout ]; then
    echo "ERROR: Timed out waiting for image registry route after ${timeout}s"
    exit 1
  fi
done

# Get the registry hostname
REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
echo "Registry hostname: $REGISTRY"

# Get the kubeadmin token
TOKEN=$(oc whoami -t)

# Use an action-scoped auth file instead of the runner's persistent Docker config.
AUTH_BASE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
umask 077
AUTHFILE=$(mktemp "$AUTH_BASE/quick-ocp-registry-auth.XXXXXX")
chmod 600 "$AUTHFILE"
trap 'rm -f "$AUTHFILE"' EXIT

# Login to the registry without exposing the token in process arguments.
echo "Logging into cluster registry..."
printf '%s\n' "$TOKEN" | podman login "$REGISTRY" \
  --compat-auth-file "$AUTHFILE" \
  --username kubeadmin \
  --password-stdin \
  --tls-verify=false

# Parse and mirror each image
SUCCESS=0
FAILED=0
FAILED_IMAGES=""

while IFS= read -r IMAGE; do
  # Skip empty lines and comments
  IMAGE=$(echo "$IMAGE" | xargs)
  if [ -z "$IMAGE" ] || [[ "$IMAGE" == \#* ]]; then
    continue
  fi

  # Derive the image name for the registry
  # e.g., docker.io/library/nginx:latest -> nginx:latest
  # e.g., quay.io/myorg/myapp:v1 -> myapp:v1
  IMAGE_NAME=$(echo "$IMAGE" | rev | cut -d'/' -f1 | rev)

  echo "--- Mirroring: $IMAGE -> $REGISTRY/openshift/$IMAGE_NAME ---"

  mirror_output=$(oc image mirror \
    "$IMAGE" \
    "$REGISTRY/openshift/$IMAGE_NAME" \
    --registry-config "$AUTHFILE" \
    --insecure=true \
    --keep-manifest-list=true 2>&1) && mirror_rc=0 || mirror_rc=$?

  if [ "$mirror_rc" -eq 0 ]; then
    echo "OK: $IMAGE"
    SUCCESS=$((SUCCESS + 1))
  else
    mirror_error=$(echo "$mirror_output" | grep -i "error" | tail -3)
    echo "FAILED: $IMAGE"
    if [ -n "$mirror_error" ]; then
      echo "$mirror_error"
    fi
    FAILED=$((FAILED + 1))
    FAILED_IMAGES="$FAILED_IMAGES  - $IMAGE\n"
  fi
done <<<"$IMAGE_LIST"

echo ""
echo "=== Image preload summary ==="
echo "Succeeded: $SUCCESS"
echo "Failed: $FAILED"
if [ $FAILED -gt 0 ]; then
  echo "Failed images:"
  echo -e "$FAILED_IMAGES"
  exit 1
fi
echo "=== Image preload complete ==="
