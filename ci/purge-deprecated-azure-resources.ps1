param (
  [string[]] $resources = @(
    'disk',
    'ni',
    'pia',
    'vm'
  )
)

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


$jobs = [hashtable[]] @();

if ((-not $resources) -or ($resources -contains 'all') -or ($resources -contains 'vm')) {
  $deallocatedAzVms = @(Get-AzVm -Status | ? { $_.PowerState -eq 'Provisioning succeeded' } | % { (Get-AzVm -Name $_.Name -ResourceGroupName $_.ResourceGroupName -Status) | ? { $_.Statuses -and $_.Statuses[2].Code -match 'deallocated' } });
  Write-Output -InputObject ('removing {0} deallocated AzVm objects' -f $deallocatedAzVms.Length);
  foreach ($deallocatedAzVm in $deallocatedAzVms) {
    try {
      Write-Output -InputObject ('removing deallocated AzVm {0} / {1}' -f $deallocatedAzVm.ResourceGroupName, $deallocatedAzVm.Name);
      $job = (Remove-AzVm `
        -ResourceGroupName $deallocatedAzVm.ResourceGroupName `
        -Name $deallocatedAzVm.Name `
        -AsJob `
        -Force);
      $jobs += @{
        'group' = $deallocatedAzVm.ResourceGroupName;
        'name' = $deallocatedAzVm.Name;
        'job' = $job
      };
    } catch {
      Write-Output -InputObject ('exception removing deallocated AzVm {0} / {1}. {2}' -f $deallocatedAzVm.ResourceGroupName, $deallocatedAzVm.Name, $_.Exception.Message);
    }
  }
}

if ((-not $resources) -or ($resources -contains 'all') -or ($resources -contains 'ni')) {
  $orphanedAzNetworkInterfaces = @(Get-AzNetworkInterface | ? { $_.VirtualMachine -eq $null });
  Write-Output -InputObject ('removing {0} orphaned AzNetworkInterface objects' -f $orphanedAzNetworkInterfaces.Length);
  foreach ($orphanedAzNetworkInterface in $orphanedAzNetworkInterfaces) {
    try {
      Write-Output -InputObject ('removing orphaned AzNetworkInterface {0} / {1} / {2}' -f $orphanedAzNetworkInterface.Location, $orphanedAzNetworkInterface.ResourceGroupName, $orphanedAzNetworkInterface.Name);
      if (Remove-AzNetworkInterface `
        -ResourceGroupName $orphanedAzNetworkInterface.ResourceGroupName `
        -Name $orphanedAzNetworkInterface.Name `
        -AsJob `
        -Force) {
        Write-Output -InputObject ('removed orphaned AzNetworkInterface {0} / {1} / {2}' -f $orphanedAzNetworkInterface.Location, $orphanedAzNetworkInterface.ResourceGroupName, $orphanedAzNetworkInterface.Name);
      } else {
        Write-Output -InputObject ('failed to remove orphaned AzNetworkInterface {0} / {1} / {2}' -f $orphanedAzNetworkInterface.Location, $orphanedAzNetworkInterface.ResourceGroupName, $orphanedAzNetworkInterface.Name);
      }
    } catch {
      Write-Output -InputObject ('exception removing orphaned AzNetworkInterface {0} / {1} / {2}. {3}' -f $orphanedAzNetworkInterface.Location, $orphanedAzNetworkInterface.ResourceGroupName, $orphanedAzNetworkInterface.Name, $_.Exception.Message);
    }
  }
}

if ((-not $resources) -or ($resources -contains 'all') -or ($resources -contains 'pia')) {
  $orphanedAzPublicIpAddresses = @(Get-AzPublicIpAddress | ? { $_.IpAddress -eq 'Not Assigned' });
  Write-Output -InputObject ('removing {0} orphaned AzPublicIpAddress objects' -f $orphanedAzPublicIpAddresses.Length);
  foreach ($orphanedAzPublicIpAddress in $orphanedAzPublicIpAddresses) {
    try {
      Write-Output -InputObject ('removing orphaned AzPublicIpAddress {0} / {1} / {2}' -f $orphanedAzPublicIpAddress.Location, $orphanedAzPublicIpAddress.ResourceGroupName, $orphanedAzPublicIpAddress.Name);
      if (Remove-AzPublicIpAddress `
        -ResourceGroupName $orphanedAzPublicIpAddress.ResourceGroupName `
        -Name $orphanedAzPublicIpAddress.Name `
        -AsJob `
        -Force) {
        Write-Output -InputObject ('removed orphaned AzPublicIpAddress {0} / {1} / {2}' -f $orphanedAzPublicIpAddress.Location, $orphanedAzPublicIpAddress.ResourceGroupName, $orphanedAzPublicIpAddress.Name);
      } else {
        Write-Output -InputObject ('failed to remove orphaned AzPublicIpAddress {0} / {1} / {2}' -f $orphanedAzPublicIpAddress.Location, $orphanedAzPublicIpAddress.ResourceGroupName, $orphanedAzPublicIpAddress.Name);
      }
    } catch {
      Write-Output -InputObject ('exception removing orphaned AzPublicIpAddress {0} / {1} / {2}. {3}' -f $orphanedAzPublicIpAddress.Location, $orphanedAzPublicIpAddress.ResourceGroupName, $orphanedAzPublicIpAddress.Name, $_.Exception.Message);
    }
  }
}

