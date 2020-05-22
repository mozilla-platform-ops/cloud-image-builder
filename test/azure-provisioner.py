import os
import random
import string
import taskcluster
import uuid
import yaml
from azure.common.credentials import ServicePrincipalCredentials
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.resource import ResourceManagementClient


def provision(provisionerId, workerType, runningWorkers, regions, machine, minCapacity, maxCapacity):
    print('provisioning {}/{}'.format(provisionerId, workerType))
    pendingTaskCount = taskclusterQueueClient.pendingTasks(provisionerId, workerType)['pendingTasks']
    print('    - {} pending tasks'.format(pendingTaskCount))
    print('    - {} total workers (according to azure api)'.format(len(runningWorkers)))
    workers = taskclusterQueueClient.listWorkers(
        provisionerId,
        workerType,
        continuationToken = None,
        limit = 1000,
        quarantined = False)['workers']
    print('    - {} total workers (according to taskcluster queue)'.format(len(workers)))
    activeWorkers = list(filter(lambda worker: 'latestTask' in worker, workers))
    inactiveWorkers = list(filter(lambda worker: 'latestTask' not in worker, workers))
    print('    - {} inactive workers (according to taskcluster queue)'.format(len(inactiveWorkers)))
    if pendingTaskCount > 0 or minCapacity > len(runningWorkers):
        spawnMinion(provisionerId, workerType, random.choice(regions), machine)


def getMinions():
    minions = {}
    locations = []
    for pool in azureWorkerPools:
        provisionerId, workerType = pool['name'].split('/', 2)
        minions[provisionerId] = {}
        minions[provisionerId][workerType] = []
        for region in pool['regions']:
            location = region.replace(' ', '').lower()
            if location not in locations:
                locations.append(location)
    for location in locations:
        vmsInLocation = azureComputeManagementClient.virtual_machines.list_by_location(location)
        for provisionerId in minions.keys():
            for workerType in minions[provisionerId].keys():
                for vm in filter(lambda vm: 'provisionerId' in vm.tags and 'workerType' in vm.tags and vm.tags.get('provisionerId') == provisionerId and vm.tags.get('workerType') == workerType, vmsInLocation):
                    minions[provisionerId][workerType].append(vm)
    return minions


