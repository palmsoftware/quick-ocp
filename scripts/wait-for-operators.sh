#!/bin/bash

timeout=600  # 10 minutes in seconds
elapsed=0
interval=10

while true; do
  if oc get co --no-headers | awk '{if ($3 != "True" || $4 != "False") exit 1}'; then
    echo "All operators are available and not progressing"
    break
  else
    echo "Waiting for operators to become available..."
    sleep $interval
    elapsed=$((elapsed + interval))
    if [ $elapsed -ge $timeout ]; then
      echo "Timeout reached: Not all operators are available"
      exit 1
    fi
  fi
done
