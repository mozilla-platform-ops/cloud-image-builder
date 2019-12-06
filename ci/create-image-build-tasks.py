import os
import slugid
import taskcluster
import yaml
from datetime import datetime, timedelta


workerManager = taskcluster.WorkerManager(taskcluster.optionsFromEnvironment())
queue = taskcluster.Queue(taskcluster.optionsFromEnvironment())


def updateWorkerPool(configPath, workerPoolId):
  with open(configPath, 'r') as stream:
    payload = yaml.safe_load(stream)
    try:
      workerManager.workerPool(workerPoolId = workerPoolId)
      print('info: worker pool {} existence detected'.format(workerPoolId))
      workerManager.updateWorkerPool(workerPoolId, payload)
      print('info: worker pool {} updated'.format(workerPoolId))
    except:
      print('info: worker pool {} absence detected'.format(workerPoolId))
      workerManager.createWorkerPool(workerPoolId, payload)
      print('info: worker pool {} created'.format(workerPoolId))


def createTask(taskId, taskName, taskDescription, provisioner, workerType, commands, artifacts = [], osGroups = [], routes = [], scopes = [], taskGroupId = None):
  payload = {
    'created': '{}Z'.format(datetime.utcnow().isoformat()[:-3]),
    'deadline': '{}Z'.format((datetime.utcnow() + timedelta(days=3)).isoformat()[:-3]),
    'provisionerId': provisioner,
    'workerType': workerType,
    'priority': 'highest',
    'routes': routes,
    'scopes': scopes,
    'payload': {
      'maxRunTime': 3600,
      'command': commands,
      'artifacts': artifacts,
      'osGroups': osGroups
    },
    'metadata': {
      'name': taskName,
      'description': taskDescription,
      'owner': 'grenade@mozilla.com',
      'source': 'https://github.com/grenade/cloud-image-builder' #.format(GIST_USER, GIST_SHA)
    }
  }
  if taskGroupId is not None:
    payload['taskGroupId'] = taskGroupId
  print('info: payload for task {} created'.format(taskId))
  queue.createTask(taskId, payload)


updateWorkerPool('ci/config/worker-pool.yaml', 'relops/win2019')

taskGroupId = slugid.nice()
createTask(
  taskId = taskGroupId,
  taskName = 'build-cloud-images',
  taskDescription = 'this task only serves as a task grouping. it does no task work',
  provisioner = 'relops',
  workerType = 'win2019',
  commands = []
)
for platform in ['azure']:
  for key in ['win10-64', 'win10-64-gpu', 'win7-32', 'win7-32-gpu', 'win2012', 'win2019']:
    createTask(
      taskId = slugid.nice(),
      taskName = 'build-{}-{}'.format(platform, key),
      taskDescription = 'build {} {} image from iso file'.format(platform, key),
      provisioner = 'relops',
      workerType = 'win2019',
      artifacts = [
        {
          'type': 'file',
          'name': 'public/unattend.xml',
          'path': 'cloud-image-builder/unattend.xml'
        }
      ],
      commands = [
        'git clone https://github.com/grenade/cloud-image-builder.git',
        'cd cloud-image-builder',
        'powershell -File build-{}-image.ps1 {}-{}'.format(platform, key, platform)
      ],
      scopes = [
        'generic-worker:os-group:relops/win2019/Administrators',
        'generic-worker:run-as-administrator:relops/win2019'
      ],
      routes = [
        'index.project.relops.cloud-image-builder.{}.{}.revision.{}'.format(platform, key, os.getenv('TRAVIS_COMMIT')),
        'index.project.relops.cloud-image-builder.{}.{}.latest'.format(platform, key)
      ],
      taskGroupId = taskGroupId
    )