def spawnMinion(provisionerId, workerType, region, machine):
    location = region.replace(' ', '').lower()
    locationAsPrefix = region.replace(' ', '-').lower()
    image = next(i for i in azureComputeManagementClient.images.list() if i.provisioning_state == 'Succeeded' and i.name.startswith('{}-{}-{}-'.format(locationAsPrefix, provisionerId, workerType.replace('-azure', ''))))
    resourceId = str(uuid.uuid1())[-12:]
    resourceGroupName = 'rg-{}-{}'.format(locationAsPrefix, provisionerId)
    availabilitySetName = 'as-{}-{}'.format(locationAsPrefix, provisionerId)
    virtualNetworkName = 'vn-{}-{}'.format(locationAsPrefix, provisionerId)
    subnetName = 'sn-{}-{}'.format(locationAsPrefix, provisionerId)
    publicIpName = 'ip-{}'.format(resourceId)
    networkInterfaceName = 'ni-{}'.format(resourceId)
    IpConfigurationName = 'ic-{}'.format(resourceId)
    virtualMachineName = 'vm-{}'.format(resourceId)

    print('    - initiating minion spawn of instance: {} from image: {}'.format(virtualMachineName, image.name))

    resourceGroup = azureResourceManagementClient.resource_groups.create_or_update(
        resourceGroupName,
        {
            'location': location
        }
    )

    availabilitySet = azureComputeManagementClient.availability_sets.create_or_update(
        resourceGroupName,
        availabilitySetName,
        {
            'location': location,
            'sku': {
                'name': 'Aligned'
            },
            'platform_fault_domain_count': 3
        }
    )

    publicIp = azureNetworkManagementClient.public_ip_addresses.create_or_update(
        resourceGroupName,
        publicIpName,
        {
            'location': location,
            'public_ip_allocation_method': 'Dynamic'
        }
    ).result()
    
    try:
        virtualNetwork = azureNetworkManagementClient.virtual_networks.get(resourceGroupName, virtualNetworkName)
    except:
        virtualNetwork = azureNetworkManagementClient.virtual_networks.create_or_update(
            resourceGroupName,
            virtualNetworkName,
            {
                'location': location,
                'address_space': {
                    'address_prefixes': ['10.0.0.0/24']
                }
            }
        ).result()
    try:
        subnet = azureNetworkManagementClient.subnets.get(resourceGroupName, virtualNetworkName, subnetName)
    except:
        subnet = azureNetworkManagementClient.subnets.create_or_update(
            resourceGroupName,
            virtualNetworkName,
            subnetName,
            {
                'address_prefix': '10.0.0.0/24'
            }
        ).result()

    networkInterface = azureNetworkManagementClient.network_interfaces.create_or_update(
        resourceGroupName,
        networkInterfaceName,
        {
            'location': location,
            'ip_configurations': [
                {
                    'name': IpConfigurationName,
                    'public_ip_address': publicIp,
                    'subnet': {
                        'id': subnet.id
                    }
                }
            ]
        }
    ).result()

    virtualMachine = azureComputeManagementClient.virtual_machines.create_or_update(
        resourceGroupName,
        virtualMachineName,
        {
            'location': location,
            'tags': {
                'machineImage': image.name,
                'workerPool': '{}/{}'.format(provisionerId, workerType),
                'workerType': '{}-{}'.format(provisionerId, workerType.replace('win2012', 'b-win2012')),
                'sourceOrganisation': 'mozilla-releng',
                'sourceRepository': 'OpenCloudConfig',
                'sourceRevision': 'azure'
            },
            'os_profile': {
                'computer_name': virtualMachineName,
                'admin_username': 'azureuser',
                'admin_password': ''.join(random.choice(string.ascii_letters + string.digits + string.punctuation) for _ in range(16))
            },
            'hardware_profile': {
                'vm_size': machine
            },
            'storage_profile': {
                'image_reference': {
                    'id': image.id
                },
                'os_disk': {
                    'name': 'vm-{}_disk1'.format(resourceId),
                    'create_option': 'FromImage',
                    'caching': 'ReadWrite',
                    'managed_disk': {
                        'storage_account_type': 'Standard_LRS'
                    }
                },
                'data_disks': [
                    {
                        'lun': 0,
                        'disk_size_gb': 128,
                        'create_option': 'Empty'
                    },
                    {
                        'lun': 1,
                        'disk_size_gb': 128,
                        'create_option': 'Empty'
                    }
                ]
            },
            'network_profile': {
                'network_interfaces': [
                    {
                        'id': networkInterface.id
                    }
                ]
            },
            'availability_set': {
                'id': availabilitySet.id
            }
        }
    ).result()
    print('        virtual machine: {} created in resource group: {}'.format(virtualMachine.name, resourceGroup.name))


# init taskcluster clients
taskclusterQueueClient = taskcluster.Queue(taskcluster.optionsFromEnvironment())
# init azure clients
azureConfig = yaml.safe_load(open('{}/.azure.yaml'.format(os.getenv('HOME')), 'r'))
azureCredentials = ServicePrincipalCredentials(
    client_id = azureConfig['client_id'],
    secret = azureConfig['secret'],
    tenant = azureConfig['tenant'])
azureComputeManagementClient = ComputeManagementClient(
    azureCredentials,
    azureConfig['subscription'])
azureNetworkManagementClient = NetworkManagementClient(
    azureCredentials,
    azureConfig['subscription'])
azureResourceManagementClient = ResourceManagementClient(
    azureCredentials,
    azureConfig['subscription'])


# provision until interrupted [ctrl + c]
try:
    while True:
        azureWorkerPools = yaml.safe_load(open('{}/azure-worker-pools.yaml'.format(os.path.dirname(__file__)), 'r'))
        minions = getMinions()
        for provisionerId in minions.keys():
            for workerType in minions[provisionerId].keys():
                pool = next(p for p in azureWorkerPools if p['name'] == '{}/{}'.format(provisionerId, workerType))
                provision(provisionerId, workerType, minions[provisionerId][workerType], pool['regions'], pool['machine'], pool['capacity']['min'], pool['capacity']['max'])
except KeyboardInterrupt:
    pass
