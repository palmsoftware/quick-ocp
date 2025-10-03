#!/bin/bash
set -e

crc version
echo $(crc version | grep OpenShift | awk '{ print $3 }')
echo "ocp_version=$(crc version | grep OpenShift | awk '{ print $3 }')" | tee "${GITHUB_OUTPUT}"
