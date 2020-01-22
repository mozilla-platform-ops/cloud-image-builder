
import json
import os
import urllib.request
import yaml


def getLatestImageId(resourceGroup, key):
  pattern = re.compile('^{}-{}-([a-z0-9]{{7}})$'.format(resourceGroup.replace('rg-', ''), key))
  images = sorted([x for x in azureComputeManagementClient.images.list_by_resource_group(group) if pattern.match(x.name)], key = lambda i: i.tags['diskImageCommitTime'], reverse=True)
  print('found {} {} images in {}'.format(len(images), key, resourceGroup))
  return images[0].id

commitSha = os.getenv('GITHUB_HEAD_SHA')
platform = os.getenv('platform')
key = os.getenv('key')
subscriptionId = 'dd0d4271-9b26-4c37-a025-1284a43a4385'
config = yaml.safe_load(urllib.request.urlopen('https://raw.githubusercontent.com/grenade/cloud-image-builder/{}/config/{}-{}.yaml'.format(commitSha, key, platform)).read().decode())
workerPool = {
  'minCapacity': 0,
  'maxCapacity': 0,
  'launchConfigs': map(lambda x: {
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
    }
  }, config['target'])
}

with open('../{}-{}.json'.format(platform, key), 'w') as file:
  json.dump(workerPool, file)