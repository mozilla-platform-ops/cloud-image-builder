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


def deallocated_vm_filter(rg, vm):
  if vm.provisioning_state != 'Succeeded':
    return False
  return (
    vm.provisioning_state == 'Succeeded'
    and any(status for status in get_instance(rg, vm.name).statuses if status.code == 'PowerState/deallocated')
  )


def orphaned_ni_filter(rg, ni):
  return ni.virtual_machine is None


def orphaned_pia_filter(rg, pia):
  return pia.ip_address is None


def orphaned_disk_filter(rg, disk):
  return disk.disk_state == 'Unattached'


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

  allVirtualMachines = list(computeClient.virtual_machines.list(group))
  deallocatedVirtualMachines = list(filter(lambda vm: deallocated_vm_filter(group, vm), allVirtualMachines))
  print('  - total virtual machines: {}, deallocated virtual machines: {}'.format(len(allVirtualMachines), len(deallocatedVirtualMachines)))
  for vm in deallocatedVirtualMachines:
    print('    - deallocated virtual machine: {}'.format(vm.name))
    computeClient.virtual_machines.delete(group, vm.name)
    print('      deleted deallocated virtual machine {}'.format(vm.name))

  allNetworkInterfaces = list(networkClient.network_interfaces.list(group))
  orphanedNetworkInterfaces = list(filter(lambda ni: orphaned_ni_filter(group, ni), allNetworkInterfaces))
  print('  - total network interfaces: {}, orphaned network interfaces: {}'.format(len(allNetworkInterfaces), len(orphanedNetworkInterfaces)))
  for ni in orphanedNetworkInterfaces:
    print('    - orphaned network interface: {}'.format(ni.name))
    networkClient.network_interfaces.delete(group, ni.name)
    print('      deleted orphaned network interface {}'.format(ni.name))

  allPublicIpAddresses = list(networkClient.public_ip_addresses.list(group))
  orphanedPublicIpAddresses = list(filter(lambda pia: orphaned_pia_filter(group, pia), allPublicIpAddresses))
  print('  - total public ip addresses: {}, orphaned public ip addresses: {}'.format(len(allPublicIpAddresses), len(orphanedPublicIpAddresses)))
  for pia in orphanedPublicIpAddresses:
    print('    - orphaned public ip address: {}'.format(pia.name))
    networkClient.public_ip_addresses.delete(group, pia.name)
    print('      deleted orphaned public ip address {}'.format(pia.name))

  allDisks = list(computeClient.disks.list_by_resource_group(group))
  orphanedDisks = list(filter(lambda disk: orphaned_disk_filter(group, disk), allDisks))
  print('  - total disks: {}, orphaned disks: {}'.format(len(allDisks), len(orphanedDisks)))
  for disk in orphanedDisks:
    print('    - orphaned disk: {}'.format(disk.name))
    computeClient.disks.delete(group, disk.name)
    print('      deleted orphaned disk {}'.format(disk.name))