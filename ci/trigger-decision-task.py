import os
import slugid
import taskcluster
from cib import createTask, updateWorkerPool


workerManager = taskcluster.WorkerManager(taskcluster.optionsFromEnvironment())
queue = taskcluster.Queue(taskcluster.optionsFromEnvironment())


updateWorkerPool(
  workerManager = workerManager,
  configPath = 'ci/config/worker-pool/relops/decision.yaml',
  workerPoolId = 'relops/decision')
updateWorkerPool(
  workerManager = workerManager,
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
  env = {
    'GITHUB_HEAD_SHA': os.getenv('TRAVIS_COMMIT')
  },
  commands = [
    '/bin/bash',
    '--login',
    '-c',
    'git clone https://github.com/grenade/cloud-image-builder.git && pip install azure boto3 pyyaml slugid taskcluster urllib3 && python cloud-image-builder/ci/create-image-build-tasks.py'
  ],
  scopes = [
    'generic-worker:os-group:relops/win2019/Administrators',
    'generic-worker:run-as-administrator:relops/win2019',
    'secrets:get:project/relops/image-builder/dev',
    'queue:route:index.project.relops.cloud-image-builder.*',
    'queue:scheduler-id:-',
    'queue:create-task:highest:relops/win2019',
    'queue:create-task:very-high:relops/win2019',
    'queue:create-task:high:relops/win2019',
    'queue:create-task:medium:relops/win2019',
    'queue:create-task:low:relops/win2019'
  ]
)
