import taskcluster
import yaml

workerPoolId = 'relops/win2019'
workerManager = taskcluster.WorkerManager(taskcluster.optionsFromEnvironment())

with open('ci/config/worker-pool.yaml', 'r') as stream:
  payload = yaml.safe_load(stream)
  try:
    workerManager.workerPool(workerPoolId = workerPoolId)
    print('info: worker pool {} existence detected'.format(workerPoolId))
    workerManager.updateWorkerPool(workerPoolId, payload)
    print('info: worker pool {} updated'.format(workerPoolId))
  except:
    print('info: worker pool {} absence detected'.format(workerPoolId))
    workerManager.createWorkerPool(workerPoolId, payload)
    print('info: worker pool {} created'.format(workerPoolId))

