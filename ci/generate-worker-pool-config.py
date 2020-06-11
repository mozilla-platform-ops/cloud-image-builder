import json
import os
import re
import string
import taskcluster
import urllib.request
import yaml
from azure.common.credentials import ServicePrincipalCredentials
from azure.mgmt.compute import ComputeManagementClient
from cib import updateWorkerPool
from datetime import datetime

taskclusterOptions = { 'rootUrl': os.environ['TASKCLUSTER_PROXY_URL'] }
taskclusterSecretsClient = taskcluster.Secrets(taskclusterOptions)
secret = taskclusterSecretsClient.get('project/relops/image-builder/dev')['secret']

currentEnvironment = 'staging' if 'stage.taskcluster.nonprod' in os.environ['TASKCLUSTER_ROOT_URL'] else 'production'

taskclusterWorkerManagerClient = taskcluster.WorkerManager(taskclusterOptions)

azureComputeManagementClient = ComputeManagementClient(
    ServicePrincipalCredentials(
        client_id = secret['azure']['id'],
        secret = secret['azure']['key'],
        tenant = secret['azure']['account']),
    secret['azure']['subscription'])


def getLatestImage(resourceGroup, key):
    pattern = re.compile('^{}-{}-([a-z0-9]{{7}})-([a-z0-9]{{7}})$'.format(resourceGroup.replace('rg-', ''), key))
    images = sorted([x for x in azureComputeManagementClient.images.list_by_resource_group(resourceGroup) if pattern.match(x.name) and 'machineImageCommitTime' in x.tags], key = lambda i: i.tags['machineImageCommitTime'], reverse=True)
    print('found {} {} images in {}'.format(len(images), key, resourceGroup))
    if len(images) > 0:
        print('latest image: {} ({})'.format(images[0].name, images[0].id))
    return images[0] if len(images) > 0 else None


def getLatestImageId(resourceGroup, key):
    image = getLatestImage(resourceGroup, key)
    return image.id if image is not None else None

commitSha = os.getenv('GITHUB_HEAD_SHA')
platform = os.getenv('platform')
key = os.getenv('key')
poolName = os.getenv('pool')
subscriptionId = 'dd0d4271-9b26-4c37-a025-1284a43a4385'
config = yaml.safe_load(urllib.request.urlopen('https://raw.githubusercontent.com/mozilla-platform-ops/cloud-image-builder/{}/config/{}.yaml'.format(commitSha, key)).read().decode())
poolConfig = next(p for p in config['manager']['pool'] if '{}/{}'.format(p['domain'], p['variant']) == poolName)

passwordCharPool = string.ascii_letters + string.digits + string.punctuation

includeRegions = map(lambda target: target['region'].replace(' ', '').lower(), config['target'])
try:
    commit = json.loads(urllib.request.urlopen(urllib.request.Request('https://api.github.com/repos/mozilla-platform-ops/cloud-image-builder/commits/{}'.format(commitSha), None, { 'User-Agent' : 'Mozilla/5.0' })).read().decode())['commit']
    lines = commit['message'].splitlines()
    if any(line.lower().startswith('include regions:') for line in lines):
        includeRegions = list(map(lambda x: x.lower().strip(), next(line for line in lines if line.startswith('include regions:')).replace('include regions:', '').split(',')))
        print('info: **include regions** commit syntax detected. worker pool generator will exclude regions that are not in: {}'.format(', '.join(includeRegions)))
    elif any(line.lower().startswith('exclude regions:') for line in lines):
        includeRegions = list(filter(lambda x: x not in map(lambda x: x.lower().strip(), next(line for line in lines if line.lower().startswith('exclude regions:')).replace('exclude regions:', '').split(',')), includeRegions))
        print('info: **exclude regions** commit syntax detected. worker pool generator will exclude regions that are not in: {}'.format(', '.join(includeRegions)))
except:
    print('warn: error reading commit message for sha: {}'.format(commitSha))

