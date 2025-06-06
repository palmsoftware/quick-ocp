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

```
steps:
  - name: Set up Quick-OCP
    uses: palmsoftware/quick-ocp@v0.0.11
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
- Supported values are `4.17`, `4.18`, and `latest`.

For more details, see the [action.yml](action.yml) and workflow examples.
