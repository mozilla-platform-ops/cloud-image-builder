import os
import slugid
import taskcluster
import yaml
from cib import createTask, diskImageManifestHasChanged, machineImageManifestHasChanged, machineImageExists
from azure.common.credentials import ServicePrincipalCredentials
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
    ServicePrincipalCredentials(
      client_id = secret['azure']['id'],
      secret = secret['azure']['key'],
      tenant = secret['azure']['account']),
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
    provisioner = 'relops',
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
    retries = 1,
    retriggerOnExitCodes = [ 123 ],
    provisioner = 'relops',
    workerType = 'win2019',
    priority = 'high',
    features = {
      'taskclusterProxy': True
    },
    commands = [
      'git clone https://github.com/grenade/cloud-image-builder.git',
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
  for key in ['win10-64', 'win10-64-gpu', 'win7-32', 'win7-32-gpu']:
    configPath = '{}/../config/{}.yaml'.format(os.path.dirname(__file__), key)
    with open(configPath, 'r') as stream:
      config = yaml.safe_load(stream)
      queueDiskImageBuild = diskImageManifestHasChanged(platform, key, commitSha)
      if queueDiskImageBuild:
        buildTaskId = slugid.nice()
        createTask(
          queue = queue,
          taskId = buildTaskId,
          taskName = '01 :: build {} {} disk image from {} {} iso'.format(platform, key, config['image']['os'], config['image']['edition']),
          taskDescription = 'build a customised {} disk image file for {}, from iso file {} and upload to cloud storage'.format(key, platform, os.path.basename(config['iso']['source']['key'])),
          maxRunMinutes = 180,
          retries = 1,
          retriggerOnExitCodes = [ 123 ],
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

      for pool in [p for p in config['manager']['pool'] if p['platform'] == platform] :
        taggingTaskIdsForPool = []
        for target in [t for t in config['target'] if t['group'].endswith('-{}'.format(pool['domain']))]:
          queueMachineImageBuild = platform in platformClient and (queueDiskImageBuild or machineImageManifestHasChanged(platform, key, commitSha, target['group']) or not machineImageExists(
            taskclusterIndex = index,
            platformClient = platformClient[platform],
            platform = platform,
            group = target['group'],
            key = key))
          if queueMachineImageBuild:
            machineImageBuildTaskId = slugid.nice()
            bootstrapRevision = next(x for x in target['tag'] if x['name'] == 'sourceRevision')['value']
            createTask(
              queue = queue,
              taskId = machineImageBuildTaskId,
              taskName = '02 :: build {} {}/{} machine image from {} {} disk image using bootstrap revision {} and deploy to {} {}'.format(platform, pool['domain'], pool['variant'], platform, key, bootstrapRevision, platform, target['group']),
              taskDescription = 'build {} {}/{} machine image from {} {} disk image using bootstrap revision {} and deploy to {} {}'.format(platform, pool['domain'], pool['variant'], platform, key, bootstrapRevision, platform, target['group']),
              maxRunMinutes = 180,
              retries = 1,
              retriggerOnExitCodes = [ 123 ],
              dependencies = [] if buildTaskId is None else [ buildTaskId ],
              provisioner = 'relops',
              workerType = 'win2019',
              priority = 'low',
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
                'powershell -File build-machine-image.ps1 {} {} {}'.format(platform, key, target['group'])
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
            taggingTaskId = slugid.nice()
            taggingTaskIdsForPool.append(taggingTaskId)
            createTask(
              queue = queue,
              image = 'python',
              taskId = taggingTaskId,
              taskName = '03 :: tag {} {} {} machine image'.format(platform, target['group'], key),
              taskDescription = 'apply tags to {} {} {} machine image'.format(platform, target['group'], key),
              maxRunMinutes = 180,
              retries = 4,
              retriggerOnExitCodes = [ 123 ],
              dependencies = [ machineImageBuildTaskId ],
              provisioner = 'relops',
              workerType = 'decision',
              priority = 'low',
              features = {
                'taskclusterProxy': True
              },
              env = {
                'platform': platform,
                'group': target['group'],
                'key': key
              },
              commands = [
                '/bin/bash',
                '--login',
                '-c',
                'git clone https://github.com/grenade/cloud-image-builder.git && pip install azure boto3 cachetools pyyaml requests slugid taskcluster urllib3 && cd cloud-image-builder && git reset --hard {} && python ci/tag-machine-images.py'.format(commitSha)
              ],
              scopes = [
                'secrets:get:project/relops/image-builder/dev'
              ],
              taskGroupId = taskGroupId)
          else:
            print('info: skipped machine image build task for {} {} {}'.format(platform, target['group'], key))

        # todo: remove this hack which exists because non-azure builds don't yet work
        queueWorkerPoolConfigurationTask = platform in platformClient
        if queueWorkerPoolConfigurationTask:
          createTask(
            queue = queue,
            image = 'python',
            taskId = slugid.nice(),
            taskName = '04 :: generate {} {}/{} worker pool configuration'.format(platform, pool['domain'], pool['variant']),
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
            dependencies = taggingTaskIdsForPool,
            provisioner = 'relops',
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
              'git clone https://github.com/grenade/cloud-image-builder.git && pip install azure boto3 pyyaml slugid taskcluster urllib3 && cd cloud-image-builder && git reset --hard {} && python ci/generate-worker-pool-config.py'.format(commitSha)
            ],
            scopes = [
              'secrets:get:project/relops/image-builder/dev',
              'worker-manager:manage-worker-pool:{}/{}'.format(pool['domain'], pool['variant']),
              'worker-manager:provider:{}'.format(pool['provider'])
            ],
            taskGroupId = taskGroupId)
