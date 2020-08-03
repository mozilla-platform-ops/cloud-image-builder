import glob
import json
import os
import pathlib
import slugid
import taskcluster
import urllib.request
import yaml
from cib import createTask, diskImageManifestHasChanged, machineImageManifestHasChanged, machineImageExists
from azure.common.credentials import ServicePrincipalCredentials
from azure.mgmt.compute import ComputeManagementClient


def extract_pools(config_path):
    return map(lambda p: '{}/{}'.format(p['domain'], p['variant']), yaml.safe_load(open(config_path, 'r'))['manager']['pool'])


taskclusterOptions = { 'rootUrl': os.environ['TASKCLUSTER_PROXY_URL'] }

auth = taskcluster.Auth(taskclusterOptions)
queue = taskcluster.Queue(taskclusterOptions)
index = taskcluster.Index(taskclusterOptions)
secrets = taskcluster.Secrets(taskclusterOptions)

secret = secrets.get('project/relops/image-builder/dev')['secret']

platformClient = {
    'azure': ComputeManagementClient(
        ServicePrincipalCredentials(
            client_id = secret['azure']['id'],
            secret = secret['azure']['key'],
            tenant = secret['azure']['account']),
        secret['azure']['subscription'])
}

commitSha = os.getenv('GITHUB_HEAD_SHA')
allKeyConfigPaths = glob.glob('{}/../config/win*.yaml'.format(os.path.dirname(__file__)))
includeKeys = list(map(lambda x: pathlib.Path(x).stem, allKeyConfigPaths))
includePools = [poolName for poolNames in map(lambda configPath: map(lambda pool: '{}/{}'.format(pool['domain'], pool['variant']), yaml.safe_load(open(configPath, 'r'))['manager']['pool']), allKeyConfigPaths) for poolName in poolNames]
includeRegions = sorted(list(set([region for regions in map(lambda configPath: map(lambda target: target['region'].replace(' ', '').lower(), yaml.safe_load(open(configPath, 'r'))['target']), allKeyConfigPaths) for region in regions])))
includeEnvironments = [
    #'production',
    'staging'
]
currentEnvironment = 'staging' if 'stage.taskcluster.nonprod' in os.environ['TASKCLUSTER_ROOT_URL'] else 'production'
if currentEnvironment == 'production':
    print('info: skipping production environment builds')
    quit()

overwriteDiskImage = False
overwriteMachineImage = False

