import json
import os
import taskcluster
import urllib.error
import urllib.request

from cachetools import cached, TTLCache
cache = TTLCache(maxsize=100, ttl=300)


@cached(cache)
def get_commits(org, repo):
  try:
    response = urllib.request.urlopen('https://api.github.com/repos/{}/{}/commits'.format(org, repo))
  except urllib.error.HTTPError as e:
    print('error code {} on commits lookup for {}/{}'.format(e.code, org, repo))
    print(e.read())
    exit(123 if e.code == 403 else 1)
  return json.loads(response.read().decode())


runEnvironment = 'travis' if os.getenv('TRAVIS_COMMIT') is not None else 'taskcluster' if os.getenv('TASK_ID') is not None else 'local'
taskclusterOptions = { 'rootUrl': os.environ['TASKCLUSTER_PROXY_URL'] } if runEnvironment == 'taskcluster' else taskcluster.optionsFromEnvironment()


index = taskcluster.Index(taskclusterOptions)
tasks = index.listTasks('project.relops.cloud-image-builder.decision.revision')['tasks']
task_shas = list(map(lambda task: task['namespace'].split('.')[-1], tasks))

repo_shas = map(lambda commit: commit['sha'], get_commits('mozilla-platform-ops', 'cloud-image-builder'))
print('- repo shas:')
for repo_sha in repo_shas:
  if repo_sha in task_shas:
    task = next(task for task in tasks if task['namespace'].split('.')[-1] == repo_sha)
    print('  - {} (task: {})'.format(repo_sha, task['taskId']))
  else:
    print('  - {}'.format(repo_sha))

print('- task shas ({}):'.format(len(task_shas)))
for task_sha in task_shas:
  print('  - {}'.format(task_sha))