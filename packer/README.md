# Cloud image builder image creation through Packer

## Overview

This is stub off of Cloud Image Builder (CIB) to use Packer to create managed images for Azure CI workers. For reference of the Packer pieces see Microsoft's [build-image-with-packer](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/build-image-with-packer) documentation. 

## Getting Started
The syntax to create a managed image build will look similar to:
```
git commit --allow-empty -m "check for gw process after start" -m "overwrite-machine-image" -m "include environments: production" -m "include keys:win10-64-2004-gpu"
```

This follows the syntax as defined in the [readme.md](https://github.com/mozilla-platform-ops/cloud-image-builder/blob/main/readme.md) that is found in the root of this repo.

If CIB uses packer or not is determined by the `key` value in the syntax. This decision is performed in ci/create-image-build-tasks.py at line [200](https://github.com/mozilla-platform-ops/cloud-image-builder/blob/26bbf54f4acf2e06cda25885167bc3b85940eae7/ci/create-image-build-tasks.py#L200) or close to there depending on future changes. 
```
for KEY in includeKeys:
    is_packer = True if KEY in ['win10-64-2004-test', 'win10-64-2004-gpu', 'win10-64-2004', 'win10-64-2004-gpu-test'] else False
```

## How it works

If CIB determines if it is a Packer build it will run [create](https://github.com/mozilla-platform-ops/cloud-image-builder/blob/26bbf54f4acf2e06cda25885167bc3b85940eae7/ci/create-image-build-tasks.py#L211) a task to run [packer\build-packer-image.ps1](https://github.com/mozilla-platform-ops/cloud-image-builder/blob/main/packer/build-packer-image.ps1) and pass the location and keys names to the script. Also note that this script is specifically for use with [Ronin Puppet's](https://github.com/mozilla-platform-ops/ronin_puppet) Azure bootstrap script. To be used elsewhere it will need to be pointed at a different json template file. More information below on this files. 

The script will determine values needed for the build and then set them as environment variables. It pulls these values from two different data sets. 

The first is a yaml file that will need to be named as the value of the key that is passed and must be present in [cloud-image-builder/packer/config/](https://github.com/mozilla-platform-ops/cloud-image-builder/tree/main/packer/config). 

For example `win10-64-2004-gpu.yaml`
```
---
image:
    publisher: MicrosoftWindowsDesktop
    offer: Windows-10
    sku: 20h1-evd
azure:
    managed_image_resource_group_name: rg-packer-through-cib
    managed_image_storage_account_type: Standard_LRS
    build_location: eastus
    locations:
        - northcentralus
        - southcentralus
        - eastus
        - northeurope
        - westeurope
vm:
    size: Standard_NV6
    disk_additional_size: 30
    tags:
        workerType: gecko-t-win10-64-2004-gpu
        sourceOrganisation: mozilla-platform-ops
        sourceRepository: ronin_puppet
        sourceRevision: cloud_windows
        deploymentId: 5db26eb
        managed_by: packer
```

`image` This is the information that PAcker will need to find the starting image in the Azure Market Place.

`azure` This is the information Packer will need to know where and with what resources to use when building the image.

`vm.tags` The [Ronin Puppet](https://github.com/mozilla-platform-ops/ronin_puppet) bootstrap script will be looking for these values. 

`vm.tags.workertype` This will determine which role Ronin Puppet will configure the image for. 

`vm.tags.source*` This will determine which repo and branch to pull the Puppet library from

`vm.tags.deploymentId` This will determine the Git hash in which the image will be locked to.

`vm.tags.managed_by` This allows Ronin Puppet scripts to determine if it is an image capture run, or if it is being ran on a TC worker.


The other data set is pull from Taskcluster secrets:

`     $secret = (Invoke-WebRequest -Uri ('{0}/secrets/v1/secret/project/relops/image-builder/dev' -f $env:TASKCLUSTER_PROXY_URL) -UseBasicParsing | ConvertFrom-Json).secret;`


There must be 4 entries found in the secrets:

`relops_azure.packer.app_id` This will be the app registration for Packer to run in Azure

`relops_azure.packer.password` The secret for the app registration.

`relops_azure.tenant_id` and `.relops_azure.subscription_id` Which are related to the Azure account Packer is being ran in. 


The script will parse this data and concat other data and create environment variables. It will then run the packer command:

`powershell .\packer.exe build -force $PSScriptRoot\packer-json-template.json`



Packer will pull information from the json file to determine the what, where, and how of the build. 

The variable section takes the environment variables defined in the script and assigns them as local variables. 

```
{
  "variables": {
    "client_id": "{{env `client_id`}}",
    "client_secret": "{{env `client_secret`}}",
	"tenant_id": "{{env `tenant_id`}}",
	"subscription_id": "{{env `subscription_id`}}",
	
	"image_publisher": "{{env `image_publisher`}}",
	"image_offer": "{{env `image_offer`}}",
	"image_sku": "{{env `image_sku`}}",
	
	"managed_image_name": "{{env `managed_image_name`}}",
	"managed_image_resource_group_name": "{{env `managed_image_resource_group_name`}}",
	
	"temp_resource_group_name": "{{env `temp_resource_group_name`}}",
	"managed_image_storage_account_type": "{{env `managed_image_storage_account_type`}}",
	
	"Project": "{{env `Project`}}",
	"workerType": "{{env `workerType`}}",
	"sourceOrganisation": "{{env `sourceOrganisation`}}",
	"sourceRepository": "{{env `sourceRepository`}}",
	"sourceRevision": "{{env `sourceRevision`}}",
	"deploymentId": "{{env `deploymentId`}}",
	"managed-by": "{{env `managed_by`}}",
	
	"location": "{{env `location`}}",
	"vm_size": "{{env `vm_size`}}",
	"disk_additional_size": "{{env `disk_additional_size`}}"
	
  },

```

The builder section provides the Azure specific information.
```

  "builders": [
    {
      "type": "azure-arm",
        
      "client_id": "{{user `client_id`}}",
      "client_secret": "{{user `client_secret`}}",
      "tenant_id": "{{user `tenant_id`}}",
      "subscription_id": "{{user `subscription_id`}}",

      "os_type": "Windows",
      "managed_image_name": "{{user `managed_image_name`}}",
      "managed_image_resource_group_name": "{{user `managed_image_resource_group_name`}}",
      
      "image_publisher": "{{user `image_publisher`}}",
      "image_offer": "{{user `image_offer`}}",
      "image_sku": "{{user `image_sku`}}",
      "communicator": "winrm",
      "winrm_use_ssl": "true",
      "winrm_insecure": "true",
      "winrm_timeout": "3m",
      "winrm_username": "packer",

      "managed_image_storage_account_type": "{{user `managed_image_storage_account_type`}}",
      "temp_resource_group_name": "{{user `temp_resource_group_name`}}",
      "virtual_network_name": "",
      "virtual_network_subnet_name": "",
      "private_virtual_network_with_public_ip": "True",
      "virtual_network_resource_group_name": "",
      "azure_tags": {
          "Project": "{{user `Project`}}",
		  "workerType": "{{user `workerType`}}",
		  "sourceOrganisation": "{{user `sourceOrganisation`}}",
		  "sourceRepository": "{{user `sourceRepository`}}",
		  "sourceRevision": "{{user `sourceRevision`}}",
		  "deploymentId": "{{user `deploymentId`}}"
	  },	
      "location": "{{user `location`}}",
      "vm_size": "{{user `vm_size`}}",
      "disk_additional_size": [
        "{{user `disk_additional_size`}}"
       ],

      "async_resourcegroup_delete":true
    }
  ],
  ```
  
  The provisioners section provides Packer with the direction to configure the machine. 
  
  ```
    "provisioners": [
    {
      "type": "powershell",
      "inline": [
          "$ErrorActionPreference='Stop'",

          "Invoke-Expression ((New-Object -TypeName net.webclient).DownloadString('https://chocolatey.org/install.ps1'))",
          "& choco feature enable -n allowGlobalConfirmation",
          "Write-Host \"Chocolatey Installed.\""
      ]
    },
    {
	  "type": "powershell",
	  "elevated_user": "SYSTEM",
	  "elevated_password": "",
	  "inline": [
	    "Invoke-Expression ((New-Object -TypeName net.webclient).DownloadString('https://raw.githubusercontent.com/mozilla-platform-ops/ronin_puppet/cloud_windows/provisioners/windows/azure/azure-bootstrap.ps1'))"
	  ]
	},
    {
      "type": "windows-restart"
    },
    {
	  "type": "powershell",
	  "elevated_user": "SYSTEM",
	  "elevated_password": "",
	  "inline": [
	    "Invoke-Expression ((New-Object -TypeName net.webclient).DownloadString('https://raw.githubusercontent.com/mozilla-platform-ops/ronin_puppet/cloud_windows/provisioners/windows/azure/azure-bootstrap.ps1'))"
	  ]
	},
    {
      "type": "windows-restart"
    },
    
  ```

Basicly it will download the Ronin Puppet Bootstrap script and run it multiple times. The provisioners do not have any error handling, and exits will only result in zero and non zero. Becuas eof this we rely on the bootstrap script to exit with a non zero if something goes wrong, or if everything is good continue to exit with zero as it steps through each of its stages.

The final part of the provsioner sectionn will set registry entries so that Ronin Puppet scripts know that Packer and Bootstraping has been completed, will pause the Azure VM agent, and sysprep the image. 
```
      "type": "powershell",
      "inline": [
        "$stage =  ((Get-ItemProperty -path HKLM:\\SOFTWARE\\Mozilla\\ronin_puppet).bootstrap_stage)",
        "If ($stage -ne 'complete') { exit 2}",
        "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Mozilla\\ronin_puppet' -name hand_off_ready -type  string -value yes",
		" # NOTE: the following *3* lines are only needed if the you have installed the Guest Agent.",
        "  while ((Get-Service RdAgent).Status -ne 'Running') { Start-Sleep -s 5 }",
        "  while ((Get-Service WindowsAzureTelemetryService).Status -ne 'Running') { Start-Sleep -s 5 }",
        "  while ((Get-Service WindowsAzureGuestAgent).Status -ne 'Running') { Start-Sleep -s 5 }",

        "if( Test-Path $Env:SystemRoot\\windows\\system32\\Sysprep\\unattend.xml ){ rm $Env:SystemRoot\\windows\\system32\\Sysprep\\unattend.xml -Force}",
        "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit",
        "while($true) { $imageState = Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State | Select ImageState; if($imageState.ImageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { Write-Output $imageState.ImageState; Start-Sleep -s 10  } else { break } }"
      ]
    }
    
```    
   
   
  After this Packer will capture the image with a name based off of ``{{env `managed_image_name`}}``. 
