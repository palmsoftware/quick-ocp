#!/usr/bin/env bash

set -euo pipefail

echo "=== Quantify potential savings from scaling down console components (no changes made) ==="

targets=()

# Discover targets based on what the current scale-down script manages
if oc get deployment.apps/console -n openshift-console &>/dev/null; then
  targets+=("openshift-console:console")
fi
if oc get deployment.apps/downloads -n openshift-console &>/dev/null; then
  targets+=("openshift-console:downloads")
fi
if oc get deployment.apps/console-operator -n openshift-console &>/dev/null; then
  targets+=("openshift-console:console-operator")
elif oc get deployment.apps/console-operator -n openshift-console-operator &>/dev/null; then
  targets+=("openshift-console-operator:console-operator")
fi

if [ ${#targets[@]} -eq 0 ]; then
  echo "No target deployments found. Nothing to quantify."
  exit 0
fi

have_jq=true
command -v jq >/dev/null 2>&1 || have_jq=false

to_millicores() {
  local v="$1"
  if [[ -z "$v" || "$v" == "0" ]]; then
    echo 0
    return
  fi
  if [[ "$v" =~ m$ ]]; then
    echo "${v%m}"
  else
    # assume cores -> millicores
    awk -v c="$v" 'BEGIN{ printf("%d", c*1000) }'
  fi
}

to_mi() {
  local v="$1"
  if [[ -z "$v" || "$v" == "0" ]]; then
    echo 0
    return
  fi
  # Normalize Ki, Mi, Gi, Ti to Mi
  case "$v" in
    *Ki) awk -v x="${v%Ki}" 'BEGIN{ printf("%.0f", x/1024) }' ;;
    *Mi) echo "${v%Mi}" ;;
    *Gi) awk -v x="${v%Gi}" 'BEGIN{ printf("%.0f", x*1024) }' ;;
    *Ti) awk -v x="${v%Ti}" 'BEGIN{ printf("%.0f", x*1024*1024) }' ;;
    *) echo 0 ;;
  esac
}

sum_req_cpu_mc=0
sum_req_mem_mi=0

printf '\n-- Requested resources (theoretical reserved capacity) --\n'
for t in "${targets[@]}"; do
  ns="${t%%:*}"
  name="${t##*:}"
  echo "Deployment ${name} in ${ns}:"
  if $have_jq; then
    json=$(oc get deploy "$name" -n "$ns" -o json)
    # Per-container breakdown
    echo "$json" | jq -r '.spec.template.spec.containers[]? | "  \(.name): cpuReq=\(.resources.requests.cpu // "0") memReq=\(.resources.requests.memory // "0")"'
    # Sum requests
    cpu_req_total=$(echo "$json" | jq -r '[.spec.template.spec.containers[]? | .resources.requests.cpu // "0"] | join("+")' | sed 's/+/ /g' | awk '{print NF? $0: 0}')
    mem_req_total=$(echo "$json" | jq -r '[.spec.template.spec.containers[]? | .resources.requests.memory // "0"] | join("+")' | sed 's/+/ /g' | awk '{print NF? $0: 0}')
    # Convert and add
    # shellcheck disable=SC2206
    cpu_parts=($cpu_req_total)
    # shellcheck disable=SC2206
    mem_parts=($mem_req_total)
    cpu_mc=0
    mem_mi=0
    for p in "${cpu_parts[@]:-}"; do cpu_mc=$((cpu_mc + $(to_millicores "$p"))); done
    for p in "${mem_parts[@]:-}"; do mem_mi=$((mem_mi + $(to_mi "$p"))); done
    echo "  Total requests: CPU=${cpu_mc}m MEM=${mem_mi}Mi"
    sum_req_cpu_mc=$((sum_req_cpu_mc + cpu_mc))
    sum_req_mem_mi=$((sum_req_mem_mi + mem_mi))
  else
    echo "  jq not found; install jq to see request breakdown"
  fi
done

printf '\nRequested totals across targets: CPU=%sm MEM=%sMi\n' "${sum_req_cpu_mc}" "${sum_req_mem_mi}"

printf '\n-- Current usage (from metrics; best-effort) --\n'
have_metrics=true
oc adm top pods -A >/dev/null 2>&1 || have_metrics=false

sum_use_cpu_mc=0
sum_use_mem_mi=0

if $have_metrics; then
  for t in "${targets[@]}"; do
    ns="${t%%:*}"
    name="${t##*:}"
    # list matching pods in ns and sum their usage
    # capture lines starting with pod name prefixes
    lines=$(oc adm top pods -n "$ns" 2>/dev/null | awk -v n="$name" 'NR>1 && index($1, n)==1 {print $0}')
    cpu_mc=0
    mem_mi=0
    while read -r pod cpu mem rest; do
      [[ -z "$pod" ]] && continue
      cpu_mc=$((cpu_mc + $(to_millicores "$cpu")))
      mem_mi=$((mem_mi + $(to_mi "$mem")))
    done <<<"$lines"
    echo "Deployment ${name} in ${ns}: CPU=${cpu_mc}m MEM=${mem_mi}Mi"
    sum_use_cpu_mc=$((sum_use_cpu_mc + cpu_mc))
    sum_use_mem_mi=$((sum_use_mem_mi + mem_mi))
  done
  printf '\nCurrent usage totals across targets: CPU=%sm MEM=%sMi\n' "${sum_use_cpu_mc}" "${sum_use_mem_mi}"
else
  echo "Metrics not available (oc adm top). Skipping live usage; using requests only."
fi

printf '\n=== End quantification ===\n'
