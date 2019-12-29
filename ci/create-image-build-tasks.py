import filecmp
import gzip
import json
import os
import slugid
import taskcluster
import urllib.request
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


def createTask(taskId, taskName, taskDescription, provisioner, workerType, commands, priority = 'normal', retries = 1, retriggerOnExitCodes = [], dependencies = [], maxRunMinutes = 10, features = {}, artifacts = [], osGroups = [], routes = [], scopes = [], taskGroupId = None):
  payload = {
    'created': '{}Z'.format(datetime.utcnow().isoformat()[:-3]),
    'deadline': '{}Z'.format((datetime.utcnow() + timedelta(days = 3)).isoformat()[:-3]),
    'dependencies': dependencies,
    'provisionerId': provisioner,
    'workerType': workerType,
    'priority': priority,
    'routes': routes,
    'scopes': scopes,
    'payload': {
      'maxRunTime': (maxRunMinutes * 60),
      'command': commands,
      'artifacts': artifacts,
      'features': features,
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
  if retriggerOnExitCodes and retries > 1:
    payload['retries'] = retries
    payload['payload']['onExitStatus'] = {
      'retry': retriggerOnExitCodes
    }

  queue.createTask(taskId, payload)
  print('info: task {} ({}: {}), created with priority: {}'.format(taskId, taskName, taskDescription, priority))

def imageManifestHasChanged(platform, key):
  currentRevision = os.getenv('TRAVIS_COMMIT')
  lastRevision = json.loads(gzip.decompress(urllib.request.urlopen('https://firefox-ci-tc.services.mozilla.com/api/index/v1/task/project.relops.cloud-image-builder.{}.{}.latest/artifacts/public/image-bucket-resource.json'.format(platform, key)).read()).decode('utf-8-sig'))['build']['revision']
  currentManifest = urllib.request.urlopen('https://raw.githubusercontent.com/grenade/cloud-image-builder/{}/config/{}-{}.yaml'.format(currentRevision, key, platform)).read().decode()
  lastManifest = urllib.request.urlopen('https://raw.githubusercontent.com/grenade/cloud-image-builder/{}/config/{}-{}.yaml'.format(lastRevision, key, platform)).read().decode()
  if currentManifest == lastManifest:
    print('info: no change detected for {}-{} manifest between last image build in revision: {} and current revision: {}'.format(key, platform, lastRevision[0:7], currentRevision[0:7]))
  else:
    print('info: change detected for {}-{} manifest between last image build in revision: {} and current revision: {}'.format(key, platform, lastRevision[0:7], currentRevision[0:7]))
  return currentManifest != lastManifest


updateWorkerPool('ci/config/worker-pool.yaml', 'relops/win2019')

taskGroupId = slugid.nice()
createTask(
  taskId = taskGroupId,
  taskName = 'a-task-group-placeholder',
  taskDescription = 'this task only serves as a task grouping. it does no task work',
  provisioner = 'relops',
  workerType = 'win2019',
  commands = []
)
for platform in ['azure']:
  for key in ['win10-64', 'win10-64-gpu', 'win7-32', 'win7-32-gpu', 'win2012', 'win2019']:

    if imageManifestHasChanged(platform, key):
      buildTaskId = slugid.nice()
      createTask(
        taskId = buildTaskId,
        taskName = 'build-{}-disk-image-from-{}-iso'.format(platform, key),
        taskDescription = 'build {} {} disk image file from iso file and upload to cloud storage'.format(platform, key),
        maxRunMinutes = 180,
        provisioner = 'relops',
        workerType = 'win2019',
        priority = 'high',
        artifacts = [
          {
            'type': 'file',
            'name': 'public/unattend.xml',
            'path': 'unattend.xml'
          },
          {
            'type': 'file',
            'name': 'public/image-bucket-resource.json',
            'path': 'image-bucket-resource.json'
          }
        ],
        osGroups = [
          'Administrators'
        ],
        features = {
          'taskclusterProxy': True,
          'runAsAdministrator': True
        },
        commands = [
          'git clone https://github.com/grenade/cloud-image-builder.git',
          'cd cloud-image-builder',
          'git reset --hard {}'.format(os.getenv('TRAVIS_COMMIT')),
          'powershell -File build-{}-disk-image.ps1 {}-{}'.format(platform, key, platform)
        ],
        scopes = [
          'generic-worker:os-group:relops/win2019/Administrators',
          'generic-worker:run-as-administrator:relops/win2019',
          'secrets:get:project/relops/image-builder/dev'
        ],
        routes = [
          'index.project.relops.cloud-image-builder.{}.{}.revision.{}'.format(platform, key, os.getenv('TRAVIS_COMMIT')),
          'index.project.relops.cloud-image-builder.{}.{}.latest'.format(platform, key)
        ],
        taskGroupId = taskGroupId
      )
    else:
      buildTaskId = None

    targetConfigPath = 'config/{}-{}.yaml'.format(key, platform)
    with open(targetConfigPath, 'r') as stream:
      targetConfig = yaml.safe_load(stream)
      for target in targetConfig['target']:
        createTask(
          taskId = slugid.nice(),
          taskName = 'convert-{}-{}-disk-image-to-{}-{}-machine-image-and-deploy-to-{}-{}'.format(platform, key, platform, key, platform, target['group']),
          taskDescription = 'convert {} {} disk image to {} {} machine image and deploy to {} {}'.format(platform, key, platform, key, platform, target['group']),
          maxRunMinutes = 180,
          retries = 3,
          retriggerOnExitCodes = [ 123 ],
          dependencies = [] if buildTaskId is None else [ buildTaskId ],
          provisioner = 'relops',
          workerType = 'win2019',
          priority = 'low',
          features = {
            'taskclusterProxy': True
          },
          commands = [
            'git clone https://github.com/grenade/cloud-image-builder.git',
            'cd cloud-image-builder',
            'git reset --hard {}'.format(os.getenv('TRAVIS_COMMIT')),
            'powershell -File build-{}-machine-image.ps1 {}-{} {}'.format(platform, key, platform, target['group'])
          ],
          scopes = [
            'secrets:get:project/relops/image-builder/dev'
          ],
          routes = [
            'index.project.relops.cloud-image-builder.{}.{}.{}.revision.{}'.format(platform, target['group'], key, os.getenv('TRAVIS_COMMIT')),
            'index.project.relops.cloud-image-builder.{}.{}.{}.latest'.format(platform, target['group'], key)
          ],
          taskGroupId = taskGroupId
        )
