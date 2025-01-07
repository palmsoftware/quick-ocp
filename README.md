# quick-ocp
Quickly spawns an OCP cluster using [OpenShift Local](https://developers.redhat.com/products/openshift-local/overview) for use on Github Actions.

This will work on the free tier lowest resource runners at the moment with additional runner support added later if needed.

Read more about Github Actions runners [here](https://docs.github.com/en/actions/using-github-hosted-runners/using-github-hosted-runners/about-github-hosted-runners).

# Usage:

Basic Usage:

You will need to supply your OCP Pull Secret as a Github Actions Secret.  Your pull secret can be acquired from [here](https://console.redhat.com/openshift/install/azure/aro-provisioned).  Click on "Download Pull Secret" and copy the contents into your secret.

```
steps:
  - name: Set up Quick-OCP
    uses: palmsoftware/quick-ocp@v0.0.1
    with:
          ocpPullSecret: $OCP_PULL_SECRET
        env:
          OCP_PULL_SECRET: ${{ secrets.OCP_PULL_SECRET }}
```

# OpenShift Local

https://developers.redhat.com/products/openshift-local/overview

This is development only environment that is provided by Red Hat that will allow you do some quick testing in a full OpenShift environment.

