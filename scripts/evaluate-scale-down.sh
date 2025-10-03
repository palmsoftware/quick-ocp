#!/usr/bin/env bash

set -u

echo "=== Evaluation: What would be scaled down (no changes made) ==="

print_deploy_status() {
  local namespace="$1"
  local name="$2"

  if oc get deployment.apps/"$name" -n "$namespace" &>/dev/null; then
    local replicas
    local ready
    replicas=$(oc get deployment.apps/"$name" -n "$namespace" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
    ready=$(oc get deployment.apps/"$name" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    echo "- Would scale deployment.apps/${name} in ${namespace} to 0 (current: replicas=${replicas}, ready=${ready})"
  else
    echo "- Not found: deployment.apps/${name} in ${namespace}"
  fi
}

# Console components
print_deploy_status "openshift-console" "console"
print_deploy_status "openshift-console" "downloads"

# Console operator in possible namespaces
if oc get deployment.apps/console-operator -n openshift-console &>/dev/null; then
  print_deploy_status "openshift-console" "console-operator"
elif oc get deployment.apps/console-operator -n openshift-console-operator &>/dev/null; then
  print_deploy_status "openshift-console-operator" "console-operator"
else
  echo "- Not found: deployment.apps/console-operator in openshift-console or openshift-console-operator"
fi

echo "=== End evaluation ==="