try:
    commit = json.loads(urllib.request.urlopen(urllib.request.Request('https://api.github.com/repos/mozilla-platform-ops/cloud-image-builder/commits/{}'.format(commitSha), None, { 'User-Agent' : 'Mozilla/5.0' })).read().decode())['commit']
    lines = commit['message'].splitlines()
    overwriteDiskImage = any(line.lower().strip() == 'overwrite-disk-image' for line in lines)
    overwriteMachineImage = any(line.lower().strip() == 'overwrite-machine-image' for line in lines)
    disableCleanup = any(line.lower().strip() == 'disable-cleanup' for line in lines)
    enableSnapshotCopy = any(line.lower().strip() == 'enable-snapshot-copy' for line in lines)
    purgeRelopsResources = True
    purgeTaskclusterResources = any(line.lower().strip() == 'purge-taskcluster-resources' for line in lines)
    skipImageVerification = any(line.lower().strip() == 'no-verify' for line in lines)
    noCI = any(line.lower().strip() == 'no-ci' or line.lower().strip() == 'no-taskcluster-ci' for line in lines)
    if noCI:
        print('info: **no ci** commit syntax detected. skipping ci task creation')
    elif any(line.lower().startswith('include environments:') for line in lines):
        includeEnvironments = list(map(lambda x: x.lower().strip(), next(line for line in lines if line.startswith('include environments:')).replace('include environments:', '').split(',')))
        print('info: **include environments** commit syntax detected. ci will process environments: {}'.format(', '.join(includeEnvironments)))
    elif any(line.lower().startswith('exclude environments:') for line in lines):
        includeEnvironments = list(filter(lambda x: x not in map(lambda x: x.lower().strip(), next(line for line in lines if line.lower().startswith('exclude environments:')).replace('exclude environments:', '').split(',')), includeEnvironments))
        print('info: **exclude environments** commit syntax detected. ci will process environments: {}'.format(', '.join(includeEnvironments)))
    if currentEnvironment not in includeEnvironments:
        noCI = True
        print('info: current environment ({}) is excluded. skipping ci task creation'.format(currentEnvironment))

    poolDeploy = (not noCI) and any(line.lower().strip() == 'pool-deploy' for line in lines)
    if poolDeploy:
        print('info: **pool deploy** commit syntax detected. disk/machine image builds will be skipped')

    if not noCI:

        if any(line.lower().startswith('include keys:') for line in lines):
            includeKeys = list(map(lambda x: x.lower().strip(), next(line for line in lines if line.startswith('include keys:')).replace('include keys:', '').split(',')))
            print('info: **include keys** commit syntax detected. ci will process keys: {}'.format(', '.join(includeKeys)))
        elif any(line.lower().startswith('exclude keys:') for line in lines):
            includeKeys = list(filter(lambda x: x not in map(lambda x: x.lower().strip(), next(line for line in lines if line.lower().startswith('exclude keys:')).replace('exclude keys:', '').split(',')), includeKeys))
            print('info: **exclude keys** commit syntax detected. ci will process keys: {}'.format(', '.join(includeKeys)))

        elif any(line.lower().startswith('include pools:') for line in lines):
            includePools = list(map(lambda x: x.lower().strip(), next(line for line in lines if line.startswith('include pools:')).replace('include pools:', '').split(',')))
            print('info: **include pools** commit syntax detected. ci will process pools: {}'.format(', '.join(includePools)))
        elif any(line.lower().startswith('exclude pools:') for line in lines):
            includePools = list(filter(lambda x: x not in map(lambda x: x.lower().strip(), next(line for line in lines if line.lower().startswith('exclude pools:')).replace('exclude pools:', '').split(',')), includePools))
            print('info: **exclude pools** commit syntax detected. ci will process pools: {}'.format(', '.join(includePools)))

        if any(line.lower().startswith('include regions:') for line in lines):
            includeRegions = list(map(lambda x: x.lower().strip(), next(line for line in lines if line.startswith('include regions:')).replace('include regions:', '').split(',')))
            print('info: **include regions** commit syntax detected. ci will process regions: {}'.format(', '.join(includeRegions)))
        elif any(line.lower().startswith('exclude regions:') for line in lines):
            includeRegions = list(filter(lambda x: x not in map(lambda x: x.lower().strip(), next(line for line in lines if line.lower().startswith('exclude regions:')).replace('exclude regions:', '').split(',')), includeRegions))
            print('info: **exclude regions** commit syntax detected. ci will process regions: {}'.format(', '.join(includeRegions)))

    print('info: commit message reads:')
    print(commit['message'])
except:
    noCI == True
    poolDeploy = False
    print('warn: error reading commit message for sha: {}, ci disabled'.format(commitSha))
if noCI:
    quit()

taskGroupId = os.getenv('TASK_ID')

print('[debug] auth.currentScopes:')
for scope in auth.currentScopes()['scopes']:
    print(' - {}'.format(scope))

yamlLintTaskId = slugid.nice()
createTask(
    queue = queue,
    image = 'python',
    taskId = yamlLintTaskId,
    taskName = '00 :: validate all yaml files in repo',
    taskDescription = 'run a linter against each yaml file in the repository',
    maxRunMinutes = 10,
    retries = 5,
    retriggerOnExitCodes = [ 123 ],
    provisioner = 'relops-3',
    workerType = 'decision',
    priority = 'high',
    commands = [
        '/bin/bash',
        '--login',
        '-c',
        'git clone https://github.com/mozilla-platform-ops/cloud-image-builder.git && cd cloud-image-builder && git reset --hard {} && pip install yamllint | grep -v "^[[:space:]]*$" && yamllint .'.format(commitSha)
    ],
    taskGroupId = taskGroupId
)

