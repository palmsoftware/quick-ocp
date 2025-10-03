#!/bin/bash
set -e

if [ ! -f /etc/docker/daemon.json ]; then
  echo "{}" | sudo tee /etc/docker/daemon.json
fi
