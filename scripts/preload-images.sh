#!/bin/bash
set -e

IMAGE_LIST="$1"

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

# Login to the registry with podman
echo "Logging into cluster registry..."
podman login "$REGISTRY" \
  --username kubeadmin \
  --password "$TOKEN" \
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

  if oc image mirror \
    "$IMAGE" \
    "$REGISTRY/openshift/$IMAGE_NAME" \
    --insecure=true \
    --keep-manifest-list=true 2>&1; then
    echo "OK: $IMAGE"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "FAILED: $IMAGE"
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
