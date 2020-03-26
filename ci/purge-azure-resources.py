import os
import sys
import taskcluster
import yaml
from azure.common.credentials import ServicePrincipalCredentials
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.resource import ResourceManagementClient

def relops_resource_group_filter(rg):
  return (
    rg.name.startswith('rg-')
    and '-us-' in rg.name
    and (
      rg.name.endswith('-gecko-1')
      or rg.name.endswith('-gecko-3')
      or rg.name.endswith('-gecko-t')
      or rg.name.endswith('-mpd001-1')
      or rg.name.endswith('-mpd001-3')
      or rg.name.endswith('-relops')
    )
  )


if 'TASKCLUSTER_PROXY_URL' in os.environ:
  secretsClient = taskcluster.Secrets({ 'rootUrl': os.environ['TASKCLUSTER_PROXY_URL'] })
  secret = secretsClient.get('project/relops/image-builder/dev')['secret']['azure']
elif os.path.isfile('{}/.cloud-image-builder-secrets.yml'.format(os.environ['HOME'])):
  secret = yaml.safe_load(open('{}/.cloud-image-builder-secrets.yml'.format(os.environ['HOME']), 'r'))['azure']
else:
  exit(1)

azureCredentials = ServicePrincipalCredentials(client_id = secret['id'], secret = secret['key'], tenant = secret['account'])
computeClient = ComputeManagementClient(azureCredentials, secret['subscription'])
resourceClient = ResourceManagementClient(azureCredentials, secret['subscription'])

groups = sys.argv[1:] if len(sys.argv) > 1 else map(lambda x: x.name, filter(relops_resource_group_filter, resourceClient.resource_groups.list()))
print('groups: {}'.format(', '.join(groups)))