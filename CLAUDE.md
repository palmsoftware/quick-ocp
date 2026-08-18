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
```

## Key Files

| File | Purpose |
|------|---------|
| `action.yml` | Composite action definition (inputs, outputs, step sequence) |
| `crc-version-pins.json` | Maps OCP versions to CRC versions; documents known issues |
| `.github/workflows/reusable-ocp-tests.yml` | CI matrix and workflow examples |
| `scripts/` | Modular shell scripts called from `action.yml` |

## Version Selection

Priority for CRC version resolution:

1. Explicit `crcVersion` input
2. Pin in `crc-version-pins.json`
3. Auto-detection via GitHub API (`"auto"` pins)

YAML parsers treat `4.20` as `4.2`; the action normalizes this automatically.

## Supported Runners

Tested on `ubuntu-22.04`, `ubuntu-24.04`, and `ubuntu-26.04`.

- `ubuntu-20.04` is unsupported (libvirt too old).
- On `ubuntu-26.04`, use OCP `4.22` or `latest` — older OCP versions fail SSH during CRC start.

## External Dependencies

- **OpenShift Mirror** (`mirror.openshift.com`) — CRC binary and bundle downloads (required).
- **GitHub API** — CRC version auto-detection (optional; non-fatal connectivity check).

## Usage

```yaml
- uses: palmsoftware/quick-ocp@v1
  with:
    ocpPullSecret: $OCP_PULL_SECRET
    bundleCache: true
    desiredOCPVersion: "4.19"
  env:
    OCP_PULL_SECRET: ${{ secrets.OCP_PULL_SECRET }}
```

## Release Tags

- `@v1` — major version tag (recommended)
- `@v1.0.1` — latest patch release

Semantic versioning: `v1.x.y` with `update-major-tag.yml` maintaining the major tag.

## Common Gotchas

1. **Bundle caching**: `bundleCache: true` uses GitHub Actions cache (10 GB limit). Essential on free-tier runners.
2. **Memory floor**: `crcMemory` minimum is 10752 MB (CRC requirement); default matches this.
3. **Cluster monitoring**: Auto-increases memory to 14336 MB; allow 60-minute job timeout.
4. **Disk space**: CRC needs ~25 GB free; action runs quick-cleanup in aggressive mode before setup.
5. **Connectivity check**: Validates OpenShift Mirror reachability; GitHub API check is non-fatal.
