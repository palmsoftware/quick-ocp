# CLAUDE.md

Guidance for working with the quick-ocp GitHub Action.

## Overview

quick-ocp deploys an OpenShift Local (CRC) cluster on GitHub Actions runners. It is optimized for free-tier runners through aggressive disk cleanup, swap creation, bundle caching, and operator scaling.

## Commands

```bash
cd quick-ocp

# Lint shell scripts (requires shfmt and shellcheck)
make lint

# Auto-fix shell script formatting
make fix-lint

# Run BATS unit tests (requires bats)
make test

# Check that Quay cache images exist for each pinned OCP version (manifest lookups only)
make check-image-cache

# Verify Quay cache image content matches the CRC version pins.
# Linux-only (downloads the pinned crc binary); pulls each ~6 GB image in turn.
# CI runs this on every PR and nightly.
make verify-image-cache
```

## Key Files

| File | Purpose |
|------|---------|
| `action.yml` | Composite action definition (inputs, outputs, step sequence) |
| `crc-version-pins.json` | Maps OCP versions to CRC versions; documents known issues |
| `.github/workflows/reusable-ocp-tests.yml` | CI matrix and workflow examples |
| `scripts/` | Modular shell scripts called from `action.yml` |
| `tests/` | BATS unit tests for the scripts (`make test`) |

## Version Selection

Priority for CRC version resolution:

1. Resolve deprecated OCP version aliases from `crc-version-pins.json` (`4.18` and `4.19` map to `4.20`)
2. For non-deprecated requests, use an explicit `crcVersion` input
3. Pin in `crc-version-pins.json`
4. Auto-detection via GitHub API (`"auto"` pins)

An explicit `crcVersion` is ignored when the requested OCP version is a deprecated alias.

YAML parsers treat `4.20` as `4.2` and `5.0` as `5`; the action normalizes both automatically.

## Supported Runners

Tested on `ubuntu-22.04`, `ubuntu-24.04`, and `ubuntu-26.04`.

- `ubuntu-20.04` is unsupported (libvirt too old).
- On `ubuntu-26.04`, use OCP `4.22`, `5.0`, or `latest` — older OCP versions fail SSH during CRC start.
- On `ubuntu-26.04`, the action sets libvirt `security_driver = "none"` so AppArmor/`virt-aa-helper` does not reject `OVMF.amdsev.fd` during CRC start.

## External Dependencies

- **OpenShift Mirror** (`mirror.openshift.com`) — CRC binary and bundle downloads (required).
- **GitHub API** — CRC version auto-detection (optional; non-fatal connectivity check).
- **Quay** (`quay.io/bapalm/quick-ocp-cache`) — CRC bundle image cache for the pre-seed and post-failure fallback (optional; failures degrade to the mirror).

## Usage

```yaml
- uses: palmsoftware/quick-ocp@v1
  with:
    ocpPullSecret: $OCP_PULL_SECRET
    bundleCache: true
    desiredOCPVersion: "4.20"
  env:
    OCP_PULL_SECRET: ${{ secrets.OCP_PULL_SECRET }}
```

## Release Tags

- `@v1` — major version tag (recommended)
- `@v1.x.y` — exact patch release; see the [releases page](https://github.com/palmsoftware/quick-ocp/releases/latest) for the current version

Semantic versioning: `v1.x.y` with `update-major-tag.yml` maintaining the major tag.

`update-major-tag.yml` force-moves `v1` to the new release on every publish, so the major tag is
never fast-forwardable from a clone. A plain `git fetch --tags` therefore fails with
`! [rejected] v1 -> v1 (would clobber existing tag)`; use `git fetch --tags --force`.

## Common Gotchas

1. **Bundle caching**: `bundleCache: true` uses GitHub Actions cache (10 GB limit). Essential on free-tier runners. On cache misses, `imageBundleCache: true` (the default) pre-seeds the bundle from the Quay image cache (`bapalm/quick-ocp-cache`); pre-seed failures always degrade to the mirror download.
2. **Memory floor**: `crcMemory` minimum is 10752 MB (CRC requirement); default matches this.
3. **Cluster monitoring**: Auto-increases memory to 14336 MB; allow 60-minute job timeout.
4. **Disk space**: CRC needs ~25 GB free; action runs quick-cleanup in aggressive mode before setup.
5. **Connectivity check**: Validates OpenShift Mirror reachability; GitHub API check is non-fatal.
6. **Stalled bundle download**: `run-crc-setup.sh` kills `crc setup` after 300s with no growth in `~/.crc/cache` (`CRC_SETUP_STALL_TIMEOUT`), removes the partial bundle, and fails without retrying the mirror so the Quay image cache fallback runs.
7. **Missing kubeconfig contexts**: `crc start` can log `Cannot update kubeconfig` (OAuth route not ready) and still exit 0. `ensure-kubeconfig.sh` recreates `crc-admin`/`crc-developer` with OAuth logins (retried up to 600s, `ENSURE_KUBECONFIG_TIMEOUT`) before the node-ready wait.
8. **Docs-only PRs**: `pre-main.yml` uses `paths-ignore: **.md`, so a PR that changes only Markdown runs no Test Changes jobs (CodeQL still runs). If a check from that workflow is ever made required in the `main` ruleset, switch to a job-level change filter so skipped runs still report.
