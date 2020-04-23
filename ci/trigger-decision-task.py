import json
import os
import slugid
import taskcluster
import urllib.request
from cib import createTask

createTask(
  queue = taskcluster.Queue(taskcluster.optionsFromEnvironment()),
  image = 'python',
  taskId = slugid.nice(),
  taskName = '00 :: create maintenance and image build tasks',
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
    'git clone https://github.com/mozilla-platform-ops/cloud-image-builder.git && cd cloud-image-builder && git reset --hard {} && pip install azure-mgmt-compute boto3 pyyaml slugid taskcluster urllib3 && python ci/create-image-build-tasks.py'.format(os.getenv('TRAVIS_COMMIT'))
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
    'queue:scheduler-id:taskcluster-github',
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
