#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# Version/tag to use from upstream. Align with certsuite sample workload flow.
: "${MULTUS_VERSION:=v4.2.2}"
: "${NAD_MASTER_IF:=}"

require_oc() {
  if ! command -v oc >/dev/null 2>&1; then
    err "oc not found"
    exit 1
  fi
}

require_cluster() {
  if ! oc cluster-info >/dev/null 2>&1; then
    err "Not connected to a cluster"
    exit 1
  fi
}

install_cni_plugins() {
  info "Verifying required CNI plugins on the node (macvlan, host-local)"
  local nodeName
  nodeName=$(oc get nodes -o jsonpath='{.items[0].metadata.name}')
  # List common CNI bin dirs and check for plugins
  oc debug node/${nodeName} -- chroot /host sh -lc 'set -e; for d in /opt/cni/bin /usr/libexec/cni; do if [ -d "$d" ]; then echo "-- $d"; ls -1 "$d" | sort; fi; done' | cat || true
  # Soft check for plugin presence
  if ! oc debug node/${nodeName} -- chroot /host sh -lc '[ -x /opt/cni/bin/macvlan ] || [ -x /usr/libexec/cni/macvlan ]' >/dev/null 2>&1; then
    warn "macvlan plugin not found on node; macvlan attachments will not work"
  fi
  if ! oc debug node/${nodeName} -- chroot /host sh -lc '[ -x /opt/cni/bin/host-local ] || [ -x /usr/libexec/cni/host-local ]' >/dev/null 2>&1; then
    warn "host-local plugin not found on node; IPAM may fail"
  fi

  # Ensure Multus can find plugins under /opt/cni/bin by symlinking from /usr/libexec/cni if needed
  info "Creating symlinks for common CNI plugins into /opt/cni/bin if missing"
  oc debug node/${nodeName} -- chroot /host sh -lc '
    set -e
    mkdir -p /opt/cni/bin
    for p in macvlan host-local ptp bridge sbr tuning vlan ipvlan; do
      if [ ! -x "/opt/cni/bin/$p" ] && [ -x "/usr/libexec/cni/$p" ]; then
        ln -sf "/usr/libexec/cni/$p" "/opt/cni/bin/$p" || true
      fi
    done
    ls -l /opt/cni/bin | sed -n "1,120p"
  ' | cat || true
}

detect_master_interface() {
  # Auto-detect the primary uplink on the node if NAD_MASTER_IF is not provided
  if [[ -n "${NAD_MASTER_IF:-}" ]]; then
    info "Using provided NAD_MASTER_IF=${NAD_MASTER_IF}"
    return 0
  fi
  local nodeName
  nodeName=$(oc get nodes -o jsonpath='{.items[0].metadata.name}')
  info "Detecting default uplink interface on node ${nodeName}"
  local detected
  # Prefer default route device; fall back to first UP non-virtual device
  detected=$(oc debug node/${nodeName} -- chroot /host sh -lc "ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++){if(\$i==\"dev\"){print \$(i+1); exit}}}'" | tail -n1 2>/dev/null || true)
  if [[ -z "$detected" ]]; then
    detected=$(oc debug node/${nodeName} -- chroot /host sh -lc "ip -o link show up | awk -F': ' '{print \$2}' | grep -Ev '^(lo|cni|flannel|tunl|veth|docker|virbr|br-|bond|dummy|tap)' | head -n1" | tail -n1 2>/dev/null || true)
  fi
  if [[ -n "$detected" ]]; then
    NAD_MASTER_IF="$detected"
    info "Detected NAD master interface: ${NAD_MASTER_IF}"
  else
    warn "Could not detect a suitable master interface; defaulting to eth0"
    NAD_MASTER_IF="eth0"
  fi
}