workerPool = {
    'minCapacity': poolConfig['capacity']['minimum'],
    'maxCapacity': poolConfig['capacity']['maximum'],
    'lifecycle': {
        'registrationTimeout': poolConfig['timeout']['registration'] if 'timeout' in poolConfig and 'registration' in poolConfig['timeout'] else 1800,
        'reregistrationTimeout': poolConfig['timeout']['reregistration'] if 'timeout' in poolConfig and 'reregistration' in poolConfig['timeout'] else 86400
    },
    'launchConfigs': list(filter(lambda x: x['storageProfile']['imageReference']['id'] is not None and x['location'] in poolConfig['locations'] and x['location'] in includeRegions, map(lambda x: {
        'location': x['region'].lower().replace(' ', ''),
        'capacityPerInstance': 1,
        'subnetId': '/subscriptions/{}/resourceGroups/{}/providers/Microsoft.Network/virtualNetworks/{}/subnets/{}'.format(subscriptionId, x['group'], x['group'].replace('rg-', 'vn-'), x['group'].replace('rg-', 'sn-')),
        'hardwareProfile': {
            'vmSize': x['machine']['format'].format(x['machine']['cpu'])
        },
        'osProfile': {
            'allowExtensionOperations': ('agent' not in x or x['agent'] != 'disable'),
            'windowsConfiguration': {
                'enableAutomaticUpdates': ('agent' not in x or x['agent'] != 'disable'),
                'provisionVMAgent': ('agent' not in x or x['agent'] != 'disable'),
                'timeZone': config['image']['timezone']
            }
        },
        'storageProfile': {
            'imageReference': {
                'id': getLatestImageId(x['group'], key)
            },
            'osDisk': {
                'caching': 'ReadWrite',
                'createOption': 'FromImage',
                'diskSizeGB': next(d for d in x['disk'] if d['os'])['size'],
                'managedDisk': {
                    'storageAccountType': 'StandardSSD_LRS' if next(d for d in x['disk'] if d['os'])['variant'] == 'ssd' else 'Standard_LRS'
                },
                'osType': 'Windows'
            },
            'dataDisks': [
                {
                    'lun': dataDiskIndex,
                    'createOption': 'Attach',
                    'diskSizeGB': dataDisk['size'],
                    'managedDisk': {
                        'storageAccountType': 'StandardSSD_LRS' if dataDisk['variant'] == 'ssd' else 'Standard_LRS'
                    }
                } for dataDiskIndex, dataDisk in enumerate(filter(lambda disk: (not disk['os']), x['disk']))
            ]
        },
        'tags': { t['name']: t['value'] for t in x['tag'] },
        'workerConfig': {
            'genericWorker': {
                'config': {
                    'idleTimeoutSecs': 90,
                    'cachesDir': 'Z:\\caches',
                    'cleanUpTaskDirs': True,
                    'deploymentId': commitSha[0:7],
                    'disableReboots': True,
                    'downloadsDir': 'Z:\\downloads',
                    'ed25519SigningKeyLocation': 'C:\\generic-worker\\ed25519-private.key',
                    'livelogExecutable': 'C:\\generic-worker\\livelog.exe',
                    'livelogPUTPort': 60022,
                    'numberOfTasksToRun': 0,
                    'provisionerId': poolConfig['domain'],
                    'runAfterUserCreation': 'C:\\generic-worker\\task-user-init.cmd',
                    'runTasksAsCurrentUser': False,
                    'sentryProject': 'generic-worker',
                    'shutdownMachineOnIdle': False,
                    'shutdownMachineOnInternalError': True,
                    'taskclusterProxyExecutable': 'C:\\generic-worker\\taskcluster-proxy.exe',
                    'taskclusterProxyPort': 80,
                    'tasksDir': 'Z:\\',
                    'workerGroup': x['group'],
                    'workerLocation': '{{"cloud":"azure","region":"{}","availabilityZone":"{}"}}'.format(x['region'].lower().replace(' ', ''), x['region'].lower().replace(' ', '')),
                    'workerType': poolConfig['variant'],
                    'wstAudience': 'cloudopsstage' if currentEnvironment == 'staging' else 'firefoxcitc',
                    'wstServerURL': 'https://websocktunnel-stage.taskcluster.nonprod.cloudops.mozgcp.net' if currentEnvironment == 'staging' else 'https://firefoxci-websocktunnel.services.mozilla.com'
                }
            }
        }
    }, filter(lambda x: x['group'].endswith('-{}'.format(poolConfig['domain'])), config['target']))))
}
if 'lifecycle' in poolConfig and poolConfig['lifecycle'] == 'spot':
    for pI in workerPool['launchConfigs']:
        workerPool['launchConfigs'][pI]['priority'] = 'Spot'
        workerPool['launchConfigs'][pI]['evictionPolicy'] = 'Deallocate'
        workerPool['launchConfigs'][pI]['billingProfile'] = {
            'maxPrice': -1
        }

# create an artifact containing the worker pool config that can be used for manual worker manager updates in the taskcluster web ui
with open('../{}.json'.format(poolName.replace('/', '-')), 'w') as file:
    json.dump(workerPool, file, indent = 2, sort_keys = True)

