# quick-ocp

[![Nightly Test](https://github.com/palmsoftware/quick-ocp/actions/workflows/nightly.yml/badge.svg)](https://github.com/palmsoftware/quick-ocp/actions/workflows/nightly.yml)
[![Test Changes](https://github.com/palmsoftware/quick-ocp/actions/workflows/pre-main.yml/badge.svg)](https://github.com/palmsoftware/quick-ocp/actions/workflows/pre-main.yml)
[![Update Major Version Tag](https://github.com/palmsoftware/quick-ocp/actions/workflows/update-major-tag.yml/badge.svg)](https://github.com/palmsoftware/quick-ocp/actions/workflows/update-major-tag.yml)

Quickly spawns an OCP cluster using [OpenShift Local](https://developers.redhat.com/products/openshift-local/overview) for use on Github Actions.

This will work on the free tier lowest resource runners at the moment with additional runner support added later if needed.

Read more about Github Actions runners [here](https://docs.github.com/en/actions/using-github-hosted-runners/using-github-hosted-runners/about-github-hosted-runners).

If you are looking to quickly spawn Kubernetes in your Action runner, try [quick-k8s](https://github.com/palmsoftware/quick-k8s).

# Supported Runners

This action is tested on the following GitHub Actions runners:

- `ubuntu-24.04`
- `ubuntu-22.04`

# Known Limitations:

- `ubuntu-26.04` is not yet supported due to a CRC vsock SSH incompatibility with Linux kernel 7.0. See [crc-org/crc#5283](https://github.com/crc-org/crc/issues/5283) for tracking.
- `ubuntu-20.04` is not supported due to the version of `libvirt` available in the mirrors not meeting the minimum version required by OpenShift Local.

# Connectivity Requirements:

This action requires network access to the **OpenShift Mirror** (`https://mirror.openshift.com`) for downloading CRC binaries and OpenShift client tools.

The action includes an automatic connectivity check that runs at the beginning of each workflow. If the OpenShift Mirror is unreachable, the action will fail gracefully with a clear error message.

You can disable this check by setting `disableConnectivityCheck: true` in your workflow:

```yaml
with:
  disableConnectivityCheck: true
```

Note: Disabling this check is not recommended as it may result in less clear error messages if connectivity issues occur during the workflow.

# Usage:

Basic Usage:

You will need to supply your OCP Pull Secret as a Github Actions Secret.  Your pull secret can be acquired from [here](https://console.redhat.com/openshift/install/pull-secret).  Click on "Download Pull Secret" and copy the contents into your secret.

```yaml
steps:
  - name: Set up Quick-OCP
    uses: palmsoftware/quick-ocp@v1
    with:
      ocpPullSecret: $OCP_PULL_SECRET
    env:
      OCP_PULL_SECRET: ${{ secrets.OCP_PULL_SECRET }}
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `ocpPullSecret` | Pull secret for OpenShift Local | Yes | — |
| `desiredOCPVersion` | OpenShift version to deploy (`4.18`, `4.19`, `4.20`, `4.21`, `4.22`, or `latest`) | No | `latest` |
| `crcVersion` | Specific CRC version to use (overrides version detection and pinning) | No | — |
| `bundleCache` | Cache the CRC bundles for faster startup | No | `false` |
| `crcMemory` | Memory allocation in MB for OpenShift Local | No | `10752` |
| `crcCpu` | CPU allocation for OpenShift Local | No | `4` |
| `crcDiskSize` | Disk size in GB for OpenShift Local | No | `31` |
| `waitForOperatorsReady` | Wait for all operators to be ready | No | `false` |
| `enableClusterMonitoring` | Enable the cluster monitoring stack (auto-increases memory to 14GiB) | No | `false` |
| `enableTelemetry` | Enable telemetry for OpenShift Local | No | `true` |
| `disableConnectivityCheck` | Disable the connectivity check for OpenShift Mirror | No | `false` |
| `preloadImages` | Newline-separated list of container images to preload into the cluster registry | No | — |

## Outputs

| Output | Description |
|--------|-------------|
| `ocp-version` | The deployed OpenShift version (e.g., `4.19.8`) |
| `crc-version` | The CRC version used (e.g., `2.54.0`) |
| `api-url` | The OpenShift API server URL (`https://api.crc.testing:6443`) |
| `console-url` | The OpenShift web console URL |
| `kubeadmin-password` | The kubeadmin password for cluster authentication (masked in logs) |

# OpenShift Local

https://developers.redhat.com/products/openshift-local/overview

This is development only environment that is provided by Red Hat that will allow you do some quick testing in a full OpenShift environment.

## References

- [install-oc-tools.sh](./scripts/install-oc-tools.sh) was a script copied from [install-oc-tools](https://github.com/cptmorgan-rh/install-oc-tools) and slightly modified for `aarch64`.

## OpenShift Version Selection

You can control which OpenShift version is deployed by setting the `desiredOCPVersion` input variable. For example:

```yaml
with:
  desiredOCPVersion: 4.18
```

- The default is `latest`, which will use the most recent supported version.  If you leave `desiredOCPVersion` blank, you will get the latest version.
- Supported values are `4.18`, `4.19`, `4.20`, `4.21`, `4.22`, and `latest`.

**Note:** YAML parsers interpret `4.20` as a floating-point number and convert it to `4.2`. The action automatically normalizes this back to `4.20`, so you don't need to quote version numbers in your workflow files.

For more details, see the [action.yml](action.yml) and workflow examples.

## CRC Version Control

### Version Pinning

To ensure stability and avoid issues with specific CRC releases, this action uses a version pinning mechanism. The `crc-version-pins.json` file maps OCP versions to specific known-good CRC versions.

**How it works:**
1. When you specify a `desiredOCPVersion` (e.g., `4.19`), the action first checks `crc-version-pins.json`
2. If a specific CRC version is pinned (not set to `"auto"`), that version is used
3. If set to `"auto"`, the action queries the GitHub API for the latest CRC release supporting that OCP version
4. Known issues with specific versions are documented in the `known_issues` section

**Example from `crc-version-pins.json`:**
```json
{
  "version_pins": {
    "latest": "auto",
    "4.18": "auto",
    "4.19": "2.54.0",
    "4.20": "auto",
    "4.21": "auto",
    "4.22": "auto"
  },
  "known_issues": {
    "4.19": {
      "broken_versions": ["2.55.0", "2.55.1"],
      "issue": "https://github.com/crc-org/crc/issues/4981",
      "description": "CRC 2.55.x with bundle 4.19.13 has expired kube-scheduler certificates"
    }
  }
}
```

**Note:** Versions set to `"auto"` (latest, 4.18, 4.20, 4.21, 4.22) automatically fetch the latest compatible CRC version from GitHub API. Only 4.19 is pinned to 2.54.0 to avoid the certificate issue in 2.55.x.

### Explicit CRC Version Override

You can also explicitly specify a CRC version, which overrides both version pinning and automatic detection:

```yaml
with:
  desiredOCPVersion: 4.19
  crcVersion: 2.54.0
```

This is useful for:
- Testing specific CRC versions
- Working around newly discovered issues before pins are updated
- Ensuring reproducibility in CI/CD pipelines

**Priority order:**
1. Explicit `crcVersion` input (highest priority)
2. Pinned version in `crc-version-pins.json`
3. Automatic detection via GitHub API (lowest priority)

## Cluster Monitoring

Setting `enableClusterMonitoring: true` deploys the OpenShift cluster monitoring stack (Prometheus, Alertmanager, etc.) inside the CRC VM. This has significant resource implications on free-tier runners:

- **Memory**: The action automatically increases CRC memory to 14,336 MB (14 GiB) if the configured value is lower. Free-tier runners have ~7 GB of host RAM, so the VM will rely heavily on swap.
- **Disk**: The monitoring stack pulls additional container images and generates metric data. Expect roughly 3-5 GB of extra disk usage on top of the base cluster.
- **Startup time**: Allow up to 60 minutes total — the monitoring pods (Prometheus, Alertmanager, node-exporter) may take several minutes to schedule and reach Ready state after the cluster is up.

```yaml
- uses: palmsoftware/quick-ocp@v1
  with:
    ocpPullSecret: $OCP_PULL_SECRET
    bundleCache: true
    enableClusterMonitoring: true
    crcMemory: '14336'
  env:
    OCP_PULL_SECRET: ${{ secrets.OCP_PULL_SECRET }}
```

**Recommendations:**
- Always use `bundleCache: true` to avoid adding bundle download time to an already long job.
- Set `timeout-minutes: 60` on the job to allow enough time for the monitoring stack to start.
- If you only need to verify monitoring is available and don't need it running for your tests, consider checking for the operator status rather than waiting for all pods.

## Preloading Container Images

Use the `preloadImages` input to mirror container images into the cluster's internal registry before your tests run. This is useful when your tests deploy workloads that pull from external registries — preloading avoids pull failures and speeds up pod startup.

Images are specified as a newline-separated list using YAML's pipe (`|`) syntax:

```yaml
- uses: palmsoftware/quick-ocp@v1
  with:
    ocpPullSecret: $OCP_PULL_SECRET
    bundleCache: true
    preloadImages: |
      docker.io/library/nginx:latest
      quay.io/myorg/myapp:v1.2.3
  env:
    OCP_PULL_SECRET: ${{ secrets.OCP_PULL_SECRET }}
```

Each image is mirrored into the `openshift` namespace as an ImageStream. For example, `docker.io/library/nginx:latest` becomes available as `nginx:latest` in the `openshift` namespace:

```bash
oc get imagestream nginx -n openshift
```

Lines starting with `#` and blank lines are ignored, so you can comment your image list.

## Troubleshooting

### OOM Kills

**Symptom:** The job fails with `crc start` errors, or the CRC VM becomes unresponsive. The runner's dmesg may show `Out of memory: Killed process`.

**Cause:** Free-tier runners have ~7 GB of RAM. The CRC VM is allocated 10,752 MB by default, so it relies on swap. Heavy workloads or enabling cluster monitoring (14 GiB) increases pressure further.

**Mitigations:**
- The action automatically creates swap on `/mnt` and protects CRC/QEMU processes from the OOM killer.
- Use `bundleCache: true` to avoid downloading the 3-5 GB bundle during the job, freeing memory during the critical startup window.
- Reduce `crcMemory` if your tests don't need the full allocation (minimum ~9216 MB for a functional cluster).
- Avoid running memory-intensive steps before `crc start` completes.

### Disk Space Exhaustion

**Symptom:** The job fails during CRC setup, bundle extraction, or cluster startup with errors about insufficient disk space.

**Cause:** The CRC bundle is 3-5 GB compressed, and the extracted VM image plus cluster data can use 20+ GB. Free-tier runners have limited disk on the root partition.

**Mitigations:**
- The action uses [quick-cleanup](https://github.com/palmsoftware/quick-cleanup) in aggressive mode to free space before cluster creation and relocates Docker storage to the larger `/mnt` partition.
- Use `bundleCache: true` — cached bundles are stored via GitHub Actions cache and extracted directly, avoiding a separate download.
- The action prints a comprehensive disk space report at the end of each run. Look for the **Disk Space Report** step in the job output to see where space was consumed.

### CRC Start Failures

**Symptom:** The `Run setup` step fails after one or more retries with errors like `Failed to connect to the CRC VM with SSH`, `connection refused`, or `Failed to update pull secret`.

**Cause:** CRC start can fail transiently due to VM boot timing, SSH connectivity, or resource pressure. The action retries up to 3 times with a 30-second delay between attempts.

**What to check:**
- Expand the **CRC Setup and Start** group in the job log to see the full output from each attempt.
- If every attempt fails with the same error, it's likely a resource issue (see OOM and disk sections above).
- If the error mentions `kubeconfig` or `pull secret`, these are typically transient and resolve on retry.

### Operator Timeout

**Symptom:** The job succeeds at creating the cluster but fails at the `Wait for operators to be available` step.

**Cause:** Some operators take longer to roll out on resource-constrained runners. The default timeout is 600 seconds (10 minutes).

**Mitigations:**
- Increase the timeout: `operatorTimeout: '900'`
- If you don't need all operators ready for your tests, set `waitForOperatorsReady: false` (the default) and check only the operators you need.
- Non-essential operators are automatically scaled down to save resources. Only core operators remain active.

### Connectivity Failures

**Symptom:** The job fails at the `Check connectivity to required services` step.

**Cause:** The OpenShift Mirror (`mirror.openshift.com`) or Red Hat SSO is unreachable. This can happen during Red Hat maintenance windows.

**What to check:**
- Check [Red Hat Status](https://status.redhat.com/) for ongoing incidents.
- The GitHub API connectivity check is non-fatal — a warning is logged but the job continues.
- If the mirror is consistently down, you can use `disableConnectivityCheck: true` to skip the check, but the download step will still fail if the mirror is actually unreachable.
