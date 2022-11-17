param (
  [Parameter(Mandatory = $true)]
  [string] 
  $Location,
  
  [string] 
  $yaml_file
)

Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  
## Check for packer
if ($Null -eq (Get-Command Packer)) {
  throw "Packer not found!"
}
    
Install-Module powershell-yaml -force

$yaml_data = (Get-Content -Path (Join-Path -Path $PSScriptRoot\config -ChildPath $yaml_file) -Raw | ConvertFrom-Yaml)

# Random string for temp resource group. Prevent duplicate names in an event of a bad build
$random = (get-random -Maximum 999)

$Env:client_id = $env:AZURE_CLIENT_ID
$Env:client_secret = $env:AZURE_CLIENT_SECRET
$Env:tenant_id = $env:AZURE_TENANT_ID
$Env:image_publisher = $yaml_data.image.publisher
$Env:image_offer = $yaml_data.image.offer
$Env:image_sku = $yaml_data.image.sku
$Env:managed_image_resource_group_name = $yaml_data.azure.managed_image_resource_group_name
$Env:managed_image_storage_account_type = $yaml_data.azure.managed_image_storage_account_type
$Env:Project = $yaml_data.vm.tags.Project
$Env:base_image = $yaml_data.vm.tags.base_image
$Env:worker_pool_id = $yaml_data.vm.tags.worker_pool_id
$worker_pool = $yaml_data.vm.tags.worker_pool_id
$Env:sourceOrganisation = $yaml_data.vm.tags.sourceOrganisation
$Env:sourceRepository = $yaml_data.vm.tags.sourceRepository
$Env:sourceBranch = $yaml_data.vm.tags.sourceBranch
$Env:bootstrapscript = ('https://raw.githubusercontent.com/{0}/{1}/{2}/provisioners/windows/azure/azure-bootstrap.ps1' -f $Env:sourceOrganisation, $Env:sourceRepository, $Env:sourceBranch)
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
}
elseif (($yaml_file -like "*alpha*" )) {
  $Env:managed_image_name = ('{0}-{1}-{2}-alpha' -f $worker_pool, $location, $yaml_data.image.sku)
}
elseif (($yaml_file -like "*next*" )) {
  $Env:managed_image_name = ('{0}-{1}-{2}-next' -f $worker_pool, $location, $yaml_data.image.sku)
}
else {
  $Env:managed_image_name = ('{0}-{1}-{2}-{3}' -f $worker_pool, $location, $yaml_data.image.sku, $yaml_data.vm.tags.deploymentId)
}
if (($yaml_file -like "trusted*" )) {
  $Env:subscription_id = $env:AZURE_SUBSCRIPTION_ID_TRUSTED
}
else {
  $Env:subscription_id = $env:AZURE_SUBSCRIPTION_ID
}

if (($yaml_file -like "*2012*" )) {
  packer build -force $PSScriptRoot\2012-packer-json-template.json
}
else {
  packer build -force $PSScriptRoot\packer-json-template.pkr.hcl
}
if ($LASTEXITCODE -ne 0) {
  exit 99
}

Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
