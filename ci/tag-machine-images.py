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


images = azureComputeManagementClient.images.list_by_resource_group(group)
pattern = re.compile('^{}-{}-([a-z0-9]{{7}})$'.format(group.replace('rg-', ''), key))
for image in [x for x in images if pattern.match(x.name)]:
  print(image)