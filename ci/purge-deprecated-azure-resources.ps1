
if (@(Get-PSRepository -Name 'PSGallery')[0].InstallationPolicy -ne 'Trusted') {
  Set-PSRepository -Name 'PSGallery' -InstallationPolicy 'Trusted';
}
foreach ($rm in @(
  @{ 'module' = 'posh-minions-managed'; 'version' = '0.0.72' },
  @{ 'module' = 'powershell-yaml'; 'version' = '0.4.1' }
)) {
  $module = (Get-Module -Name $rm.module -ErrorAction SilentlyContinue);
  if ($module) {
    if ($module.Version -lt $rm.version) {
      Update-Module -Name $rm.module -RequiredVersion $rm.version;
    }
  } else {
    Install-Module -Name $rm.module -RequiredVersion $rm.version -AllowClobber;
  }
  Import-Module -Name $rm.module -RequiredVersion $rm.version -ErrorAction SilentlyContinue;
}

$secret = (Invoke-WebRequest -Uri 'http://taskcluster/secrets/v1/secret/project/relops/image-builder/dev' -UseBasicParsing | ConvertFrom-Json).secret;
Connect-AzAccount `
  -ServicePrincipal `
  -Credential (New-Object System.Management.Automation.PSCredential($secret.azure.id, (ConvertTo-SecureString `
    -String $secret.azure.key `
    -AsPlainText `
    -Force))) `
  -Tenant $secret.azure.account | Out-Null;


$deallocatedAzVms = @(Get-AzVm -Status | ? { $_.PowerState -eq 'Provisioning succeeded' } | % { (Get-AzVm -Name $_.Name -ResourceGroupName $_.ResourceGroupName -Status) | ? { $_.Statuses -and $_.Statuses[2].Code -match 'deallocated' } });
Write-Output -InputObject ('removing {0} deallocated AzVm objects' -f $deallocatedAzVms.Length);
foreach ($deallocatedAzVm in $deallocatedAzVms) {
  Write-Output -InputObject ('removing deallocated AzVm {0} / {1}' -f $deallocatedAzVm.ResourceGroupName, $deallocatedAzVm.Name);
  $deallocatedAzVm | Remove-AzVm -Force;
}

$orphanedAzNetworkInterfaces = @(Get-AzNetworkInterface | ? { $_.VirtualMachine -eq $null });
Write-Output -InputObject ('removing {0} orphaned AzNetworkInterface objects' -f $orphanedAzNetworkInterfaces.Length);
foreach ($orphanedAzNetworkInterface in $orphanedAzNetworkInterfaces) {
  Write-Output -InputObject ('removing orphaned AzNetworkInterface {0} / {1} / {2}' -f $orphanedAzNetworkInterface.Location, $orphanedAzNetworkInterface.ResourceGroupName, $orphanedAzNetworkInterface.Name);
  $orphanedAzNetworkInterface | Remove-AzNetworkInterface -Force;
}

$orphanedAzPublicIpAddresses = @(Get-AzPublicIpAddress | ? { $_.IpAddress -eq 'Not Assigned' });
Write-Output -InputObject ('removing {0} orphaned AzPublicIpAddress objects' -f $orphanedAzPublicIpAddresses.Length);
foreach ($orphanedAzPublicIpAddress in $orphanedAzPublicIpAddresses) {
  Write-Output -InputObject ('removing orphaned AzPublicIpAddress {0} / {1} / {2}' -f $orphanedAzPublicIpAddress.Location, $orphanedAzPublicIpAddress.ResourceGroupName, $orphanedAzPublicIpAddress.Name);
  $orphanedAzPublicIpAddress | Remove-AzPublicIpAddress -Force;
}

$orphanedAzNetworkSecurityGroups = @(Get-AzNetworkSecurityGroup | ? { -not $_.NetworkInterFaces });
Write-Output -InputObject ('removing {0} orphaned AzNetworkSecurityGroup objects' -f $orphanedAzNetworkSecurityGroups.Length);
foreach ($orphanedAzNetworkSecurityGroup in $orphanedAzNetworkSecurityGroups) {
  Write-Output -InputObject ('removing orphaned AzNetworkSecurityGroup {0} / {1} / {2}' -f $orphanedAzNetworkSecurityGroup.Location, $orphanedAzNetworkSecurityGroup.ResourceGroupName, $orphanedAzNetworkSecurityGroup.Name);
  $orphanedAzNetworkSecurityGroup | Remove-AzNetworkSecurityGroup -Force;
}

$orphanedAzVirtualNetworks = @(Get-AzVirtualNetwork | ? { (-not $_.Subnets) -or (-not $_.Subnets[0].IpConfigurations) });
Write-Output -InputObject ('removing {0} orphaned AzVirtualNetwork objects' -f $orphanedAzVirtualNetworks.Length);
foreach ($orphanedAzVirtualNetwork in $orphanedAzVirtualNetworks) {
  Write-Output -InputObject ('removing orphaned AzVirtualNetwork {0} / {1} / {2}' -f $orphanedAzVirtualNetwork.Location, $orphanedAzVirtualNetwork.ResourceGroupName, $orphanedAzVirtualNetwork.Name);
  foreach ($orphanedAzVirtualNetworkSubnetConfig in $orphanedAzVirtualNetwork.Subnets) {
    Write-Output -InputObject ('skipped removing orphaned AzVirtualNetworkSubnetConfig {0}' -f $orphanedAzVirtualNetworkSubnetConfig.Name);
    #Remove-AzVirtualNetworkSubnetConfig -Name $orphanedAzVirtualNetworkSubnetConfig.Name -VirtualNetwork $orphanedAzVirtualNetwork;
  }
  $orphanedAzVirtualNetwork | Remove-AzVirtualNetwork -Force;
}

$orphanedAzDisks = @(Get-AzDisk | ? { $_.DiskState -eq 'Unattached' });
Write-Output -InputObject ('removing {0} orphaned AzDisk objects' -f $orphanedAzDisks.Length);
foreach ($orphanedAzDisk in $orphanedAzDisks) {
  Write-Output -InputObject ('removing orphaned AzDisk {0} / {1} / {2}' -f $orphanedAzDisk.Location, $orphanedAzDisk.ResourceGroupName, $orphanedAzDisk.Name);
  $orphanedAzDisk | Remove-AzDisk -Force;
}