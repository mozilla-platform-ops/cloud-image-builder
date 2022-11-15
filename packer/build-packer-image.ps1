<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>
param (
  [Parameter(Mandatory = $true)]
  [string] $location=$args[0],
  [string] $yaml_file=$args[1]
)

function Write-Log {
  param (
    [string] $message,
    [string] $severity = 'INFO',
    [string] $source = 'BootStrap',
    [string] $logName = 'Application'
  )
  if (!([Diagnostics.EventLog]::Exists($logName)) -or !([Diagnostics.EventLog]::SourceExists($source))) {
    New-EventLog -LogName $logName -Source $source
  }
  switch ($severity) {
    'DEBUG' {
      $entryType = 'SuccessAudit'
      $eventId = 2
      break
    }
    'WARN' {
      $entryType = 'Warning'
      $eventId = 3
      break
    }
    'ERROR' {
      $entryType = 'Error'
      $eventId = 4
      break
    }
    default {
      $entryType = 'Information'
      $eventId = 1
      break
    }
  }
  Write-EventLog -LogName $logName -Source $source -EntryType $entryType -Category 0 -EventID $eventId -Message $message
  if ([Environment]::UserInteractive) {
    $fc = @{ 'Information' = 'White'; 'Error' = 'Red'; 'Warning' = 'DarkYellow'; 'SuccessAudit' = 'DarkGray' }[$entryType]
    Write-Host  -object $message -ForegroundColor $fc
  }
}
function Build-PackerImage {
  param (
    [Parameter(Mandatory = $true)]
    [string] $location=$arg[0],
    [string] $yaml_file=$args[1]
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }

  process {

     Install-Module powershell-yaml -force
     
     # This ymal file is stripped down to what Packer needs for dev and testing
     # Though hard coded now it should proablaly be a variable that is passed a parameter to the function. 
     # For now push using "include pools: gecko-t/win10-64-azure" with the needed yaml file uncommented below
      
     #$yaml_file = 'win10-64-2004-gpu.yaml'
     #$yaml_file = 'win10-64-2004-gpu-test.yaml'
     #$yaml_file = 'win10-64-2004.yaml'
     #$yaml_file = 'win10-64-2004-test.yaml'

     $yaml_data = (Get-Content -Path (Join-Path -Path $PSScriptRoot\config -ChildPath $yaml_file) -Raw | ConvertFrom-Yaml)

     # Get taskcluster secrets
     $secret = (Invoke-WebRequest -Uri ('{0}/secrets/v1/secret/project/relops/image-builder/dev' -f $env:TASKCLUSTER_PROXY_URL) -UseBasicParsing | ConvertFrom-Json).secret;
     # Random string for temp resource group. Prevent duplicate names in an event of a bad build
     $random = (get-random -Maximum 999)
     
     $Env:client_id = $secret.relops_azure.packer.app_id
     $Env:client_secret = $secret.relops_azure.packer.password
     $Env:tenant_id = $secret.relops_azure.tenant_id
     $Env:image_publisher = $yaml_data.image.publisher
     $Env:image_offer = $yaml_data.image.offer
     $Env:image_sku = $yaml_data.image.sku
     $Env:managed_image_resource_group_name = $yaml_data.azure.managed_image_resource_group_name
     $Env:managed_image_storage_account_type = $yaml_data.azure.managed_image_storage_account_type
     $Env:Project = $yaml_data.vm.tags.Project
     #$Env:workerType = $yaml_data.vm.tags.workerType
     $Env:base_image = $yaml_data.vm.tags.base_image
     $Env:worker_pool_id = $yaml_data.vm.tags.worker_pool_id
     #$worker_pool = ($yaml_data.vm.tags.worker_pool_id.replace('/','-'))
     $worker_pool =$yaml_data.vm.tags.worker_pool_id
     $Env:sourceOrganisation = $yaml_data.vm.tags.sourceOrganisation
     $Env:sourceRepository = $yaml_data.vm.tags.sourceRepository
     #$Env:sourceRevision = $yaml_data.vm.tags.sourceRevision
     $Env:sourceBranch = $yaml_data.vm.tags.sourceBranch
     $Env:bootstrapscript = ('https://raw.githubusercontent.com/{0}/{1}/{2}/provisioners/windows/azure/azure-bootstrap.ps1' -f  $Env:sourceOrganisation, $Env:sourceRepository, $Env:sourceBranch)
     $Env:deploymentId = $yaml_data.vm.tags.deploymentId
     $Env:managed_by = $yaml_data.vm.tags.managed_by
     $Env:location = $location
     $Env:vm_size = $yaml_data.vm.size
     $Env:disk_additional_size = $yaml_data.vm.disk_additional_size
     $Env:managed_image_name = ('{0}-{1}-{2}-{3}' -f $worker_pool, $location, $yaml_data.image.sku, $yaml_data.vm.tags.deploymentId)
     $Env:temp_resource_group_name = ('{0}-{1}-{2}-{3}-tmp3' -f $worker_pool, $location, $yaml_data.vm.tags.deploymentId, $random)
     # alpha 2 is temp. Should be removed in the future
     if (($yaml_file -like "*alpha2*" )) {
        $Env:managed_image_name = ('{0}-{1}-{2}-alpha2' -f $worker_pool, $location, $yaml_data.image.sku)
     } elseif (($yaml_file -like "*alpha*" )) {
        $Env:managed_image_name = ('{0}-{1}-{2}-alpha' -f $worker_pool, $location, $yaml_data.image.sku)
     } elseif (($yaml_file -like "*next*" )) {
        $Env:managed_image_name = ('{0}-{1}-{2}-next' -f $worker_pool, $location, $yaml_data.image.sku)
     } else {
        $Env:managed_image_name = ('{0}-{1}-{2}-{3}' -f $worker_pool, $location, $yaml_data.image.sku, $yaml_data.vm.tags.deploymentId)
     }
     if (($yaml_file -like "trusted*" )) {
        $Env:subscription_id = $secret.relops_azure.trusted_subscription_id
     } else {
        $Env:subscription_id = $secret.relops_azure.subscription_id
     }


     (New-Object Net.WebClient).DownloadFile('https://cloud-image-builder.s3.us-west-2.amazonaws.com/packer.exe', '.\packer.exe')
     #powershell .\packer.exe build -force $PSScriptRoot\packer-json-template.json
     #.\packer.exe build -force $PSScriptRoot\packer-json-template.json
     if (($yaml_file -like "*2012*" )) {
        .\packer.exe build -force $PSScriptRoot\2012-packer-json-template.json
     } else {
        .\packer.exe build -force $PSScriptRoot\packer-json-template.json
     }
     if ($LASTEXITCODE -ne 0) {
       exit 99
     }

  }
  end {
    write-host Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}

Build-PackerImage -location $location -yaml_file $yaml_file
