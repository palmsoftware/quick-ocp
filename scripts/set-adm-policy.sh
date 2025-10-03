#!/bin/bash
set -e

oc adm policy add-scc-to-user privileged user
oc adm policy add-scc-to-group privileged system:authenticated