# update the worker manager with a complete worker pool config
machineImages = filter(lambda x: x is not None, map(lambda x: getLatestImage(x['group'], key), filter(lambda x: x['group'].endswith('-{}'.format(poolConfig['domain'])), config['target'])))
description = [
    '### experimental {}/{} taskcluster worker'.format(poolConfig['domain'], poolConfig['variant']),
    '#### provenance',
    '- operating system: **{}**'.format(config['image']['os']),
    '- os edition: **{}**'.format(config['image']['edition']),
    '- source iso: **{}**'.format(os.path.basename(config['iso']['source']['key'])),
    '- iso wim index: **{}** ({} {})'.format(config['iso']['wimindex'], config['image']['os'], config['image']['edition']),
    '- architecture: **{}**'.format(config['image']['architecture']),
    '- language: **{}**'.format(config['image']['language']),
    '- system timezone: **{}**'.format(config['image']['timezone']),
    '#### integration',
    '- commits and build tasks:',
    '\n'.join(list(map(lambda x: '  - {machineImageName}\n    - disk:\n      - commit: {diskImageCommitLink}\n      - build: {diskImageTaskLink}\n    - machine:\n      - commit: {machineImageCommitLink}\n      - build: {machineImageTaskLink}\n    - bootstrap: {bootstrapCommitLink}\n    - deployment: {deploymentCommitLink}'.format(
        machineImageName=x.name,
        diskImageCommitLink='[{org}/{repo}/{ref}](https://github.com/{org}/{repo}/commit/{ref})'.format(
            org='mozilla-platform-ops',
            repo='cloud-image-builder',
            ref=x.tags['diskImageCommitSha'][0:7],
        ) if 'diskImageCommitSha' in x.tags else 'missing tag: diskImageCommitSha',
        diskImageTaskLink='[{taskId}]({rootUrl}/tasks/{taskId}/runs/{run})'.format(
            rootUrl=os.getenv('TASKCLUSTER_ROOT_URL'),
            taskId=x.tags['diskImageTask'].split('/')[0],
            run=x.tags['diskImageTask'].split('/')[1]
        ) if 'diskImageTask' in x.tags else 'missing tag: diskImageTask',
        machineImageCommitLink='[{org}/{repo}/{ref}](https://github.com/{org}/{repo}/commit/{ref})'.format(
            org='mozilla-platform-ops',
            repo='cloud-image-builder',
            ref=x.tags['machineImageCommitSha'][0:7],
        ) if 'machineImageCommitSha' in x.tags else 'missing tag: machineImageCommitSha',
        machineImageTaskLink='[{taskId}]({rootUrl}/tasks/{taskId}/runs/{run})'.format(
            rootUrl=os.getenv('TASKCLUSTER_ROOT_URL'),
            taskId=x.tags['machineImageTask'].split('/')[0],
            run=x.tags['machineImageTask'].split('/')[1]
        ) if 'machineImageTask' in x.tags else 'missing tag: machineImageTask',
        bootstrapCommitLink='[{org}/{repo}/{ref}](https://github.com/{org}/{repo}/commit/{ref})'.format(
            org=x.tags['sourceOrganisation'],
            repo=x.tags['sourceRepository'],
            ref=x.tags['sourceRevision']
        ) if 'sourceOrganisation' in x.tags and 'sourceRepository' in x.tags and 'sourceRevision' in x.tags else 'missing tags: sourceOrganisation, sourceRepository, sourceRevision',
        deploymentCommitLink='[{org}/{repo}/{ref}](https://github.com/{org}/{repo}/commit/{ref})'.format(
            org=x.tags['sourceOrganisation'],
            repo=x.tags['sourceRepository'],
            ref=x.tags['deploymentId']
        ) if 'sourceOrganisation' in x.tags and 'sourceRepository' in x.tags and 'deploymentId' in x.tags else 'missing tags: sourceOrganisation, sourceRepository, deploymentId'), machineImages))),
    '#### deployment',
    '- platform: **{} ({})**'.format(platform, ', '.join(poolConfig['locations'])),
    '- last worker pool update: {} [{}]({})'.format(datetime.utcnow().isoformat()[:-10].replace('T', ' '), os.getenv('TASK_ID'), '{}/tasks/{}#artifacts'.format(os.getenv('TASKCLUSTER_ROOT_URL'), os.getenv('TASK_ID')))
]

providerConfig = {
    'description': '\n'.join(description),
    'owner': poolConfig['owner'],
    'emailOnError': True,
    'providerId': poolConfig['provider'],
    'config': workerPool
}
configPath = '../{}.yaml'.format(poolName.replace('/', '-'))
with open(configPath, 'w') as file:
    print('saving: {}'.format(configPath))
    yaml.dump(providerConfig, file, default_flow_style=False)
    updateWorkerPool(
        workerManager = taskclusterWorkerManagerClient,
        configPath = configPath,
        workerPoolId = '{}'.format(poolName))
