import os
import taskcluster
from cib import updateRole, updateWorkerPool


try:
  if any(line.lower().strip() == 'no-ci' or line.lower().strip() == 'no-travis-ci' for line in os.getenv('TRAVIS_COMMIT_MESSAGE').splitlines()):
    print('info: **no ci** commit syntax detected.  skipping ci task creation')
    quit()
except:
  print('warn: error reading commit message, ci disabled')
  quit()


taskclusterAuth = taskcluster.Auth(taskcluster.optionsFromEnvironment())
taskclusterWorkerManager = taskcluster.WorkerManager(taskcluster.optionsFromEnvironment())

updateRole(
  auth = taskclusterAuth,
  configPath = 'ci/config/role/branch-master.yaml',
  roleId = 'repo:github.com/mozilla-platform-ops/cloud-image-builder:branch:master')
updateWorkerPool(
  workerManager = taskclusterWorkerManager,
  configPath = 'ci/config/worker-pool/relops/decision.yaml',
  workerPoolId = 'relops/decision')
updateWorkerPool(
  workerManager = taskclusterWorkerManager,
  configPath = 'ci/config/worker-pool/relops/win2019.yaml',
  workerPoolId = 'relops/win2019')