# quick-ocp
Quickly spawns an OCP cluster using [OpenShift Local](https://developers.redhat.com/products/openshift-local/overview) for use on Github Actions.

This will work on the free tier lowest resource runners at the moment with additional runner support added later if needed.

Read more about Github Actions runners [here](https://docs.github.com/en/actions/using-github-hosted-runners/using-github-hosted-runners/about-github-hosted-runners).

If you are looking to quickly spawn Kubernetes in your Action runner, try [quick-k8s](https://github.com/palmsoftware/quick-k8s).

# Known Limitations:

- This does not run correctly on `ubuntu-20.04` runners due to the version of `libvirt` available in the mirrors isn't the minimum version required by OpenShift Local.

# Usage:

Basic Usage:

You will need to supply your OCP Pull Secret as a Github Actions Secret.  Your pull secret can be acquired from [here](https://console.redhat.com/openshift/install/azure/aro-provisioned).  Click on "Download Pull Secret" and copy the contents into your secret.

```yaml
steps:
  - name: Set up Quick-OCP
    uses: palmsoftware/quick-ocp@v0.0.16
    with:
      ocpPullSecret: ${{ secrets.OCP_PULL_SECRET }}
```

Advanced Usage with Pod Readiness Check:

```yaml
steps:
  - name: Set up Quick-OCP
    uses: palmsoftware/quick-ocp@v0.0.16
    with:
      ocpPullSecret: ${{ secrets.OCP_PULL_SECRET }}
      waitForPodsReady: 'true'
      waitForOperatorsReady: 'true'
      desiredOCPVersion: '4.18'
```

## Input Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `ocpPullSecret` | Pull secret for OpenShift Local | Yes | - |
| `waitForPodsReady` | Wait for essential pods to be ready before completing | No | `'false'` |
| `waitForOperatorsReady` | Wait for all operators to be ready | No | `'false'` |
| `desiredOCPVersion` | OpenShift version to deploy (4.17, 4.18, or latest) | No | `'latest'` |
| `crcMemory` | Memory allocation for OpenShift Local (MB) | No | `'10752'` |
| `crcCpu` | CPU allocation for OpenShift Local | No | `'4'` |
| `crcDiskSize` | Disk size for OpenShift Local (GB) | No | `'31'` |
| `bundleCache` | Cache the CRC bundles for faster startup | No | `'false'` |
| `enableTelemetry` | Enable telemetry for OpenShift Local | No | `'yes'` |

### waitForPodsReady

When set to `'true'`, this option will make the action wait for **essential pods** to be in a ready state before completing. The wait script intelligently ignores non-essential pods like cronjob-generated pods (e.g., `collect-profiles`, `image-pruner`) and components that have been scaled down for resource optimization. This ensures core cluster functionality is ready while avoiding timeouts from optional components.

**Example:**
```yaml
- name: Set up Quick-OCP with pod readiness check
  uses: palmsoftware/quick-ocp@v0.0.16
  with:
    ocpPullSecret: ${{ secrets.OCP_PULL_SECRET }}
    waitForPodsReady: 'true'
```

**Note:** Enabling this option will slightly increase the setup time but ensures core cluster components are stable for subsequent operations. The intelligent filtering avoids common timeout issues from non-essential pods.

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
- Supported values are `4.17`, `4.18`, and `latest`.

For more details, see the [action.yml](action.yml) and workflow examples.
