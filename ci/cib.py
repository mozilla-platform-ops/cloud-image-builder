import gzip
import json
import os
import urllib.request
import yaml
from datetime import datetime, timedelta

from cachetools import cached, TTLCache
cache = TTLCache(maxsize=100, ttl=300)

@cached(cache)
def getConfig(revision, key):
  url = 'https://raw.githubusercontent.com/mozilla-platform-ops/cloud-image-builder/{}/config/{}.yaml'.format(revision, key)
  return yaml.safe_load(urllib.request.urlopen(url).read().decode())


def updateRole(auth, configPath, roleId):
  with open(configPath, 'r') as stream:
    payload = yaml.safe_load(stream)
    role = None
    try:
      role = auth.role(roleId = roleId)
    except:
      print('error:', sys.exc_info()[0])
    if role:
      print('info: role {} existence detected'.format(roleId))
      auth.updateRole(roleId, payload)
      print('info: role {} updated'.format(roleId))
    else:
      print('info: role {} absence detected'.format(roleId))
      auth.createRole(roleId, payload)
      print('info: role {} created'.format(roleId))


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
      'source': 'https://github.com/mozilla-platform-ops/cloud-image-builder'
    },
    'schedulerId': 'taskcluster-github'
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
  try:
    previousRevisionUrl = '{}/api/index/v1/task/project.relops.cloud-image-builder.{}.{}.latest/artifacts/public/image-bucket-resource.json'.format(os.environ['TASKCLUSTER_ROOT_URL'], platform, key)
    previousRevision = json.loads(gzip.decompress(urllib.request.urlopen(previousRevisionUrl).read()).decode('utf-8-sig'))['build']['revision']
    print('debug: previous revision determined as: {}, using: {}'.format(previousRevision, previousRevisionUrl))

    currentConfig = getConfig(currentRevision, key)
    print('debug: current config for: {}, loaded from revision: {}'.format(key, currentRevision[0:7]))

    previousConfig = getConfig(previousRevision, key)
    print('debug: previous config for: {}, loaded from revision: {}'.format(key, previousRevision[0:7]))
  except:
    print('error: failed to load comparable disk image configs for: {}'.format(key))
    return True

  imageConfigUnchanged = True
  isoConfigUnchanged = True
  sharedFilesUnchanged = True

  if currentConfig['image'] == previousConfig['image']:
    print('info: no change detected for image definition in {}.yaml between last image build in revision: {} and current revision: {}'.format(key, previousRevision[0:7], currentRevision[0:7]))
  else:
    imageConfigUnchanged = False
    print('info: change detected for image definition in {}.yaml between last image build in revision: {} and current revision: {}'.format(key, previousRevision[0:7], currentRevision[0:7]))

  if currentConfig['iso'] == previousConfig['iso']:
    print('info: no change detected for iso definition in {}.yaml between last image build in revision: {} and current revision: {}'.format(key, previousRevision[0:7], currentRevision[0:7]))
  else:
    isoConfigUnchanged = False
    print('info: change detected for iso definition in {}.yaml between last image build in revision: {} and current revision: {}'.format(key, previousRevision[0:7], currentRevision[0:7]))

  # todo: parse shared config files for change specific to platform/key
  for sharedFile in ['disable-windows-service', 'drivers', 'packages', 'unattend-commands']:
    currentContents = urllib.request.urlopen('https://raw.githubusercontent.com/mozilla-platform-ops/cloud-image-builder/{}/config/{}.yaml'.format(currentRevision, sharedFile)).read().decode()
    previousContents = urllib.request.urlopen('https://raw.githubusercontent.com/mozilla-platform-ops/cloud-image-builder/{}/config/{}.yaml'.format(previousRevision, sharedFile)).read().decode()
    if currentContents == previousContents:
      print('info: no change detected in {}.yaml between last image build in revision: {} and current revision: {}'.format(sharedFile, previousRevision[0:7], currentRevision[0:7]))
    else:
      sharedFilesUnchanged = False
      print('info: change detected for {}.yaml between last image build in revision: {} and current revision: {}'.format(sharedFile, previousRevision[0:7], currentRevision[0:7]))

  return not (imageConfigUnchanged and isoConfigUnchanged and sharedFilesUnchanged)


