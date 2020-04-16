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


def purge_filter(resource_type, resource_group, resource):
  if resource_type == 'virtual machine':
    return resource.provisioning_state == 'Succeeded' and any(status for status in get_instance(resource_group, resource.name).statuses if status.code == 'PowerState/deallocated')
  elif resource_type == 'network interface':
    return resource.virtual_machine is None
  elif resource_type == 'public ip address':
    return resource.ip_address is None
  elif resource_type == 'disk':
    return resource.disk_state == 'Unattached'
  else:
    return False


def purge_action(resource_type, resource_group, resource_name):
  if resource_type == 'virtual machine':
    computeClient.virtual_machines.delete(resource_group, resource_name)
  elif resource_type == 'network interface':
    networkClient.network_interfaces.delete(resource_group, resource_name)
  elif resource_type == 'public ip address':
    networkClient.public_ip_addresses.delete(resource_group, resource_name)
  elif resource_type == 'disk':
    computeClient.disks.delete(resource_group, resource_name)


if 'TASKCLUSTER_PROXY_URL' in os.environ:
  secretsClient = taskcluster.Secrets({ 'rootUrl': os.environ['TASKCLUSTER_PROXY_URL'] })
  secret = secretsClient.get('project/relops/image-builder/dev')['secret']['azure']
elif os.path.isfile('{}/.cloud-image-builder-secrets.yml'.format(os.environ['HOME'])):
  secret = yaml.safe_load(open('{}/.cloud-image-builder-secrets.yml'.format(os.environ['HOME']), 'r'))['azure']
else:
  exit(1)

azureCredentials = ServicePrincipalCredentials(client_id = secret['id'], secret = secret['key'], tenant = secret['account'])
computeClient = ComputeManagementClient(azureCredentials, secret['subscription'])
networkClient = NetworkManagementClient(azureCredentials, secret['subscription'])
resourceClient = ResourceManagementClient(azureCredentials, secret['subscription'])

allGroups = list(resourceClient.resource_groups.list())
targetGroups = sys.argv[1:] if len(sys.argv) > 1 else list(map(lambda x: x.name, filter(relops_resource_group_filter, allGroups)))

print('scanning subscription (total resource groups: {}, target resource groups: {}): '.format(len(allGroups), len(targetGroups)))


for group in targetGroups:
  print('- scanning resource group {}:'.format(group))
  resources = [
    {
      'type-singular': 'virtual machine',
      'type-plural': 'virtual machines',
      'filter-descriptor': 'deallocated',
      'list': computeClient.virtual_machines.list(group)
    },
    {
      'type-singular': 'network interface',
      'type-plural': 'network interfaces',
      'filter-descriptor': 'orphaned',
      'list': networkClient.network_interfaces.list(group)
    },
    {
      'type-singular': 'public ip address',
      'type-plural': 'public ip addresses',
      'filter-descriptor': 'orphaned',
      'list': networkClient.public_ip_addresses.list(group)
    },
    {
      'type-singular': 'disk',
      'type-plural': 'disks',
      'filter-descriptor': 'orphaned',
      'list': computeClient.disks.list_by_resource_group(group)
    }
  ]
  for resource in resources:
    all_resources = list(resource['list'])
    filtered_resources = list(filter(lambda x: purge_filter(resource['type-singular'], group, x), all_resources))
    print('  - {}:'.format(resource['type-plural']))
    print('    - total: {}'.format(len(all_resources)))
    print('    - {}: {}'.format(resource['filter-descriptor'], len(filtered_resources)))
    for resource_item in filtered_resources:
      purge_action(resource['type-singular'], group, resource_item.name)
      print('      - deleted: {}'.format(resource_item.name))
