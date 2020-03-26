import json
import os
import re
import requests
import taskcluster
import urllib.error
import urllib.request
import yaml
from azure.common.credentials import ServicePrincipalCredentials
from azure.mgmt.compute import ComputeManagementClient

from cachetools import cached, TTLCache
cache = TTLCache(maxsize=100, ttl=300)


@cached(cache)
def get_commit(org, repo, revision):
  try:
    response = urllib.request.urlopen('https://api.github.com/repos/{}/{}/commits/{}'.format(org, repo, revision))
  except urllib.error.HTTPError as e:
    print('error code {} on commit lookup for {}/{}/{}'.format(e.code, org, repo, revision))
    print(e.read())
    exit(123 if e.code == 403 else 1)
  return json.loads(response.read().decode())


secretsClient = taskcluster.Secrets({ 'rootUrl': os.environ['TASKCLUSTER_PROXY_URL'] })
secret = secretsClient.get('project/relops/image-builder/dev')['secret']

platform = os.getenv('platform')
group = os.getenv('group')
key = os.getenv('key')

print('platform: {}'.format(platform))
print('group: {}'.format(group))
print('key: {}'.format(key))

if platform == 'azure':
  azureComputeManagementClient = ComputeManagementClient(
    ServicePrincipalCredentials(
      client_id = secret['azure']['id'],
      secret = secret['azure']['key'],
      tenant = secret['azure']['account']),
    secret['azure']['subscription'])

  pattern = re.compile('^{}-{}-([a-z0-9]{{7}})-([a-z0-9]{{7}})$'.format(group.replace('rg-', ''), key))
  images = [x for x in azureComputeManagementClient.images.list_by_resource_group(group) if pattern.match(x.name)]
  for image in images:
    diskImageRevision = pattern.search(image.name).group(1)
    print('image: {}, has disk image revision: {} (mozilla-platform-ops/cloud-image-builder)'.format(image.name, diskImageRevision))
    diskImageCommit = get_commit('mozilla-platform-ops', 'cloud-image-builder', diskImageRevision)
    configUrl = 'https://raw.githubusercontent.com/mozilla-platform-ops/cloud-image-builder/{}/config/{}.yaml'.format(diskImageRevision, key)
    if image.tags:
      print('image has tags: {}'.format(', '.join(['%s:: %s' % (k, v) for (k, v) in image.tags.items()])))
      print('updating tags...')
    else:
      print('image has no tags. creating tags...')
    if requests.head(configUrl).status_code == requests.codes.ok:
      config = yaml.safe_load(urllib.request.urlopen(configUrl).read().decode())
      configTargetGroup = next((t for t in config['target'] if t['group'] == group), None)
      org = next((tag for tag in configTargetGroup['tag'] if tag['name'] == 'sourceOrganisation'), { 'value': '' })['value']
      repo = next((tag for tag in configTargetGroup['tag'] if tag['name'] == 'sourceRepository'), { 'value': '' })['value']
      machineImageRevision = pattern.search(image.name).group(2)
      print('image: {}, has machine image revision: {} ({}/{})'.format(image.name, machineImageRevision, org, repo))
      machineImageCommit = get_commit(org, repo, machineImageRevision)
      image.tags = {
        'diskImageCommitDate': diskImageCommit['commit']['committer']['date'][0:10],
        'diskImageCommitTime': diskImageCommit['commit']['committer']['date'],
        'diskImageCommitSha': diskImageCommit['sha'],
        'diskImageCommitMessage': diskImageCommit['commit']['message'],
        'machineImageCommitDate': machineImageCommit['commit']['committer']['date'][0:10],
        'machineImageCommitTime': machineImageCommit['commit']['committer']['date'],
        'machineImageCommitSha': machineImageCommit['sha'],
        'machineImageCommitMessage': machineImageCommit['commit']['message'],
        'machineImageCommitOrg': org,
        'machineImageCommitRepo': repo,
        'isoName': os.path.basename(config['iso']['source']['key']),
        'isoIndex': config['iso']['wimindex'],
        'os': config['image']['os'],
        'edition': config['image']['edition'],
        'language': config['image']['language'],
        'architecture': config['image']['architecture']
      }
    else:
      image.tags = {
        'diskImageCommitDate': diskImageCommit['commit']['committer']['date'][0:10],
        'diskImageCommitTime': diskImageCommit['commit']['committer']['date'],
        'diskImageCommitSha': diskImageCommit['sha'],
        'diskImageCommitMessage': diskImageCommit['commit']['message']
      }
    azureComputeManagementClient.images.create_or_update(group, image.name, image)
    print('image tags updated')
    print(', '.join(['%s:: %s' % (k, v) for (k, v) in image.tags.items()]))

  snapshots = [x for x in azureComputeManagementClient.snapshots.list_by_resource_group(group) if pattern.match(x.name)]
  for snapshot in snapshots:
    diskImageRevision = pattern.search(snapshot.name).group(1)
    print('snapshot: {}, has disk image revision: {} (mozilla-platform-ops/cloud-image-builder)'.format(snapshot.name, diskImageRevision))
    diskImageCommit = get_commit('mozilla-platform-ops', 'cloud-image-builder', diskImageRevision)
    configUrl = 'https://raw.githubusercontent.com/mozilla-platform-ops/cloud-image-builder/{}/config/{}.yaml'.format(diskImageRevision, key)
    if snapshot.tags:
      print('snapshot has tags: {}'.format(', '.join(['%s:: %s' % (k, v) for (k, v) in snapshot.tags.items()])))
      print('updating tags...')
    else:
      print('snapshot has no tags. creating tags...')
    if requests.head(configUrl).status_code == requests.codes.ok:
      config = yaml.safe_load(urllib.request.urlopen(configUrl).read().decode())
      configTargetGroup = next((t for t in config['target'] if t['group'] == group), None)
      org = next((tag for tag in configTargetGroup['tag'] if tag['name'] == 'sourceOrganisation'), { 'value': '' })['value']
      repo = next((tag for tag in configTargetGroup['tag'] if tag['name'] == 'sourceRepository'), { 'value': '' })['value']
      machineImageRevision = pattern.search(snapshot.name).group(2)
      print('snapshot: {}, has machine image revision: {} ({}/{})'.format(snapshot.name, machineImageRevision, org, repo))
      machineImageCommit = get_commit(org, repo, machineImageRevision)
      snapshot.tags = {
        'diskImageCommitDate': diskImageCommit['commit']['committer']['date'][0:10],
        'diskImageCommitTime': diskImageCommit['commit']['committer']['date'],
        'diskImageCommitSha': diskImageCommit['sha'],
        'diskImageCommitMessage': diskImageCommit['commit']['message'],
        'machineImageCommitDate': machineImageCommit['commit']['committer']['date'][0:10],
        'machineImageCommitTime': machineImageCommit['commit']['committer']['date'],
        'machineImageCommitSha': machineImageCommit['sha'],
        'machineImageCommitMessage': machineImageCommit['commit']['message'],
        'machineImageCommitOrg': org,
        'machineImageCommitRepo': repo,
        'isoName': os.path.basename(config['iso']['source']['key']),
        'isoIndex': config['iso']['wimindex'],
        'os': config['image']['os'],
        'edition': config['image']['edition'],
        'language': config['image']['language'],
        'architecture': config['image']['architecture']
      }
    else:
      snapshot.tags = {
        'diskImageCommitDate': diskImageCommit['commit']['committer']['date'][0:10],
        'diskImageCommitTime': diskImageCommit['commit']['committer']['date'],
        'diskImageCommitSha': diskImageCommit['sha'],
        'diskImageCommitMessage': diskImageCommit['commit']['message']
      }
    azureComputeManagementClient.snapshots.create_or_update(group, snapshot.name, snapshot)
    print('snapshot tags updated')
    print(', '.join(['%s:: %s' % (k, v) for (k, v) in snapshot.tags.items()]))
else:
  print('skipped image and snapshot tagging. not implemented for platform: {}'.format(platform))