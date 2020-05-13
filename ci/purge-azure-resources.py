import os
import sys
import taskcluster
import yaml
from azure.common.credentials import ServicePrincipalCredentials
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.resource import ResourceManagementClient

from cachetools import cached, TTLCache
cache = TTLCache(maxsize=100, ttl=300)


@cached(cache)
def get_instance(rg_name, vm_name):
  return computeClient.virtual_machines.instance_view(rg_name, vm_name)


def purge_filter(resource, resource_group_name = None):
  if resource.__class__.__name__ == 'ResourceGroup':
    return (
      resource.name.startswith('rg-')
      and '-us-' in resource.name
      and (
        resource.name.endswith('-gecko-1')
        or resource.name.endswith('-gecko-3')
        or resource.name.endswith('-gecko-t')
        or resource.name.endswith('-mpd001-1')
        or resource.name.endswith('-mpd001-3')
        or resource.name.endswith('-relops')
      )
    )
  else:
    print('no filter mechanism identified for {}'.format(resource.__class__.__name__))
    return False


if 'TASKCLUSTER_PROXY_URL' in os.environ:
  secretsClient = taskcluster.Secrets({ 'rootUrl': os.environ['TASKCLUSTER_PROXY_URL'] })
  secret = secretsClient.get('project/relops/image-builder/dev')['secret']['azure']
  print('secrets fetched using taskcluster proxy')
elif 'TASKCLUSTER_ROOT_URL' in os.environ and 'TASKCLUSTER_CLIENT_ID' in os.environ and 'TASKCLUSTER_ACCESS_TOKEN' in os.environ:
  secretsClient = taskcluster.Secrets(taskcluster.optionsFromEnvironment())
  secret = secretsClient.get('project/relops/image-builder/dev')['secret']['azure']
  print('secrets fetched using taskcluster environment credentials')
elif os.path.isfile('{}/.cloud-image-builder-secrets.yml'.format(os.environ['HOME'])):
  secret = yaml.safe_load(open('{}/.cloud-image-builder-secrets.yml'.format(os.environ['HOME']), 'r'))['azure']
  print('secrets obtained from local filesystem')
else:
  print('failed to obtain taskcluster secrets')
  exit(1)

azureCredentials = ServicePrincipalCredentials(client_id = secret['id'], secret = secret['key'], tenant = secret['account'])
computeClient = ComputeManagementClient(azureCredentials, secret['subscription'])
networkClient = NetworkManagementClient(azureCredentials, secret['subscription'])
resourceClient = ResourceManagementClient(azureCredentials, secret['subscription'])

allGroups = list(resourceClient.resource_groups.list())
targetGroups = sys.argv[1:] if len(sys.argv) > 1 else list(map(lambda x: x.name, filter(purge_filter, allGroups)))
resource_descriptors = {
  #'virtual machine': {
  #  'filter-descriptor': 'deallocated',
  #  'list': computeClient.virtual_machines.list,
  #  'purge': computeClient.virtual_machines.delete,
  #  'filter': lambda virtual_machine, resource_group_name: virtual_machine.provisioning_state == 'Succeeded' and any(status for status in get_instance(resource_group_name, virtual_machine.name).statuses if status.code == 'PowerState/deallocated')
  #},
  'network interface': {
    'filter-descriptor': 'orphaned',
    'list': networkClient.network_interfaces.list,
    'purge': networkClient.network_interfaces.delete,
    'filter': lambda network_interface, resource_group_name: network_interface.virtual_machine is None
  },
  'public ip address': {
    'filter-descriptor': 'orphaned',
    'list': networkClient.public_ip_addresses.list,
    'purge': networkClient.public_ip_addresses.delete,
    'filter': lambda public_ip_address, resource_group_name: public_ip_address.ip_address is None
  },
  'disk': {
    'filter-descriptor': 'orphaned',
    'list': computeClient.disks.list_by_resource_group,
    'purge': computeClient.disks.delete,
    'filter': lambda disk, resource_group_name: disk.disk_state == 'Unattached'
  }
  #,
  # commented out because this filter does not work for resource groups that have multiple worker types (eg: gecko-t). need to also filter on worker type.
  #'image': {
  #  'filter-descriptor': 'orphaned',
  #  'list': computeClient.images.list_by_resource_group,
  #  'purge': computeClient.images.delete,
  #  # filter below will delete all images that have deploymentId and machineImageCommitTime tags, except the two most recent images that have deploymentId and machineImageCommitTime tags
  #  'filter': lambda image, resource_group_name: image.tags and 'deploymentId' in image.tags and 'machineImageCommitTime' in image.tags and image.name not in list(map(lambda ni: ni.name, list(sorted(filter(lambda i: i.tags and 'deploymentId' in i.tags and 'machineImageCommitTime' in i.tags, computeClient.images.list_by_resource_group(resource_group_name)), key = lambda x: x.tags['machineImageCommitTime'], reverse = True))[0:2]))
  #}
}

print('scanning subscription (total resource groups: {}, target resource groups: {}): '.format(len(allGroups), len(targetGroups)))
for group in targetGroups:
  print('- scanning resource group {}:'.format(group))
  for resource_type, resource_descriptor in resource_descriptors.items():
    all_resources = list(resource_descriptor['list'](**{'resource_group_name': group}))
    filtered_resources = list(filter(lambda x: resource_descriptor['filter'](x, group), all_resources))
    print('  - {}{}:'.format(resource_type, 'es' if resource_type[-1] == 's' else 's'))
    print('    - total: {}'.format(len(all_resources)))
    print('    - {}: {}'.format(resource_descriptor['filter-descriptor'], len(filtered_resources)))
    for resource_item in filtered_resources:
      try:
        resource_descriptor['purge'](*[group, resource_item.name])
        print('      - deleted: {}'.format(resource_item.name))
      except BaseException as e:
        print('      - failed to delete: {}. {}'.format(resource_item.name, str(e)))
