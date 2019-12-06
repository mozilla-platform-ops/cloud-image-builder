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

      'generic-worker:os-group:aws-provisioner-v1/relops-image-builder/Administrators',
      'generic-worker:run-as-administrator:aws-provisioner-v1/relops-image-builder',

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
      #'features': [],
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
  taskName = 'hello-from-task-group',
  taskDescription = 'say hello from the task group',
  provisioner = 'relops',
  workerType = 'win2019',
  commands = ['echo "hello from task group']
)
for key in ['gecko-t/win10-64', 'gecko-t/win10-64-gpu', 'gecko-t/win7-32', 'gecko-t/win7-32-gpu', 'gecko-1/win2012', 'gecko-3/win2012', 'relops/win2019']:
  createTask(
    taskId = slugid.nice(),
    taskName = 'hello-from-{}'.format(key),
    taskDescription = 'say hello from {}'.format(key),
    provisioner = 'relops',
    workerType = 'win2019',
    artifacts = [
      {
        'type': 'file',
        'name': 'public/psv.ps1',
        'path': 'psv.ps1',
      },
      {
        'type': 'file',
        'name': 'public/git-ref.ps1',
        'path': 'git-ref.ps1',
      }
    ],
    commands = [
      'dir',
      'echo $PSVersionTable.PSVersion > psv.ps1',
      'powershell -File .\\psv.ps1',
      'git clone https://github.com/grenade/cloud-image-builder.git',
      'cd cloud-image-builder',
      'echo $revision = $(& git @("rev-parse", "HEAD")); > ..\\git-ref.ps1',
      'powershell -File ..\\git-ref.ps1'
    ],
    scopes = [
      'generic-worker:os-group:relops/win2019/Administrators',
      'generic-worker:run-as-administrator:relops/win2019'
    ],
    routes = [
      'index.project.relops.cloud-image-builder.{}.revision.{}'.format(key.replace('/', '.'), os.getenv('TRAVIS_COMMIT')),
      'index.project.relops.cloud-image-builder.{}.latest'.format(key.replace('/', '.'))
    ],
    
    taskGroupId = taskGroupId
  )