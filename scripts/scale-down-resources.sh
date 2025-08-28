#!/usr/bin/env bash

echo "=== Scaling down non-essential OpenShift components ==="

# Helper: ensure overrides array exists to avoid JSON patch errors
ensure_overrides_array() {
  local current
  current=$(oc get clusterversion version -o jsonpath='{.spec.overrides}' 2>/dev/null || echo "")
  if [ -z "$current" ] || [ "$current" = "<no value>" ]; then
    oc patch clusterversion version --type=merge -p '{"spec":{"overrides":[]}}' >/dev/null 2>&1 || true
  fi
}

# Helper: add a CVO override if missing (idempotent)
add_cvo_override() {
  local kind="$1" group="$2" namespace="$3" name="$4"
  local present
  present=$(oc get clusterversion version -o jsonpath="{range .spec.overrides[?(@.kind=='$kind' && @.group=='$group' && @.namespace=='$namespace' && @.name=='$name')]}{.unmanaged}{end}" 2>/dev/null || echo "")
  if [ "$present" != "true" ]; then
    ensure_overrides_array
    oc patch clusterversion version --type=json -p "[{\"op\":\"add\",\"path\":\"/spec/overrides/-\",\"value\":{\"kind\":\"$kind\",\"group\":\"$group\",\"namespace\":\"$namespace\",\"name\":\"$name\",\"unmanaged\":true}}]" >/dev/null 2>&1 || true
    echo "Added CVO override unmanaged=true for $kind/$name in $namespace ($group)"
  else
    echo "CVO override already present for $kind/$name in $namespace ($group)"
  fi
}

# Ensure the Console operator does not reconcile the console back up
if oc get consoles.operator.openshift.io/cluster &>/dev/null; then
  current_state=$(oc get consoles.operator.openshift.io/cluster -o jsonpath='{.spec.managementState}' 2>/dev/null || echo "")
  if [ "$current_state" != "Removed" ]; then
    oc patch consoles.operator.openshift.io/cluster --type=merge -p '{"spec":{"managementState":"Removed"}}' || true
    echo "Patched consoles.operator.openshift.io/cluster to managementState=Removed"
  else
    echo "Console operator already set to managementState=Removed"
  fi
else
  echo "consoles.operator.openshift.io/cluster not found; skipping operator patch"
fi

# Ensure the Samples operator does not reconcile sample imagestreams/templates
if oc get configs.samples.operator.openshift.io/cluster &>/dev/null; then
  samples_state=$(oc get configs.samples.operator.openshift.io/cluster -o jsonpath='{.spec.managementState}' 2>/dev/null || echo "")
  if [ "$samples_state" != "Removed" ]; then
    oc patch configs.samples.operator.openshift.io/cluster --type=merge -p '{"spec":{"managementState":"Removed"}}' || true
    echo "Patched configs.samples.operator.openshift.io/cluster to managementState=Removed"
  else
    echo "Samples operator already set to managementState=Removed"
  fi
else
  echo "configs.samples.operator.openshift.io/cluster not found; skipping samples operator patch"
fi

# Ensure the internal Image Registry is fully disabled and stays down
if oc get configs.imageregistry.operator.openshift.io/cluster &>/dev/null; then
  registry_state=$(oc get configs.imageregistry.operator.openshift.io/cluster -o jsonpath='{.spec.managementState}' 2>/dev/null || echo "")
  if [ "$registry_state" != "Removed" ]; then
    oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge -p '{"spec":{"managementState":"Removed"}}' || true
    echo "Patched configs.imageregistry.operator.openshift.io/cluster to managementState=Removed"
  else
    echo "Image Registry operator already set to managementState=Removed"
  fi
else
  echo "configs.imageregistry.operator.openshift.io/cluster not found; skipping image registry patch"
fi

# Disable default catalog sources to avoid marketplace registry pods
if oc get operatorhubs.config.openshift.io/cluster &>/dev/null; then
  oc patch operatorhubs.config.openshift.io/cluster --type=merge -p '{"spec":{"disableAllDefaultSources":true}}' || true
  echo "Patched operatorhubs.config.openshift.io/cluster to disableAllDefaultSources=true"
  # Best-effort cleanup of default catalog sources if they exist
  oc delete catalogsource/redhat-operators catalogsource/community-operators catalogsource/certified-operators -n openshift-marketplace --ignore-not-found=true || true
else
  echo "operatorhubs.config.openshift.io/cluster not found; skipping OperatorHub patch"
fi

# Scale down console deployments if they exist
if oc get deployment.apps/console -n openshift-console &>/dev/null; then
  oc scale --replicas=0 deployment.apps/console -n openshift-console || true
  echo "Scaled down console deployment"
else
  echo "console deployment not found in openshift-console namespace"
fi

if oc get deployment.apps/downloads -n openshift-console &>/dev/null; then
  oc scale --replicas=0 deployment.apps/downloads -n openshift-console || true
  echo "Scaled down downloads deployment"
else
  echo "downloads deployment not found in openshift-console namespace"
fi

# Check for console-operator in multiple possible namespaces
# Do not scale down console-operator; CVO will recreate it. Rely on managementState=Removed instead.
if oc get deployment.apps/console-operator -n openshift-console &>/dev/null || \
   oc get deployment.apps/console-operator -n openshift-console-operator &>/dev/null; then
  echo "console-operator detected; leaving it running to honor managementState=Removed"
else
  echo "console-operator deployment not found in openshift-console or openshift-console-operator namespaces"
fi

# Disable Cluster Monitoring stack via CVO override and scale down if present
add_cvo_override Deployment apps openshift-monitoring cluster-monitoring-operator
if oc get deployment.apps/cluster-monitoring-operator -n openshift-monitoring &>/dev/null; then
  oc scale --replicas=0 deployment.apps/cluster-monitoring-operator -n openshift-monitoring || true
  echo "Scaled down cluster-monitoring-operator"
fi
for d in prometheus-operator prometheus-k8s alertmanager-main grafana kube-state-metrics \
         openshift-state-metrics telemeter-client thanos-querier; do
  if oc get deployment.apps/$d -n openshift-monitoring &>/dev/null; then
    oc scale --replicas=0 deployment.apps/$d -n openshift-monitoring || true
    echo "Scaled down $d in openshift-monitoring"
  fi
done

# Disable Insights operator via CVO override and scale down if present
add_cvo_override Deployment apps openshift-insights insights-operator
if oc get deployment.apps/insights-operator -n openshift-insights &>/dev/null; then
  oc scale --replicas=0 deployment.apps/insights-operator -n openshift-insights || true
  echo "Scaled down insights-operator"
fi

echo "=== Resource scaling completed ==="


