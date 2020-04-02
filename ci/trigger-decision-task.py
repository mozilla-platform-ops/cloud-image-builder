import json
import os
import slugid
import taskcluster
import urllib.request
from cib import createTask, updateRole, updateWorkerPool


taskclusterAuth = taskcluster.Auth(taskcluster.optionsFromEnvironment())
taskclusterWorkerManager = taskcluster.WorkerManager(taskcluster.optionsFromEnvironment())
queue = taskcluster.Queue(taskcluster.optionsFromEnvironment())
commit = json.loads(urllib.request.urlopen(urllib.request.Request('https://api.github.com/repos/mozilla-platform-ops/cloud-image-builder/commits/{}'.format(os.getenv('TRAVIS_COMMIT')), None, { 'User-Agent' : 'Mozilla/5.0' })).read().decode())['commit']

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

createTask(
  queue = queue,
  image = 'python',
  taskId = slugid.nice(),
  taskName = '00 :: decision task',
  taskDescription = 'determine which windows cloud images should be built, where they should be deployed and trigger appropriate build tasks for the same',
  provisioner = 'relops',
  workerType = 'decision',
  features = {
    'taskclusterProxy': True
  },
  env = {
    'GITHUB_HEAD_SHA': os.getenv('TRAVIS_COMMIT')
  },
  commands = [
    '/bin/bash',
    '--login',
    '-c',
    'git clone https://github.com/mozilla-platform-ops/cloud-image-builder.git && pip install azure boto3 pyyaml slugid taskcluster urllib3 && cd cloud-image-builder && git reset --hard {} && python ci/{}.py'.format(os.getenv('TRAVIS_COMMIT'), 'pool-deploy' if commit['message'].startswith('pool-deploy') else 'create-image-build-tasks')
  ],
  scopes = [
    'generic-worker:os-group:relops/win2019/Administrators',
    'generic-worker:run-as-administrator:relops/*',
    'queue:create-task:highest:relops/*',
    'queue:create-task:very-high:relops/*',
    'queue:create-task:high:relops/*',
    'queue:create-task:medium:relops/*',
    'queue:create-task:low:relops/*',
    'queue:route:index.project.relops.cloud-image-builder.*',
    'queue:scheduler-id:-',
    'worker-manager:manage-worker-pool:gecko-1/win*',
    'worker-manager:manage-worker-pool:gecko-3/win*',
    'worker-manager:manage-worker-pool:gecko-t/win*',
    'worker-manager:manage-worker-pool:mpd001-1/win*',
    'worker-manager:manage-worker-pool:mpd001-3/win*',
    'worker-manager:manage-worker-pool:relops/win*',
    'worker-manager:provider:aws',
    'worker-manager:provider:azure',
    'secrets:get:project/relops/image-builder/dev'
  ]
)
