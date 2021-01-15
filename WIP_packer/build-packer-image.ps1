<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

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
function Build-Packer-Image {
  param (
  )
  begin {
    Write-host Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }

  process {
     
     Install-Module powershell-yaml -force
     
     # This ymal file is stripped down to what Packer needs for dev and testing
     # Though hard coded now it should proablaly be a variable that is passed a parameter to the function. 
     # I am trying to have the script and json template agnostic and all unique values will come from the yaml file
     # The values that are label with markco in the yaml file will be replaced next week
    
     $yaml_data = @((Get-Content -Path .\win10-64_packer.yaml -Raw | ConvertFrom-Yaml))
     $build_location = $yaml_data.azure.build_location
     
     # Get taskcluster secrets
     # $secret = (Invoke-WebRequest -Uri 'http://taskcluster/secrets/v1/secret/project/relops/image-builder/dev' -UseBasicParsing | ConvertFrom-Json).secret;
     # With the secrets in place the packer build completes successfully
     # The image copy fails on authentication
     
     write-host location is $location
     $Env:client_id = # TC secrets azure.packer.client_id
     $Env:client_secret = # TC secrets azure.packer.client_secret
     $Env:tenant_id = # TC secrets azure.account
     $Env:subscription_id # TC secrets azure.subscription 
     $Env:image_publisher = $yaml_data.image.publisher
     $Env:image_offer = $yaml_data.image.offer
     $Env:image_sku = $yaml_data.image.sku
     $Env:managed_image_resource_group_name = $yaml_data.azure.managed_image_resource_group_name
     $Env:managed_image_storage_account_type = $yaml_data.azure.managed_image_storage_account_type
     $Env:Project = $yaml_data.vm.tags.Project
     $Env:workerType = $yaml_data.vm.tags.workerType
     $Env:sourceOrganisation = $yaml_data.vm.tags.sourceOrganisation
     $Env:sourceRepository = $yaml_data.vm.tags.sourceRepository
     $Env:sourceRevision = $yaml_data.vm.tags.sourceRevision
     $Env:deploymentId = $yaml_data.vm.tags.deploymentId
     $Env:managed_by = $yaml_data.vm.tags.managed_by
     $Env:location = $build_location
     $Env:vm_size = $yaml_data.vm.size
     $Env:disk_additional_size = $yaml_data.vm.disk_additional_size
     $Env:managed_image_name = ('{0}-{1}-{2}' -f $yaml_data.vm.tags.workerType, $build_location, $yaml_data.vm.tags.deploymentId)
     $Env:temp_resource_group_name = ('{0}-{1}-{2}-tmp3' -f $yaml_data.vm.tags.workerType, $build_location, $yaml_data.vm.tags.deploymentId)
         
     # packer.exe stored at https://cloud-image-builder.s3-us-west-2.amazonaws.com/packer.exe
     # No installation/ down load binary and run
     powershell .\packer.exe build  -force .\packer-json-template.json
     
     # With the foreach Powershell waits for one build to finish before startting the next one
     # Was trying to copy the image between regions
     # Alternatively we could have a seperate task per region. 
         
     $locations = $yaml_data.azure.locations
     foreach ($location in $locations) {
        if ($location -ne $build_location ) {
            write-host ('{0}-{1}-{2}' -f $yaml_data.vm.tags.workerType, $location, $yaml_data.vm.tags.deploymentId)
            az extension add --name image-copy-extension
            az image copy --source-resource-group $yaml_data.azure.managed_image_resource_group_name --source-object-name  $Env:managed_image_name --target-location $location --target-resource-group $yaml_data.azure.managed_image_resource_group_name --cleanup
            
        }
     }
  }
  end {
    write-host Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}

Build-Packer-Image 