azurePurgeTaskIds = { 'default': slugid.nice() }
if purgeRelopsResources:
    azurePurgeTaskIds['relops'] = slugid.nice()
if purgeTaskclusterResources:
    azurePurgeTaskIds['taskcluster-staging-workers-us-central'] = slugid.nice()
    azurePurgeTaskIds['taskcluster-production-workers-us-central'] = slugid.nice()
createTask(
    queue = queue,
    taskId = slugid.nice(),
    taskName = '00 :: purge deprecated azure resources - powershell (slow)',
    taskDescription = 'delete orphaned, deprecated, deallocated and unused azure resources',
    maxRunMinutes = 60,
    retries = 5,
    retriggerOnExitCodes = [ 123 ],
    provisioner = 'relops-3',
    workerType = 'win2019',
    priority = 'low',
    features = {
        'taskclusterProxy': True
    },
    commands = [
        'git clone https://github.com/mozilla-platform-ops/cloud-image-builder.git',
        'cd cloud-image-builder',
        'git reset --hard {}'.format(commitSha),
        'powershell -File ci\\purge-deprecated-azure-resources.ps1'
    ],
    scopes = [
        'secrets:get:project/relops/image-builder/dev'
    ],
    taskGroupId = taskGroupId
)

for resourceGroup in azurePurgeTaskIds:
    createTask(
        queue = queue,
        image = 'python',
        taskId = azurePurgeTaskIds[resourceGroup],
        taskName = '00 :: purge deprecated azure resources in {} resource group{}'.format(resourceGroup, 's' if resourceGroup == 'default' else ''),
        taskDescription = 'delete orphaned, deprecated, deallocated and unused azure resources',
        #dependencies = [ yamlLintTaskId ],
        maxRunMinutes = 60,
        retries = 5,
        retriggerOnExitCodes = [ 123 ],
        provisioner = 'relops-3',
        workerType = 'decision',
        priority = 'high',
        features = {
            'taskclusterProxy': True
        },
        commands = [
            '/bin/bash',
            '--login',
            '-c',
            'git clone https://github.com/mozilla-platform-ops/cloud-image-builder.git && cd cloud-image-builder && git reset --hard {} && pip install -r ci/purge-azure-resources-requirements.txt | grep -v "^[[:space:]]*$" && python ci/purge-azure-resources.py{}'.format(commitSha, '' if resourceGroup == 'default' else ' {}'.format(resourceGroup))
        ],
        scopes = [
            'secrets:get:project/relops/image-builder/dev'
        ],
        taskGroupId = taskGroupId
    )

