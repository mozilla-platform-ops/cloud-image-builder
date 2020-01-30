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
      'artifacts': artifacts if workerType.startswith('win') else { artifact['name']: { 'type': artifact['type'], 'path': artifact['path'] } for artifact in artifacts },
      'features': features
    },
    'metadata': {
      'name': taskName,
      'description': taskDescription,
      'owner': 'grenade@mozilla.com',
      'source': 'https://github.com/grenade/cloud-image-builder'
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


def diskImageManifestHasChanged(platform, key, currentRevision):
  lastRevision = json.loads(gzip.decompress(urllib.request.urlopen('https://firefox-ci-tc.services.mozilla.com/api/index/v1/task/project.relops.cloud-image-builder.{}.{}.latest/artifacts/public/image-bucket-resource.json'.format(platform, key)).read()).decode('utf-8-sig'))['build']['revision']

  imageConfigUnchanged = True
  isoConfigUnchanged = True
  sharedFilesUnchanged = True

  configFile = '{}-{}'.format(key, platform)
  currentConfig = yaml.safe_load(urllib.request.urlopen('https://raw.githubusercontent.com/grenade/cloud-image-builder/{}/config/{}.yaml'.format(currentRevision, configFile)).read().decode())
  previousConfig = yaml.safe_load(urllib.request.urlopen('https://raw.githubusercontent.com/grenade/cloud-image-builder/{}/config/{}.yaml'.format(lastRevision, configFile)).read().decode())

  if currentConfig['image'] == previousConfig['image']:
    print('info: no change detected for image definition in {}.yaml between last image build in revision: {} and current revision: {}'.format(configFile, lastRevision[0:7], currentRevision[0:7]))
  else:
    imageConfigUnchanged = False
    print('info: change detected for image definition in {}.yaml between last image build in revision: {} and current revision: {}'.format(configFile, lastRevision[0:7], currentRevision[0:7]))

  if currentConfig['iso'] == previousConfig['iso']:
    print('info: no change detected for iso definition in {}.yaml between last image build in revision: {} and current revision: {}'.format(configFile, lastRevision[0:7], currentRevision[0:7]))
  else:
    isoConfigUnchanged = False
    print('info: change detected for iso definition in {}.yaml between last image build in revision: {} and current revision: {}'.format(configFile, lastRevision[0:7], currentRevision[0:7]))

  # todo: parse shared config files for change specific to platform/key
  for sharedFile in ['disable-windows-service', 'drivers', 'packages', 'unattend-commands']:
    currentContents = urllib.request.urlopen('https://raw.githubusercontent.com/grenade/cloud-image-builder/{}/config/{}.yaml'.format(currentRevision, sharedFile)).read().decode()
    previousContents = urllib.request.urlopen('https://raw.githubusercontent.com/grenade/cloud-image-builder/{}/config/{}.yaml'.format(lastRevision, sharedFile)).read().decode()
    if currentContents == previousContents:
      print('info: no change detected in {}.yaml between last image build in revision: {} and current revision: {}'.format(sharedFile, lastRevision[0:7], currentRevision[0:7]))
    else:
      sharedFilesUnchanged = False
      print('info: change detected for {}.yaml between last image build in revision: {} and current revision: {}'.format(sharedFile, lastRevision[0:7], currentRevision[0:7]))

  return not (imageConfigUnchanged and isoConfigUnchanged and sharedFilesUnchanged)


def machineImageManifestHasChanged(platform, key, currentRevision, group):
  lastRevision = json.loads(gzip.decompress(urllib.request.urlopen('https://firefox-ci-tc.services.mozilla.com/api/index/v1/task/project.relops.cloud-image-builder.{}.{}.latest/artifacts/public/image-bucket-resource.json'.format(platform, key)).read()).decode('utf-8-sig'))['build']['revision']

  targetTagsUnchanged = True

  configFile = '{}-{}'.format(key, platform)
  currentConfig = yaml.safe_load(urllib.request.urlopen('https://raw.githubusercontent.com/grenade/cloud-image-builder/{}/config/{}.yaml'.format(currentRevision, configFile)).read().decode())
  previousConfig = yaml.safe_load(urllib.request.urlopen('https://raw.githubusercontent.com/grenade/cloud-image-builder/{}/config/{}.yaml'.format(lastRevision, configFile)).read().decode())

  currentTargetGroupConfig = next((t for t in currentConfig['target'] if t['group'] == group), None)
  previousTargetGroupConfig = next((t for t in previousConfig['target'] if t['group'] == group), None)

  if previousTargetGroupConfig is None and currentTargetGroupConfig is not None:
    print('info: new target group {} detected, in {}.yaml since last image build in revision: {} and current revision: {}'.format(group, configFile, lastRevision[0:7], currentRevision[0:7]))
    return True

  for tagKey in ['workerType', 'sourceOrganisation', 'sourceRepository', 'sourceRevision']:
    currentTagValue = next((tag for tag in currentTargetGroupConfig['tag'] if tag['name'] == tagKey), { 'value': '' })['value']
    previousTagValue = next((tag for tag in previousTargetGroupConfig['tag'] if tag['name'] == tagKey), { 'value': '' })['value']
    if currentTagValue == previousTagValue:
      print('debug: no change detected for tag {}, with value "{}", in target group {}, in {}.yaml between last image build in revision: {} and current revision: {}'.format(tagKey, currentTagValue, group, configFile, lastRevision[0:7], currentRevision[0:7]))
    else:
      targetTagsUnchanged = False
      print('info: change detected for tag {}, with previous value "{}", and new value "{}", in target group {}, in {}.yaml between last image build in revision: {} and current revision: {}'.format(tagKey, previousTagValue, currentTagValue, group, configFile, lastRevision[0:7], currentRevision[0:7]))
  return not targetTagsUnchanged


def machineImageExists(taskclusterIndex, platformClient, platform, group, key):
  artifact = taskclusterIndex.findArtifactFromTask(
    'project.relops.cloud-image-builder.{}.{}.latest'.format(platform, key.replace('-{}'.format(platform), '')),
    'public/image-bucket-resource.json')
  image = None
  if platform == 'azure':
    imageName = '{}-{}-{}'.format(group.replace('rg-', ''), key.replace('-{}'.format(platform), ''), artifact['build']['revision'][0:7])
    try:
      image = platformClient.images.get(group, imageName)
      print('{} machine image: {} found with id: {}'.format(platform, imageName, image.id))
    except:
      image = None
      print('{} machine image: {} not found'.format(platform, imageName))
  return image is not None
