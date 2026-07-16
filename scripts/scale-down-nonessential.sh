#!/bin/bash
set -e

echo "=== Disabling non-essential OpenShift operators ==="

max_retries=5
retry_delay=10
for attempt in $(seq 1 $max_retries); do
  EXISTING_OVERRIDES=$(oc get clusterversion/version -ojsonpath='{range .spec.overrides[*]}{.name}{"\n"}{end}' 2>&1) && break
  echo "WARNING: Failed to query ClusterVersion (attempt $attempt/$max_retries), retrying in ${retry_delay}s..."
  sleep "$retry_delay"
  if [ "$attempt" -eq "$max_retries" ]; then
    echo "ERROR: Could not reach ClusterVersion API after $max_retries attempts"
    echo "$EXISTING_OVERRIDES"
    exit 1
  fi
done

PATCH="["
NEED_COMMA=false

add_override() {
  local kind="$1" name="$2" namespace="$3" group="$4"
  if echo "$EXISTING_OVERRIDES" | grep -qx "$name"; then
    echo "Override for $name already exists, skipping"
    return
  fi
  if $NEED_COMMA; then
    PATCH+=","
  fi
  PATCH+="{\"op\":\"add\",\"path\":\"/spec/overrides/-\",\"value\":{\"kind\":\"$kind\",\"name\":\"$name\",\"namespace\":\"$namespace\",\"unmanaged\":true,\"group\":\"$group\"}}"
  NEED_COMMA=true
}

# Console operator
add_override "Deployment" "console-operator" "openshift-console-operator" "apps"
add_override "ClusterOperator" "console" "" "config.openshift.io"

# Cluster samples operator
add_override "Deployment" "cluster-samples-operator" "openshift-cluster-samples-operator" "apps"
add_override "ClusterOperator" "samples" "" "config.openshift.io"

# Kube storage version migrator
add_override "Deployment" "kube-storage-version-migrator-operator" "openshift-kube-storage-version-migrator-operator" "apps"
add_override "ClusterOperator" "kube-storage-version-migrator" "" "config.openshift.io"

PATCH+="]"

if [ "$PATCH" != "[]" ]; then
  echo "Applying ClusterVersion overrides..."
  oc patch clusterversion/version --type json -p "$PATCH" 2>&1
else
  echo "All overrides already in place"
fi

# Scale down deployments
scale_down() {
  local name="$1" namespace="$2"
  if oc get deployment.apps/"$name" -n "$namespace" &>/dev/null; then
    oc scale --replicas=0 deployment.apps/"$name" -n "$namespace" 2>&1 | grep -v "node-role.kubernetes.io/master" || true
    echo "Scaled down $name in $namespace"
  else
    echo "$name not found in $namespace, skipping"
  fi
}

# Console
scale_down "console-operator" "openshift-console-operator"
scale_down "console" "openshift-console"
scale_down "downloads" "openshift-console"

# Cluster samples operator
scale_down "cluster-samples-operator" "openshift-cluster-samples-operator"

# Kube storage version migrator
scale_down "kube-storage-version-migrator-operator" "openshift-kube-storage-version-migrator-operator"
scale_down "migrator" "openshift-kube-storage-version-migrator"

echo "=== Non-essential operators disabled ==="
