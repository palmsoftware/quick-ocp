# quick-ocp

[![Nightly Test](https://github.com/palmsoftware/quick-ocp/actions/workflows/nightly.yml/badge.svg)](https://github.com/palmsoftware/quick-ocp/actions/workflows/nightly.yml)
[![Test Changes](https://github.com/palmsoftware/quick-ocp/actions/workflows/pre-main.yml/badge.svg)](https://github.com/palmsoftware/quick-ocp/actions/workflows/pre-main.yml)
[![Update Major Version Tag](https://github.com/palmsoftware/quick-ocp/actions/workflows/update-major-tag.yml/badge.svg)](https://github.com/palmsoftware/quick-ocp/actions/workflows/update-major-tag.yml)

Quickly spawns an OCP cluster using [OpenShift Local](https://developers.redhat.com/products/openshift-local/overview) for use on Github Actions.

This will work on the free tier lowest resource runners at the moment with additional runner support added later if needed.

Read more about Github Actions runners [here](https://docs.github.com/en/actions/using-github-hosted-runners/using-github-hosted-runners/about-github-hosted-runners).

If you are looking to quickly spawn Kubernetes in your Action runner, try [quick-k8s](https://github.com/palmsoftware/quick-k8s).

# Known Limitations:

- This does not run correctly on `ubuntu-20.04` runners due to the version of `libvirt` available in the mirrors isn't the minimum version required by OpenShift Local.

# Usage:

Basic Usage:

You will need to supply your OCP Pull Secret as a Github Actions Secret.  Your pull secret can be acquired from [here](https://console.redhat.com/openshift/install/azure/aro-provisioned).  Click on "Download Pull Secret" and copy the contents into your secret.

```
steps:
  - name: Set up Quick-OCP
    uses: palmsoftware/quick-ocp@v0.0.16
    with:
          ocpPullSecret: $OCP_PULL_SECRET
        env:
          OCP_PULL_SECRET: ${{ secrets.OCP_PULL_SECRET }}
```

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
- Supported values are `4.18`, `4.19`, `4.20`, and `latest`.

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
    "4.20": "auto"
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

**Note:** Versions set to `"auto"` (latest, 4.18, 4.20) automatically fetch the latest compatible CRC version from GitHub API. Only 4.19 is pinned to 2.54.0 to avoid the certificate issue in 2.55.x.

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
