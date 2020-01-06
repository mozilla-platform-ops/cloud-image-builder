import os
import slugid
import taskcluster
import yaml
from cib import createTask, imageManifestHasChanged, machineImageExists
from azure.common.credentials import ServicePrincipalCredentials
from azure.mgmt.compute import ComputeManagementClient


runEnvironment = 'travis' if os.getenv('TRAVIS_COMMIT') is not None else 'taskcluster' if os.getenv('TASK_ID') is not None else None
taskclusterOptions = { 'rootUrl': os.environ['TASKCLUSTER_PROXY_URL'] } if runEnvironment == 'taskcluster' else taskcluster.optionsFromEnvironment()

auth = taskcluster.Auth(taskclusterOptions)
queue = taskcluster.Queue(taskclusterOptions)
index = taskcluster.Index(taskclusterOptions)
secrets = taskcluster.Secrets(taskclusterOptions)

secret = secrets.get('project/relops/image-builder/dev')

azureCredentials = ServicePrincipalCredentials(
  client_id = secret['azure']['id'],
  secret = secret['azure']['key'],
  tenant = secret['azure']['account'])
azureComputeManagementClient = ComputeManagementClient(azureCredentials, secret['azure']['subscription'])

if runEnvironment == 'travis':
  commitSha = os.getenv('TRAVIS_COMMIT')
  taskGroupId = slugid.nice()
  createTask(
    queue = queue,
    taskId = taskGroupId,
    taskName = 'a-task-group-placeholder',
    taskDescription = 'this task only serves as a task grouping when triggered from travis. it does no actual work',
    provisioner = 'relops',
    workerType = 'win2019',
    commands = [ 'echo "task: {}, sha: {}"'.format(taskGroupId, commitSha) ])
elif runEnvironment == 'taskcluster':
  commitSha = os.getenv('GITHUB_HEAD_SHA')
  taskGroupId = os.getenv('TASK_ID')
  print('debug: auth.currentScopes')
  print(auth.currentScopes())
else:
  quit()

for platform in ['azure']:
  for key in ['win10-64', 'win10-64-gpu', 'win7-32', 'win7-32-gpu', 'win2012', 'win2019']:
    queueDiskImageBuild = imageManifestHasChanged(platform, key, commitSha)
    if queueDiskImageBuild:
      buildTaskId = slugid.nice()
      createTask(
        queue = queue,
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
          'git reset --hard {}'.format(commitSha),
          'powershell -File build-{}-disk-image.ps1 {}-{}'.format(platform, key, platform)
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

    targetConfigPath = '{}/../config/{}-{}.yaml'.format(os.path.dirname(__file__), key, platform)
    with open(targetConfigPath, 'r') as stream:
      targetConfig = yaml.safe_load(stream)
      for target in targetConfig['target']:
        queueMachineImageBuild = not machineImageExists(index, azureComputeManagementClient, platform, target['region'], target['group'], key)
        if queueMachineImageBuild:
          createTask(
            queue = queue,
            taskId = slugid.nice(),
            taskName = 'convert-{}-{}-disk-image-to-{}-{}-machine-image-and-deploy-to-{}-{}'.format(platform, key, platform, key, platform, target['group']),
            taskDescription = 'convert {} {} disk image to {} {} machine image and deploy to {} {}'.format(platform, key, platform, key, platform, target['group']),
            maxRunMinutes = 180,
            retries = 1,
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
              'git reset --hard {}'.format(commitSha),
              'powershell -File build-{}-machine-image.ps1 {}-{} {}'.format(platform, key, platform, target['group'])
            ],
            scopes = [
              'secrets:get:project/relops/image-builder/dev'
            ],
            routes = [
              'index.project.relops.cloud-image-builder.{}.{}.{}.revision.{}'.format(platform, target['group'], key, commitSha),
              'index.project.relops.cloud-image-builder.{}.{}.{}.latest'.format(platform, target['group'], key)
            ],
            taskGroupId = taskGroupId)
