# usage:
# Invoke-Expression (New-Object Net.WebClient).DownloadString(('https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/purge-orphaned-resources.ps1?{0}' -f [Guid]::NewGuid()))

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
    Write-Output -InputObject ('removing orphaned AzVirtualNetworkSubnetConfig {0}' -f $orphanedAzVirtualNetworkSubnetConfig.Name);
    Remove-AzVirtualNetworkSubnetConfig -Name $orphanedAzVirtualNetworkSubnetConfig.Name -VirtualNetwork $orphanedAzVirtualNetwork;
  }
  $orphanedAzVirtualNetwork | Remove-AzVirtualNetwork -Force;
}

$orphanedAzDisks = @(Get-AzDisk | ? { $_.DiskState -eq 'Unattached' });
Write-Output -InputObject ('removing {0} orphaned AzDisk objects' -f $orphanedAzDisks.Length);
foreach ($orphanedAzDisk in $orphanedAzDisks) {
  Write-Output -InputObject ('removing orphaned AzDisk {0} / {1} / {2}' -f $orphanedAzDisk.Location, $orphanedAzDisk.ResourceGroupName, $orphanedAzDisk.Name);
  $orphanedAzDisk | Remove-AzDisk -Force;
}