for platform in ['amazon', 'azure']:
    for key in includeKeys:
        configPath = '{}/../config/{}.yaml'.format(os.path.dirname(__file__), key)
        with open(configPath, 'r') as stream:
            config = yaml.safe_load(stream)
            isDiskImageForIncludedPool = any('{}/{}'.format(pool['domain'], pool['variant']) in includePools for pool in config['manager']['pool'])
            queueDiskImageBuild = (not poolDeploy) and isDiskImageForIncludedPool and (overwriteDiskImage or diskImageManifestHasChanged(platform, key, commitSha))
            if queueDiskImageBuild:
                buildTaskId = slugid.nice()
                createTask(
                    queue = queue,
                    taskId = buildTaskId,
                    taskName = '01 :: build {} {} disk image from {} {} iso'.format(platform, key, config['image']['os'], config['image']['edition']),
                    taskDescription = 'build a customised {} disk image file for {}, from iso file {} and upload to cloud storage'.format(key, platform, os.path.basename(config['iso']['source']['key'])),
                    dependencies = [ yamlLintTaskId ],
                    maxRunMinutes = 180,
                    retries = 1,
                    retriggerOnExitCodes = [ 123 ],
                    provisioner = 'relops-3',
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
                        'git clone https://github.com/mozilla-platform-ops/cloud-image-builder.git',
                        'cd cloud-image-builder',
                        'git reset --hard {}'.format(commitSha),
                        'powershell -File build-disk-image.ps1 {} {}'.format(platform, key)
                    ],
                    scopes = [
                        'generic-worker:os-group:relops/win2019/Administrators',
                        'generic-worker:run-as-administrator:relops/win2019',
                        'secrets:get:project/relops/image-builder/dev'
                    ],
                    routes = [
                        'index.project.relops.cloud-image-builder.{}.{}.revision.{}'.format(platform, key, commitSha),
                        'index.project.relops.cloud-image-builder.{}.{}.latest'.format(platform, key)
                    ],
                    taskGroupId = taskGroupId
                )
            else:
                buildTaskId = None
                print('info: skipped disk image build task for {} {} {}'.format(platform, key, commitSha))

            for pool in [p for p in config['manager']['pool'] if p['platform'] == platform and '{}/{}'.format(p['domain'], p['variant']) in includePools]:
                machineImageBuildTaskIdsForPool = []
                #taggingTaskIdsForPool = []
                for target in [t for t in config['target'] if t['group'].endswith('-{}'.format(pool['domain'])) and t['region'].lower().replace(' ', '') in includeRegions]:
                    queueMachineImageBuild = (not poolDeploy) and (platform in platformClient) and (queueDiskImageBuild or machineImageManifestHasChanged(platform, key, commitSha, target['group']) or not machineImageExists(
                        taskclusterIndex = index,
                        platformClient = platformClient[platform],
                        platform = platform,
                        group = target['group'],
                        key = key))

                    machineImageBuildTaskId = slugid.nice()
                    if queueMachineImageBuild:
                        machineImageBuildTaskIdsForPool.append(machineImageBuildTaskId)
                        bootstrapRevision = next(x for x in target['tag'] if x['name'] == 'sourceRevision')['value']
                        bootstrapRepository = next(x for x in target['tag'] if x['name'] == 'sourceRepository')['value']
                        bootstrapOrganisation = next(x for x in target['tag'] if x['name'] == 'sourceOrganisation')['value']
                        machineImageBuildDependencies = [ yamlLintTaskId ]
                        if platform == 'azure':
                            for resourceGroup in azurePurgeTaskIds:
                                machineImageBuildDependencies.append(azurePurgeTaskIds[resourceGroup])
                        if buildTaskId is not None:
                            machineImageBuildDependencies.append(buildTaskId)
                        createTask(
                            queue = queue,
                            taskId = machineImageBuildTaskId,
                            taskName = '02 :: build {} {}/{} machine image from {} {} disk image using {}/{} revision {} and deploy to {} {}'.format(platform, pool['domain'], pool['variant'], platform, key, bootstrapOrganisation, bootstrapRepository, bootstrapRevision, platform, target['group']),
                            taskDescription = 'build {} {}/{} machine image from {} {} disk image using {}/{} revision {} and deploy to {} {}'.format(platform, pool['domain'], pool['variant'], platform, key, bootstrapOrganisation, bootstrapRepository, bootstrapRevision, platform, target['group']),
                            maxRunMinutes = 180,
                            retries = 5,
                            retriggerOnExitCodes = [ 123 ],
                            dependencies = machineImageBuildDependencies,
                            provisioner = 'relops-3',
                            workerType = 'win2019',
                            priority = 'low',
                            artifacts = [
                                {
                                    'type': 'directory',
                                    'name': 'public/instance-logs',
                                    'path': 'instance-logs'
                                },
                                {
                                    'type': 'directory',
                                    'name': 'public/screenshot/full',
                                    'path': 'screenshot/full'
                                },
                                {
                                    'type': 'directory',
                                    'name': 'public/screenshot/thumbnail',
                                    'path': 'screenshot/thumbnail'
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
                                'git clone https://github.com/mozilla-platform-ops/cloud-image-builder.git',
                                'cd cloud-image-builder',
                                'git reset --hard {}'.format(commitSha),
                                'powershell .\\build-machine-image.ps1 -platform {} -imageKey {} -group {}{}{}{}'.format(
                                    platform,
                                    key,
                                    target['group'],
                                    (' -enableSnapshotCopy' if enableSnapshotCopy else ''),
                                    (' -overwrite' if overwriteMachineImage else ''),
                                    (' -disableCleanup' if disableCleanup else '')
                                )
                            ],
                            scopes = [
                                'generic-worker:os-group:relops/win2019/Administrators',
                                'generic-worker:run-as-administrator:relops/win2019',
                                'secrets:get:project/relops/image-builder/dev'
                            ],
                            routes = [
                                'index.project.relops.cloud-image-builder.{}.{}.{}.revision.{}'.format(platform, target['group'], key, commitSha),
                                'index.project.relops.cloud-image-builder.{}.{}.{}.latest'.format(platform, target['group'], key)
                            ],
                            taskGroupId = taskGroupId)
                    else:
                        print('info: skipped machine image build task for {} {} {}'.format(platform, target['group'], key))

                queueWorkerPoolConfigurationTask = platform in platformClient
                if queueWorkerPoolConfigurationTask:
                    workerPoolConfigurationTaskId = slugid.nice()
                    createTask(
                        queue = queue,
                        image = 'python',
                        taskId = workerPoolConfigurationTaskId,
                        taskName = '03 :: generate {} {}/{} worker pool configuration'.format(platform, pool['domain'], pool['variant']),
                        taskDescription = 'create worker pool configuration for {} {}/{} which can be added to worker manager'.format(platform, pool['domain'], pool['variant']),
                        maxRunMinutes = 180,
                        retries = 1,
                        retriggerOnExitCodes = [ 123 ],
                        artifacts = [
                            {
                                'type': 'file',
                                'name': 'public/{}-{}.json'.format(pool['domain'], pool['variant']),
                                'path': '{}-{}.json'.format(pool['domain'], pool['variant']),
                            },
                            {
                                'type': 'file',
                                'name': 'public/{}-{}.yaml'.format(pool['domain'], pool['variant']),
                                'path': '{}-{}.yaml'.format(pool['domain'], pool['variant']),
                            }
                        ],
                        dependencies = machineImageBuildTaskIdsForPool,
                        provisioner = 'relops-3',
                        workerType = 'decision',
                        priority = 'low',
                        features = {
                            'taskclusterProxy': True
                        },
                        env = {
                            'GITHUB_HEAD_SHA': commitSha,
                            'platform': platform,
                            'key': key,
                            'pool': '{}/{}'.format(pool['domain'], pool['variant'])
                        },
                        commands = [
                            '/bin/bash',
                            '--login',
                            '-c',
                            'git clone https://github.com/mozilla-platform-ops/cloud-image-builder.git && pip install azure-mgmt-compute boto3 cachetools pyyaml slugid taskcluster urllib3 | grep -v "^[[:space:]]*$" && cd cloud-image-builder && git reset --hard {} && python ci/generate-worker-pool-config.py'.format(commitSha)
                        ],
                        scopes = [
                            'secrets:get:project/relops/image-builder/dev',
                            'worker-manager:manage-worker-pool:{}/{}'.format(pool['domain'], pool['variant']),
                            'worker-manager:provider:{}'.format(pool['provider'])
                        ],
                        taskGroupId = taskGroupId)

                    queueWorkerPoolVerificationTask = (not skipImageVerification) and ('queue:create-task:highest:{}/win*'.format(pool['domain']) in auth.currentScopes()['scopes'])
                    if queueWorkerPoolVerificationTask:
                        createTask(
                            queue = queue,
                            taskId = slugid.nice(),
                            taskName = '04 :: verify task claimability on {} {}/{}'.format(platform, pool['domain'], pool['variant']),
                            taskDescription = 'verify that worker pool instance instantiations and task claims succeed using newly deployed machine images',
                            maxRunMinutes = 60,
                            retries = 5,
                            retriggerOnExitCodes = [ 123 ],
                            dependencies = [ workerPoolConfigurationTaskId ],
                            provisioner = 'relops-test-workers',
                            workerType = "{}/{}".format(pool['domain'], pool['variant']),
                            priority = 'high',
                            commands = [
                                'echo "hello world, from {}/{} on {}"'.format(pool['domain'], pool['variant'], platform)
                            ],
                            scopes = [],
                            taskGroupId = taskGroupId)
