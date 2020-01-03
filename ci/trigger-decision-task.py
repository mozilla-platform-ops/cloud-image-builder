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
  ]
)
