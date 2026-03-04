#!/bin/bash
set -e

PULL_SECRET="$1"

(umask 077 && echo "$PULL_SECRET" >pull-secret.json)