clone_and_generate_manifests() {
  info "Cloning multus-cni ${MULTUS_VERSION} and generating manifests (e2e/generate_yamls.sh)"
  local tmpdir
  tmpdir=$(mktemp -d)
  pushd "$tmpdir" >/dev/null
  git clone --depth 1 --branch "${MULTUS_VERSION}" https://github.com/k8snetworkplumbingwg/multus-cni.git | cat
  cd multus-cni/e2e

  # Python venv for j2 (jinjanator)
  python3 -m venv .venv
  source .venv/bin/activate
  pip install --upgrade pip >/dev/null
  pip install jinjanator >/dev/null
  # generate_yamls.sh expects j2 binary name
  cp .venv/bin/jinjanate .venv/bin/j2
  export PATH="$(pwd)/.venv/bin:${PATH}"

  # get_tools.sh builds helper binaries (skip on arm64 to mirror sample script)
  local arch
  arch=$(uname -m)
  if [[ "$arch" != "arm64" && "$arch" != "aarch64" ]]; then
    ./get_tools.sh | cat || warn "get_tools.sh encountered issues"
  else
    info "Skipping get_tools.sh on ${arch}"
  fi

  ./generate_yamls.sh | cat

  # Collect generated files
  # Prefer any daemonset that defines kube-multus-ds
  MULTUS_DS_FILE=$(grep -Rl "kube-multus-ds" . | grep -E '\.ya?ml$' | head -n1 || true)
  # CRD file for NAD
  NAD_CRD_FILE=$(grep -Rl "network-attachment-definitions.k8s.cni.cncf.io" . | grep -E '\.ya?ml$' | head -n1 || true)

  if [[ -z "${MULTUS_DS_FILE:-}" ]]; then
    err "Could not locate generated multus DaemonSet manifest"
    return 1
  fi

  # Export paths to caller
  # Convert to absolute paths so they are valid after we leave the temp dir
  if [[ -n "${MULTUS_DS_FILE:-}" ]]; then
    MULTUS_DS_FILE="$(cd "$(dirname "${MULTUS_DS_FILE}")" && pwd)/$(basename "${MULTUS_DS_FILE}")"
  fi
  if [[ -n "${NAD_CRD_FILE:-}" ]]; then
    NAD_CRD_FILE="$(cd "$(dirname "${NAD_CRD_FILE}")" && pwd)/$(basename "${NAD_CRD_FILE}")"
  fi
  export MULTUS_GEN_DIR="$PWD"
  export MULTUS_DS_FILE
  export NAD_CRD_FILE
  popd >/dev/null
}

deploy_multus_ds() {
  info "Deploying Multus CNI (generated manifests)"
  # Apply CRD first if present
  if [[ -n "${NAD_CRD_FILE:-}" && -f "${NAD_CRD_FILE}" ]]; then
    oc apply -f "${NAD_CRD_FILE}" | cat || warn "CRD apply encountered issues"
  fi
  oc apply -f "${MULTUS_DS_FILE}" | cat

  info "Waiting for Multus DaemonSet to be ready"
  local ds_ns="kube-system"
  local ds_name
  ds_name=$(oc -n "${ds_ns}" get ds -o name 2>/dev/null | grep -E 'daemonset.apps/kube-multus-ds(-[a-z0-9]+)?' | head -n1 || true)
  if [[ -z "${ds_name}" ]]; then
    ds_name=$(oc -n "${ds_ns}" get ds -o name 2>/dev/null | grep -i multus | head -n1 || true)
  fi
  if [[ -n "${ds_name}" ]]; then
    oc -n "${ds_ns}" rollout status "${ds_name}" --timeout=240s | cat || warn "Rollout status timed out for ${ds_name}"
  else
    warn "Could not find a Multus DaemonSet in ${ds_ns}; attempting openshift-multus"
    ds_ns="openshift-multus"
    ds_name=$(oc -n "${ds_ns}" get ds -o name 2>/dev/null | head -n1 || true)
    if [[ -n "${ds_name}" ]]; then
      oc -n "${ds_ns}" rollout status "${ds_name}" --timeout=240s | cat || true
    fi
  fi
  ok "Multus DaemonSet applied"
}

ensure_multus_bindirs() {
  info "Ensuring Multus config uses both /opt/cni/bin and /usr/libexec/cni"
  local ns="kube-system"
  local cm="multus-cni-config"
  if ! oc -n "$ns" get cm "$cm" >/dev/null 2>&1; then
    warn "ConfigMap ${cm} not found in ${ns}"
    return 0
  fi
  local cfg
  cfg=$(oc -n "$ns" get cm "$cm" -o jsonpath='{.data.cni-conf\.json}')
  if echo "$cfg" | grep -q 'binDirs'; then
    if echo "$cfg" | grep -q '/usr/libexec/cni'; then
      info "binDirs already includes /usr/libexec/cni"
      return 0
    fi
  fi
  # Build patched JSON: insert binDirs
  local patched
  patched=$(echo "$cfg" | jq 'del(.binDir) | .binDirs=["/opt/cni/bin","/usr/libexec/cni"]')
  oc -n "$ns" create configmap "$cm" --from-literal=cni-conf.json="$patched" -o yaml --dry-run=client | oc apply -f - | cat
  # Restart DS to pick up config
  local ds
  ds=$(oc -n "$ns" get ds -o name | grep -E 'daemonset.apps/kube-multus-ds(-[a-z0-9]+)?' | head -n1 || true)
  if [[ -n "$ds" ]]; then
    oc -n "$ns" rollout restart "$ds" | cat || true
    oc -n "$ns" rollout status "$ds" --timeout=240s | cat || true
  fi
}

