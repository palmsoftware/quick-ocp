#!/bin/bash

for cmd in kubectl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed." >&2
    exit 1
  fi
done

timeout=1200  # 20 minutes in seconds
elapsed=0
interval=10

# Function to check if a pod should be ignored
should_ignore_pod() {
  local namespace="$1"
  local pod_name="$2"
  
  # Skip cronjob-generated pods (they come and go by design)
  if [[ "$pod_name" =~ ^(collect-profiles|image-pruner)-[0-9]{8,}-[a-z0-9]{5}$ ]]; then
    return 0
  fi
  
  # Skip network diagnostics pods (often problematic and not essential)
  if [[ "$namespace" == "openshift-network-diagnostics" ]]; then
    return 0
  fi
  
  # Skip marketplace catalog pods if they're being scaled down
  if [[ "$namespace" == "openshift-marketplace" && "$pod_name" =~ ^(certified|community|redhat)-operators-[a-z0-9]+$ ]]; then
    return 0
  fi
  
  # Skip migrator pods that are being scaled down
  if [[ "$namespace" == "openshift-kube-storage-version-migrator" && "$pod_name" =~ ^migrator-[a-z0-9]+-[a-z0-9]+$ ]]; then
    return 0
  fi
  
  # Skip console pods if they're being scaled down
  if [[ "$namespace" == "openshift-console" && "$pod_name" =~ ^(console|downloads)-[a-z0-9]+-[a-z0-9]+$ ]]; then
    return 0
  fi
  
  # Don't ignore - this pod is essential
  return 1
}

while true; do
  # Get all non-running/non-completed pods
  pending_pods=$(oc get pods --all-namespaces --no-headers | awk '{if ($4 != "Running" && $4 != "Completed") print $1 ":" $2 ":" $4}')
  
  if [ -z "$pending_pods" ]; then
    echo "All pods are running or completed"
    break
  fi
  
  # Filter out non-essential pending pods
  essential_pending=""
  while IFS=':' read -r namespace pod_name status; do
    if ! should_ignore_pod "$namespace" "$pod_name"; then
      essential_pending="$essential_pending$namespace:$pod_name:$status\n"
    fi
  done <<< "$pending_pods"
  
  if [ -z "$essential_pending" ]; then
    echo "All essential pods are running or completed (ignoring non-essential pods)"
    break
  else
    echo "Waiting for essential pods to be running or completed..."
    echo -e "$essential_pending" | while IFS=':' read -r namespace pod_name status; do
      echo "Pending essential pod: $pod_name in namespace: $namespace (status: $status)"
    done
    sleep $interval
    elapsed=$((elapsed + interval))
    if [ $elapsed -ge $timeout ]; then
      echo "Timeout reached: Not all essential pods are running or completed"
      echo "Remaining pending essential pods:"
      echo -e "$essential_pending" | while IFS=':' read -r namespace pod_name status; do
        echo "  - $pod_name in $namespace (status: $status)"
      done
      exit 1
    fi
  fi
done
