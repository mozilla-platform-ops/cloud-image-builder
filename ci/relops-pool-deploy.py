import taskcluster
from cib import updateRole, updateWorkerPool

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