import os
import re
import taskcluster
from azure.common.credentials import ServicePrincipalCredentials
from azure.mgmt.compute import ComputeManagementClient

secretsClient = taskcluster.Secrets({ 'rootUrl': os.environ['TASKCLUSTER_PROXY_URL'] })
secret = secretsClient.get('project/relops/image-builder/dev')['secret']

azureComputeManagementClient = ComputeManagementClient(
  ServicePrincipalCredentials(
    client_id = secret['azure']['id'],
    secret = secret['azure']['key'],
    tenant = secret['azure']['account']),
  secret['azure']['subscription'])


platform = os.getenv('platform')
group = os.getenv('group')
key = os.getenv('key')

print('platform: {}'.format(platform))
print('group: {}'.format(group))
print('key: {}'.format(key))


pattern = re.compile('^{}-{}-([a-z0-9]{{7}})$'.format(group.replace('rg-', ''), key))
images = [x for x in azureComputeManagementClient.images.list_by_resource_group(group) if pattern.match(x.name)]
for image in images:
  revision = pattern.search(image.name).group(1)
  print('image: {}, has revision: {}'.format(image.name, revision))
  if image.tags:
    print(', '.join(['%s:: %s' % (key, value) for (key, value) in image.tags.items()]))
  else:
    print('image has no tags')