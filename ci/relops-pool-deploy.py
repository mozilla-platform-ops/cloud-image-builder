import os
import taskcluster
from cib import updateRole


currentEnvironment = 'staging' if 'stage.taskcluster.nonprod' in os.environ['TASKCLUSTER_ROOT_URL'] else 'production'
includeEnvironments = [
  'production',
  'staging'
]
lines = os.getenv('TRAVIS_COMMIT_MESSAGE').splitlines()

if any(line.lower().strip() == 'no-ci' or line.lower().strip() == 'no-travis-ci' for line in lines):
  print('info: **no ci** commit syntax detected. skipping pool and role checks')
  quit()

if any(line.lower().startswith('include environments:') for line in lines):
  includeEnvironments = list(map(lambda x: x.lower().strip(), next(line for line in lines if line.startswith('include environments:')).replace('include environments:', '').split(',')))
  print('info: **include environments** commit syntax detected. ci will process environments: {}'.format(', '.join(includeEnvironments)))
elif any(line.lower().startswith('exclude environments:') for line in lines):
  includeEnvironments = list(filter(lambda x: x not in map(lambda x: x.lower().strip(), next(line for line in lines if line.lower().startswith('exclude environments:')).replace('exclude environments:', '').split(',')), includeEnvironments))
  print('info: **exclude environments** commit syntax detected. ci will process environments: {}'.format(', '.join(includeEnvironments)))
if currentEnvironment not in includeEnvironments:
  print('info: current environment ({}) is excluded. skipping pool and role checks'.format(currentEnvironment))
  quit()


taskclusterAuth = taskcluster.Auth(taskcluster.optionsFromEnvironment())
taskclusterWorkerManager = taskcluster.WorkerManager(taskcluster.optionsFromEnvironment())

updateRole(
  auth = taskclusterAuth,
  configPath = 'ci/config/role/branch-master.yaml',
  roleId = 'repo:github.com/mozilla-platform-ops/cloud-image-builder:branch:master')

for pool in ['gecko-t/win10-64-azure', 'gecko-t/win7-32-azure']:
  updateRole(
    auth = taskclusterAuth,
    configPath = 'ci/config/role/{}/{}.yaml'.format(currentEnvironment, pool),
    roleId = 'worker-pool:{}'.format(pool))
