# Scripts

## purge-deprecated-azure-resources.ps1

* Cache the following powershell modules using psmodulecache@v5.1

```PowerShell
Az.Compute
Az.Network
Az.Resource
Az.Storage
Powershell-yaml
```

* Connect to Azure Subscription and set context
* Get any resource groups that Contains "-us-" or ends with '-gecko-1','-gecko-3','-gecko-t','-relops','-mpd001-1','-mpd001-3'

* If deallocated VMs are found, remove it.
* If any network interface is not bound to a virtual machien, remove it.
* If any public ip addresses are not assigned, remove them.
* If any of the resource groups above contain a network security group with no network interfaces, remove it.
* If any of the resource groups above contain a virtual network without subnets, remove it.
* If any of the resource groups above contain an unattached disk, remove it.
* If any of the resource groups above contain snapshots, remove them. Determine how long to keep them.
* If any of the resource groups above contain AzImage older than X commit, remove them. Maybe use existing method to query git commit hash?