force_public_images() {
  info "Forcing Multus DaemonSet(s) to use public image (avoid localhost:5000/e2e tags)"
  local ns="kube-system"
  local image
  : "${MULTUS_IMAGE:=ghcr.io/k8snetworkplumbingwg/multus-cni:stable}"
  # Patch all kube-multus DS variants (e.g., kube-multus-ds, kube-multus-ds-amd64)
  local ds_list
  ds_list=$(oc -n "$ns" get ds -o name 2>/dev/null | grep -E '^daemonset\.apps/kube-multus-ds' || true)
  if [[ -z "$ds_list" ]]; then
    warn "No kube-multus DaemonSets found to patch"
    return 0
  fi
  while IFS= read -r ds; do
    [[ -z "$ds" ]] && continue
    info "Patching $ds with image ${MULTUS_IMAGE}"
    oc -n "$ns" set image "$ds" kube-multus="$MULTUS_IMAGE" install-multus-binary="$MULTUS_IMAGE" | cat || true
    oc -n "$ns" patch "$ds" --type='merge' -p '{"spec":{"template":{"spec":{"initContainers":[{"name":"install-multus-binary","image":"'"${MULTUS_IMAGE}"'"}]}}}}' | cat || true
    oc -n "$ns" rollout status "$ds" --timeout=240s | cat || true
  done <<< "$ds_list"
}

create_sample_nad() {
  detect_master_interface
  info "Creating a sample macvlan NetworkAttachmentDefinition in namespace default"
  cat <<EOF | oc apply -f - | cat
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: multus-macvlan-sample
  namespace: default
spec:
  config: '{
    "cniVersion": "0.3.1",
    "type": "macvlan",
    "master": "${NAD_MASTER_IF}",
    "mode": "bridge",
    "ipam": { "type": "host-local", "subnet": "10.99.0.0/24" }
  }'
EOF
  ok "Sample NAD created"
}

verify_secondary_interface() {
  info "Launching a test pod annotated to attach the sample NAD"
  cat <<'EOF' | oc apply -f - | cat
apiVersion: v1
kind: Pod
metadata:
  name: multus-test-pod
  namespace: default
  annotations:
    k8s.v1.cni.cncf.io/networks: default/multus-macvlan-sample
spec:
  restartPolicy: Never
  containers:
  - name: test
    image: quay.io/curl/curl:8.8.0
    command: ["/bin/sh","-c"]
    args: ["sleep 3600"]
    securityContext:
      privileged: true
EOF

  info "Waiting for pod to be Ready"
  oc wait --for=condition=Ready pod/multus-test-pod -n default --timeout=180s | cat || {
    warn "Pod did not become Ready; dumping pod events"
    oc describe pod multus-test-pod -n default | cat || true
  }

  info "Checking interfaces inside the pod"
  if oc exec -n default multus-test-pod -- sh -lc 'ip -o link' | grep -q net1; then
    ok "Secondary interface net1 present in pod"
    oc exec -n default multus-test-pod -- sh -lc 'ip -o addr' | cat || true
  else
    warn "Secondary interface net1 not detected; check CNI plugins and host support"
  fi
}

cleanup_sample() {
  info "Cleanup (optional)"
  oc delete pod/multus-test-pod -n default --ignore-not-found | cat || true
}

main() {
  require_oc
  require_cluster
  clone_and_generate_manifests
  deploy_multus_ds
  ensure_multus_bindirs
  force_public_images
  install_cni_plugins
  create_sample_nad
  verify_secondary_interface
  cleanup_sample

  ok "Multus installation and validation steps completed"
}

main "$@"


