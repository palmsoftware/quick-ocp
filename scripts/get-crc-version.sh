#!/bin/bash
set -e

crc version
echo $PATH
VERSION_NUMBER=$(crc version | grep CRC | awk '{ print $3 }')
echo $VERSION_NUMBER
echo $(crc version | grep CRC | awk '{ print $3 }')
echo "version_number=$(crc version | grep CRC | awk '{ print $3 }')" | tee "${GITHUB_OUTPUT}"
