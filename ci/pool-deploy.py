import os
import slugid
import taskcluster
import yaml
from cib import createTask, diskImageManifestHasChanged, machineImageManifestHasChanged, machineImageExists
#from azure.common.credentials import ServicePrincipalCredentials
from azure.identity import ClientSecretCredential
from azure.mgmt.compute import ComputeManagementClient


runEnvironment = 'travis' if os.getenv('TRAVIS_COMMIT') is not None else 'taskcluster' if os.getenv('TASK_ID') is not None else None
taskclusterOptions = { 'rootUrl': os.environ['TASKCLUSTER_PROXY_URL'] } if runEnvironment == 'taskcluster' else taskcluster.optionsFromEnvironment()

auth = taskcluster.Auth(taskclusterOptions)
queue = taskcluster.Queue(taskclusterOptions)
index = taskcluster.Index(taskclusterOptions)
secrets = taskcluster.Secrets(taskclusterOptions)

secret = secrets.get('project/relops/image-builder/dev')['secret']

platformClient = {
    'azure': ComputeManagementClient(
        #ServicePrincipalCredentials(
        #    client_id = secret['azure']['id'],
        #    secret = secret['azure']['key'],
        #    tenant = secret['azure']['account']),
        ClientSecretCredential(
            tenant_id=secret['azure']['account'],
            client_id=secret['azure']['id'],
            client_secret=secret['azure']['key']),
        secret['azure']['subscription'])
}

if runEnvironment == 'travis':
    commitSha = os.getenv('TRAVIS_COMMIT')
    taskGroupId = slugid.nice()
    createTask(
        queue = queue,
        taskId = taskGroupId,
        taskName = '00 :: task group placeholder',
        taskDescription = 'this task only serves as a task grouping when triggered from travis. it does no actual work',
        provisioner = 'relops-3',
        workerType = 'win2019',
        commands = [ 'echo "task: {}, sha: {}"'.format(taskGroupId, commitSha) ])
elif runEnvironment == 'taskcluster':
    commitSha = os.getenv('GITHUB_HEAD_SHA')
    taskGroupId = os.getenv('TASK_ID')
    print('debug: auth.currentScopes')
    print(auth.currentScopes())
    createTask(
        queue = queue,
        taskId = slugid.nice(),
        taskName = '00 :: purge deprecated azure resources',
        taskDescription = 'delete orphaned, deprecated, deallocated and unused azure resources',
        maxRunMinutes = 60,
        provisioner = 'relops-3',
        workerType = 'win2019',
        priority = 'high',
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
else:
    quit()

for platform in ['amazon', 'azure']:
    for key in ['win10-64', 'win10-64-gpu', 'win7-32', 'win7-32-gpu', 'win2012', 'win2019']:
        configPath = '{}/../config/{}.yaml'.format(os.path.dirname(__file__), key)
        with open(configPath, 'r') as stream:
            config = yaml.safe_load(stream)
            for pool in [p for p in config['manager']['pool'] if p['platform'] == platform] :
                # todo: remove this hack which exists because non-azure builds don't yet work
                queueWorkerPoolConfigurationTask = platform in platformClient
                if queueWorkerPoolConfigurationTask:
                    createTask(
                        queue = queue,
                        image = 'python',
                        taskId = slugid.nice(),
                        taskName = '01 :: generate {} {}/{} worker pool configuration'.format(platform, pool['domain'], pool['variant']),
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
                            'git clone https://github.com/mozilla-platform-ops/cloud-image-builder.git && pip install azure boto3 pyyaml slugid taskcluster urllib3 | grep -v "^[[:space:]]*$" && cd cloud-image-builder && git reset --hard {} && python ci/generate-worker-pool-config.py'.format(commitSha)
                        ],
                        scopes = [
                            'secrets:get:project/relops/image-builder/dev',
                            'worker-manager:manage-worker-pool:{}/{}'.format(pool['domain'], pool['variant']),
                            'worker-manager:provider:{}'.format(pool['provider'])
                        ],
                        taskGroupId = taskGroupId)