if ((-not $resources) -or ($resources -contains 'all') -or ($resources -contains 'nsg')) {
  $orphanedAzNetworkSecurityGroups = @(Get-AzNetworkSecurityGroup | ? { -not $_.NetworkInterFaces });
  Write-Output -InputObject ('removing {0} orphaned AzNetworkSecurityGroup objects' -f $orphanedAzNetworkSecurityGroups.Length);
  foreach ($orphanedAzNetworkSecurityGroup in $orphanedAzNetworkSecurityGroups) {
    try {
      Write-Output -InputObject ('removing orphaned AzNetworkSecurityGroup {0} / {1} / {2}' -f $orphanedAzNetworkSecurityGroup.Location, $orphanedAzNetworkSecurityGroup.ResourceGroupName, $orphanedAzNetworkSecurityGroup.Name);
      if (Remove-AzNetworkSecurityGroup `
        -ResourceGroupName $orphanedAzNetworkSecurityGroup.ResourceGroupName `
        -Name $orphanedAzNetworkSecurityGroup.Name `
        -AsJob `
        -Force) {
        Write-Output -InputObject ('removed orphaned AzNetworkSecurityGroup {0} / {1} / {2}' -f $orphanedAzNetworkSecurityGroup.Location, $orphanedAzNetworkSecurityGroup.ResourceGroupName, $orphanedAzNetworkSecurityGroup.Name);
      } else {
        Write-Output -InputObject ('failed to remove orphaned AzNetworkSecurityGroup {0} / {1} / {2}' -f $orphanedAzNetworkSecurityGroup.Location, $orphanedAzNetworkSecurityGroup.ResourceGroupName, $orphanedAzNetworkSecurityGroup.Name);
      }
    } catch {
      Write-Output -InputObject ('exception removing orphaned AzNetworkSecurityGroup {0} / {1} / {2}. {3}' -f $orphanedAzNetworkSecurityGroup.Location, $orphanedAzNetworkSecurityGroup.ResourceGroupName, $orphanedAzNetworkSecurityGroup.Name, $_.Exception.Message);
    }
  }
}

if ((-not $resources) -or ($resources -contains 'all') -or ($resources -contains 'vn')) {
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
}

if ((-not $resources) -or ($resources -contains 'all') -or ($resources -contains 'disk')) {
  $orphanedAzDisks = @(Get-AzDisk | ? { $_.DiskState -eq 'Unattached' });
  Write-Output -InputObject ('removing {0} orphaned AzDisk objects' -f $orphanedAzDisks.Length);
  foreach ($orphanedAzDisk in $orphanedAzDisks) {
    try {
      Write-Output -InputObject ('removing orphaned AzDisk {0} / {1} / {2}' -f $orphanedAzDisk.Location, $orphanedAzDisk.ResourceGroupName, $orphanedAzDisk.Name);
      if (Remove-AzDisk `
        -ResourceGroupName $orphanedAzDisk.ResourceGroupName `
        -DiskName $orphanedAzDisk.Name `
        -AsJob `
        -Force) {
        Write-Output -InputObject ('removed orphaned AzDisk {0} / {1} / {2}' -f $orphanedAzDisk.Location, $orphanedAzDisk.ResourceGroupName, $orphanedAzDisk.Name);
      } else {
        Write-Output -InputObject ('failed to remove orphaned AzDisk {0} / {1} / {2}' -f $orphanedAzDisk.Location, $orphanedAzDisk.ResourceGroupName, $orphanedAzDisk.Name);
      }
    } catch {
      Write-Output -InputObject ('exception removing orphaned AzDisk {0} / {1} / {2}. {3}' -f $orphanedAzDisk.Location, $orphanedAzDisk.ResourceGroupName, $orphanedAzDisk.Name, $_.Exception.Message);
    }
  }
}

#foreach ($vmDeleteOperation in $jobs) {
  # todo: log job status
#}