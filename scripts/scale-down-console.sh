#!/bin/bash
set -e

echo "=== Scaling down non-essential OpenShift components ==="

# Scale down console deployments if they exist
if oc get deployment.apps/console -n openshift-console &>/dev/null; then
  oc scale --replicas=0 deployment.apps/console -n openshift-console 2>&1 | grep -v "node-role.kubernetes.io/master" || true
  echo "Scaled down console deployment"
else
  echo "console deployment not found in openshift-console namespace"
fi

if oc get deployment.apps/downloads -n openshift-console &>/dev/null; then
  oc scale --replicas=0 deployment.apps/downloads -n openshift-console 2>&1 | grep -v "node-role.kubernetes.io/master" || true
  echo "Scaled down downloads deployment"
else
  echo "downloads deployment not found in openshift-console namespace"
fi

# Check for console-operator in multiple possible namespaces
if oc get deployment.apps/console-operator -n openshift-console &>/dev/null; then
  oc scale --replicas=0 deployment.apps/console-operator -n openshift-console 2>&1 | grep -v "node-role.kubernetes.io/master" || true
  echo "Scaled down console-operator in openshift-console"
elif oc get deployment.apps/console-operator -n openshift-console-operator &>/dev/null; then
  oc scale --replicas=0 deployment.apps/console-operator -n openshift-console-operator 2>&1 | grep -v "node-role.kubernetes.io/master" || true
  echo "Scaled down console-operator in openshift-console-operator"
else
  echo "console-operator deployment not found in openshift-console or openshift-console-operator namespaces"
fi

echo "=== Resource scaling completed ==="
