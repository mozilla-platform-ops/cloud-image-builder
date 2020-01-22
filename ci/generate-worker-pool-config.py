import json
import os
import re
import taskcluster
import urllib.request
import yaml
from azure.common.credentials import ServicePrincipalCredentials
from azure.mgmt.compute import ComputeManagementClient

secretsClient = taskcluster.Secrets({ 'rootUrl': os.environ['TASKCLUSTER_PROXY_URL'] })
secret = secretsClient.get('project/relops/image-builder/dev')['secret']

enabledLocations = ['centralus']

azureComputeManagementClient = ComputeManagementClient(
  ServicePrincipalCredentials(
    client_id = secret['azure']['id'],
    secret = secret['azure']['key'],
    tenant = secret['azure']['account']),
  secret['azure']['subscription'])


def getLatestImageId(resourceGroup, key):
  pattern = re.compile('^{}-{}-([a-z0-9]{{7}})$'.format(resourceGroup.replace('rg-', ''), key))
  images = sorted([x for x in azureComputeManagementClient.images.list_by_resource_group(resourceGroup) if pattern.match(x.name)], key = lambda i: i.tags['diskImageCommitTime'], reverse=True)
  print('found {} {} images in {}'.format(len(images), key, resourceGroup))
  return images[0].id if len(images) > 0 else None

commitSha = os.getenv('GITHUB_HEAD_SHA')
platform = os.getenv('platform')
key = os.getenv('key')
subscriptionId = 'dd0d4271-9b26-4c37-a025-1284a43a4385'
config = yaml.safe_load(urllib.request.urlopen('https://raw.githubusercontent.com/grenade/cloud-image-builder/{}/config/{}-{}.yaml'.format(commitSha, key, platform)).read().decode())
workerPool = {
  'minCapacity': 0,
  'maxCapacity': 0,
  'launchConfigs': list(filter(lambda x: x['storageProfile']['imageReference']['id'] is not None and x['location'] in enabledLocations, map(lambda x: {
    'location': x['region'].lower().replace(' ', ''),
    'capacityPerInstance': 1,
    'subnetId': '/subscriptions/{}/resourceGroups/{}/providers/Microsoft.Network/virtualNetworks/{}/subnets/sn-central-us-{}'.format(subscriptionId, x['group'], x['group'].replace('rg-', 'vn-'), x['group'].replace('rg-', 'sn-')),
    'hardwareProfile': {
      'vmSize': x['machine']['format'].format(x['machine']['cpu'])
    },
    'storageProfile': {
      'imageReference': {
        'id': getLatestImageId(x['group'], key)
      },
      'osDisk': {
        'caching': 'ReadWrite',
        'createOption': 'FromImage',
        'managedDisk': {
          'storageAccountType': 'StandardSSD_LRS' if x['disk'][0]['variant'] == 'ssd' else 'Standard_LRS'
        },
        'osType': 'Windows'
      },
      'dataDisks': [
        {
          'lun': 0,
          'caching': 'ReadWrite',
          'createOption': 'Empty',
          'diskSizeGB': 128,
          'managedDisk': {
            'storageAccountType': 'StandardSSD_LRS' if x['disk'][0]['variant'] == 'ssd' else 'Standard_LRS'
          }
        },
        {
          'lun': 1,
          'caching': 'ReadWrite',
          'createOption': 'Empty',
          'diskSizeGB': 128,
          'managedDisk': {
            'storageAccountType': 'StandardSSD_LRS' if x['disk'][0]['variant'] == 'ssd' else 'Standard_LRS'
          }
        }
      ]
    },
    'tags': {
      'workerType': 'gecko-1-b-win2012-azure' if key == 'win2012' else 'relops-win2019-azure' if key == 'win2019' else 'gecko-t-{}-{}'.format(key, platform),
      'sourceOrganisation': 'mozilla-releng',
      'sourceRepository': 'OpenCloudConfig',
      'sourceRevision': 'azure'
    },
    'workerConfig': {}
  }, config['target'])))
}

with open('../{}-{}.json'.format(platform, key), 'w') as file:
  json.dump(workerPool, file, indent = 2, sort_keys = True)