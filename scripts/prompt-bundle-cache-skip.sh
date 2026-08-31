#!/bin/bash
set -e

echo "Skipping cache restore due to bundleCache being false"

is_github_hosted() {
  if [ "${RUNNER_ENVIRONMENT:-}" = "github-hosted" ]; then
    return 0
  fi
  if [ "${GITHUB_ACTIONS:-}" = "true" ] && [ "${RUNNER_ENVIRONMENT:-}" != "self-hosted" ]; then
    return 0
  fi
  return 1
}

if is_github_hosted; then
  echo "::warning::bundleCache is disabled. On GitHub-hosted runners, enabling bundleCache: true caches the 3-5 GB CRC bundle via GitHub Actions cache and significantly reduces download time on subsequent runs."
fi
