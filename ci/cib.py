import gzip
import json
import urllib.request
import yaml
from datetime import datetime, timedelta


def updateWorkerPool(workerManager, configPath, workerPoolId):
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


def createTask(queue, taskId, taskName, taskDescription, provisioner, workerType, commands, env = None, image = None, priority = 'low', retries = 0, retriggerOnExitCodes = [], dependencies = [], maxRunMinutes = 10, features = {}, artifacts = [], osGroups = [], routes = [], scopes = [], taskGroupId = None):
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
      'artifacts': artifacts if workerType.startswith('win') else { artifact.name: { 'type': artifact.type, 'path': artifact.path } for artifact in artifacts },
      'features': features
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
  if env is not None:
    payload['payload']['env'] = env
  if image is not None:
    payload['payload']['image'] = image
  if osGroups:
    payload['payload']['osGroups'] = osGroups
  if retriggerOnExitCodes and retries > 0:
    payload['retries'] = retries
    payload['payload']['onExitStatus'] = {
      'retry': retriggerOnExitCodes
    }

  queue.createTask(taskId, payload)
  print('info: task {} ({}: {}), created with priority: {}'.format(taskId, taskName, taskDescription, priority))


def imageManifestHasChanged(platform, key, currentRevision):
  lastRevision = json.loads(gzip.decompress(urllib.request.urlopen('https://firefox-ci-tc.services.mozilla.com/api/index/v1/task/project.relops.cloud-image-builder.{}.{}.latest/artifacts/public/image-bucket-resource.json'.format(platform, key)).read()).decode('utf-8-sig'))['build']['revision']
  currentManifest = urllib.request.urlopen('https://raw.githubusercontent.com/grenade/cloud-image-builder/{}/config/{}-{}.yaml'.format(currentRevision, key, platform)).read().decode()
  lastManifest = urllib.request.urlopen('https://raw.githubusercontent.com/grenade/cloud-image-builder/{}/config/{}-{}.yaml'.format(lastRevision, key, platform)).read().decode()
  if currentManifest == lastManifest:
    print('info: no change detected for {}-{} manifest between last image build in revision: {} and current revision: {}'.format(key, platform, lastRevision[0:7], currentRevision[0:7]))
  else:
    print('info: change detected for {}-{} manifest between last image build in revision: {} and current revision: {}'.format(key, platform, lastRevision[0:7], currentRevision[0:7]))
  return currentManifest != lastManifest


def machineImageExists(taskclusterIndex, platformClient, platform, region, group, key):
  artifact = taskclusterIndex.findArtifactFromTask(
    'project.relops.cloud-image-builder.{}.{}.latest'.format(platform, key.replace('-{}'.format(platform), '')),
    'public/image-bucket-resource.json')
  print(artifact)

  if platform == 'azure':
    targetImageName = '{}-{}-{}'.format(group.replace('rg-', ''), key.replace('-{}'.format(platform), ''), artifact['build']['revision'][0:7])

  print(targetImageName)
  location = region.replace(' ', '').lower()
  for publisher in platformClient.virtual_machine_images.list_publishers(location):
    for offer in platformClient.virtual_machine_images.list_offers(location, publisher.name):
      for sku in platformClient.virtual_machine_images.list_skus(location, publisher.name, offer.name):
        for version in platformClient.virtual_machine_images.list(location, publisher.name, offer.name, sku.name):
          image = compute_client.virtual_machine_images.get(location, publisher.name, offer.name, sku.name, version.name)
          print('location: {}, publisher: {}, offer: {}, sku: {}, version: {}, image: {}'.format(location, publisher.name, offer.name, sku.name, version.name, image.name))
  return True
