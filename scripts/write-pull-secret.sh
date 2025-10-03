#!/bin/bash
set -e

PULL_SECRET="$1"

echo "$PULL_SECRET" >pull-secret.json
