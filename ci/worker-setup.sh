#!/bin/bash


if [[ $(taskcluster api workerManager listWorkerPools | jq -r '.workerPools[] | select(.workerPoolId == "relops/win2019") | .workerPoolId') ]]; then
  echo "worker pool relops/win2019 existence detected"
else
  echo "worker pool relops/win2019 absence detected"
fi