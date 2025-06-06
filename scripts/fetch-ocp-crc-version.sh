#!/usr/bin/env bash

# Fetch CRC releases and determine the latest release for each unique OpenShift major.minor version.

GITHUB_API="https://api.github.com/repos/crc-org/crc/releases?per_page=100"

if [ -z "$1" ]; then
  echo "Usage: $0 <ocp_major.minor> (e.g., 4.18)" >&2
  exit 1
fi
OCP_VERSION="$1"

# Only support OCP versions 4.10 and above
if ! [[ "$OCP_VERSION" =~ ^4\.([1-9][0-9]|10)$ ]]; then
  echo "Error: Only OCP versions 4.10 and above are supported (e.g., 4.18, 4.20)." >&2
  exit 2
fi

# Retry curl up to 10 times with 3s delay
RETRIES=10
for i in $(seq 1 $RETRIES); do
  RESPONSE=$(curl -s "$GITHUB_API")
  if [ -n "$RESPONSE" ] && [ "$RESPONSE" != "null" ]; then
    break
  fi
  if [ "$i" -eq "$RETRIES" ]; then
    echo "Error: Failed to fetch CRC releases from GitHub API after $RETRIES attempts." >&2
    exit 3
  fi
  sleep 3
done

echo "$RESPONSE" | jq -r --arg OCP_MINOR "$OCP_VERSION" '
  [
    .[] 
    | {
        tag: .tag_name,
        name: .name,
        url: .html_url,
        published: .published_at,
        body: .body
      }
    | . + {
        ocp_minor: (
          if (.name | test("-[0-9]+\\.[0-9]+\\.[0-9]+$")) then
            (.name | capture("-(?<ver>[0-9]+\\.[0-9]+)\\.[0-9]+$") | .ver)
          elif (.body | test("OpenShift\\s+[0-9]+\\.[0-9]+\\.[0-9]+")) then
            (.body | capture("OpenShift\\s+(?<ver>[0-9]+\\.[0-9]+)\\.[0-9]+") | .ver)
          else
            null
          end
        )
      }
    | select(.ocp_minor == $OCP_MINOR)
  ]
  | sort_by(.published)
  | reverse
  | .[0]
  | if . == null then
      ("No CRC release found for OpenShift version \($OCP_MINOR)")
    else
      (.tag | sub("^v"; ""))
    end
'