def machineImageManifestHasChanged(platform, key, currentRevision, group):
  try:
    previousRevisionUrl = '{}/api/index/v1/task/project.relops.cloud-image-builder.{}.{}.latest/artifacts/public/image-bucket-resource.json'.format(os.environ['TASKCLUSTER_ROOT_URL'], platform, key)
    previousRevision = json.loads(gzip.decompress(urllib.request.urlopen(previousRevisionUrl).read()).decode('utf-8-sig'))['build']['revision']
    print('debug: previous revision determined as: {}, using: {}'.format(previousRevision, previousRevisionUrl))

    currentConfig = getConfig(currentRevision, key)
    print('debug: current config for: {}, loaded from revision: {}'.format(key, currentRevision[0:7]))

    previousConfig = getConfig(previousRevision, key)
    print('debug: previous config for: {}, loaded from revision: {}'.format(key, previousRevision[0:7]))
  except:
    print('error: failed to load comparable disk image configs for: {}'.format(key))
    return True

  targetBootstrapUnchanged = True
  targetTagsUnchanged = True
  currentTargetGroupConfig = next((t for t in currentConfig['target'] if t['group'] == group), None)
  previousTargetGroupConfig = next((t for t in previousConfig['target'] if t['group'] == group), None)

  if previousTargetGroupConfig is None and currentTargetGroupConfig is not None:
    print('info: new target group {} detected, in {}.yaml since last image build in revision: {} and current revision: {}'.format(group, key, previousRevision[0:7], currentRevision[0:7]))
    return True

  if 'bootstrap' in currentTargetGroupConfig and 'bootstrap' not in previousTargetGroupConfig:
    targetBootstrapUnchanged = False
    print('info: change detected in target group {}. new bootstrap execution commands definition in {}.yaml between last image build in revision: {} and current revision: {}'.format(group, key, previousRevision[0:7], currentRevision[0:7]))
  elif 'bootstrap' not in currentTargetGroupConfig and 'bootstrap' in previousTargetGroupConfig:
    targetBootstrapUnchanged = False
    print('info: change detected in target group {}. removed bootstrap execution commands definition in {}.yaml between last image build in revision: {} and current revision: {}'.format(group, key, previousRevision[0:7], currentRevision[0:7]))
  elif 'bootstrap' in currentTargetGroupConfig and 'bootstrap' in previousTargetGroupConfig and currentTargetGroupConfig['bootstrap'] != previousTargetGroupConfig['bootstrap']:
    targetBootstrapUnchanged = False
    print('info: change detected in target group {}, for bootstrap execution commands definition in {}.yaml between last image build in revision: {} and current revision: {}'.format(group, key, previousRevision[0:7], currentRevision[0:7]))
  else:
    print('info: no change detected in target group {}, for bootstrap execution commands definition in {}.yaml between last image build in revision: {} and current revision: {}'.format(group, key, previousRevision[0:7], currentRevision[0:7]))

  for tagKey in ['workerType', 'sourceOrganisation', 'sourceRepository', 'sourceRevision', 'sourceScript', 'deploymentId']:
    currentTagValue = next((tag for tag in currentTargetGroupConfig['tag'] if tag['name'] == tagKey), { 'value': '' })['value']
    previousTagValue = next((tag for tag in previousTargetGroupConfig['tag'] if tag['name'] == tagKey), { 'value': '' })['value']
    if currentTagValue == previousTagValue:
      print('debug: no change detected for tag {}, with value "{}", in target group {}, in {}.yaml between last image build in revision: {} and current revision: {}'.format(tagKey, currentTagValue, group, key, previousRevision[0:7], currentRevision[0:7]))
    else:
      targetTagsUnchanged = False
      print('info: change detected for tag {}, with previous value "{}", and new value "{}", in target group {}, in {}.yaml between last image build in revision: {} and current revision: {}'.format(tagKey, previousTagValue, currentTagValue, group, key, previousRevision[0:7], currentRevision[0:7]))

  return not (targetBootstrapUnchanged and targetTagsUnchanged)


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
  #elif platform == 'amazon':
  return image is not None
