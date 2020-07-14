param (
  [string[]] $groups = @(),
  [string[]] $resources = @(
    'disk',
    'image',
    'ni',
    'nsg',
    'pia',
    'snap'#,
    #'vm'
  )
)

if (@(Get-PSRepository -Name 'PSGallery')[0].InstallationPolicy -ne 'Trusted') {
  Set-PSRepository -Name 'PSGallery' -InstallationPolicy 'Trusted';
}
foreach ($rm in @(
  @{
    'module' = 'Az.Compute';
    'version' = '3.1.0'
  },
  @{
    'module' = 'Az.Network';
    'version' = '2.1.0'
  },
  @{
    'module' = 'Az.Resources';
    'version' = '1.8.0'
  },
  @{
    'module' = 'Az.Storage';
    'version' = '1.9.0'
  },
  @{
    'module' = 'posh-minions-managed';
    'version' = '0.0.93'
  },
  @{
    'module' = 'powershell-yaml';
    'version' = '0.4.1'
  }
)) {
  $module = (Get-Module -Name $rm.module -ErrorAction SilentlyContinue);
  if ($module) {
    if ($module.Version -lt $rm.version) {
      Update-Module -Name $rm.module -RequiredVersion $rm.version;
    }
  } else {
    Install-Module -Name $rm.module -RequiredVersion $rm.version -AllowClobber;
  }
  try {
    Import-Module -Name $rm.module -RequiredVersion $rm.version -ErrorAction SilentlyContinue;
  } catch {
    Write-Output -InputObject ('import of required module: {0}, version: {1}, failed. {2}' -f $rm.module, $rm.version, $_.Exception.Message);
    # if we get here, the instance is borked and will throw exceptions on all subsequent tasks.
    & shutdown @('/s', '/t', '3', '/c', 'borked powershell module library detected', '/f', '/d', '1:1');
    exit 123;
  }
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

if ($groups.Length -eq 0) {
  $groups = @(Get-AzResourceGroup | ? {
    $_.ResourceGroupName.StartsWith('rg-') `
    -and $_.ResourceGroupName.Contains('-us-') `
    -and (
      $_.ResourceGroupName.EndsWith('-gecko-1') `
      -or $_.ResourceGroupName.EndsWith('-gecko-3') `
      -or $_.ResourceGroupName.EndsWith('-gecko-t') `
      -or $_.ResourceGroupName.EndsWith('-relops') `
      -or $_.ResourceGroupName.EndsWith('-mpd001-1') `
      -or $_.ResourceGroupName.EndsWith('-mpd001-3')
    )
  } | % { $_.ResourceGroupName });
}

if ((-not $resources) -or ($resources -contains 'all') -or ($resources -contains 'vm')) {
  foreach ($group in $groups) {
    $deallocatedAzVms = @(Get-AzVm -ResourceGroupName $group -Status | ? { $_.PowerState -eq 'Provisioning succeeded' } | % { (Get-AzVm -Name $_.Name -ResourceGroupName $_.ResourceGroupName -Status) | ? { $_.Statuses -and $_.Statuses[2].Code -match 'deallocated' } });
    if ($deallocatedAzVms.Length -gt 0) {
      Write-Output -InputObject ('removing {0} deallocated AzVm objects in {1}' -f $deallocatedAzVms.Length, $group);
    }
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
}

if ((-not $resources) -or ($resources -contains 'all') -or ($resources -contains 'ni')) {
  foreach ($group in $groups) {
    $orphanedAzNetworkInterfaces = @(Get-AzNetworkInterface -ResourceGroupName $group | ? { $_.VirtualMachine -eq $null });
    if ($orphanedAzNetworkInterfaces.Length -gt 0) {
      Write-Output -InputObject ('removing {0} orphaned AzNetworkInterface objects in {1}' -f $orphanedAzNetworkInterfaces.Length, $group);
    }
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
}

if ((-not $resources) -or ($resources -contains 'all') -or ($resources -contains 'pia')) {
  foreach ($group in $groups) {
    $orphanedAzPublicIpAddresses = @(Get-AzPublicIpAddress -ResourceGroupName $group | ? { $_.IpAddress -eq 'Not Assigned' });
    if ($orphanedAzPublicIpAddresses.Length -gt 0) {
      Write-Output -InputObject ('removing {0} orphaned AzPublicIpAddress objects in {1}' -f $orphanedAzPublicIpAddresses.Length, $group);
    }
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
}

if ((-not $resources) -or ($resources -contains 'all') -or ($resources -contains 'nsg')) {
  foreach ($group in $groups) {
    $orphanedAzNetworkSecurityGroups = @(Get-AzNetworkSecurityGroup -ResourceGroupName $group | ? { ((-not $_.NetworkInterFaces) -and ($_.Name.StartsWith('nsg-')) -and (($_.Name.EndsWith('-relops')) -or ($_.Name.EndsWith('-gecko-1')) -or ($_.Name.EndsWith('-gecko-3')) -or ($_.Name.EndsWith('-gecko-t')) -or ($_.Name.EndsWith('-mpd001-1')) -or ($_.Name.EndsWith('-mpd001-3')))) });
    if ($orphanedAzNetworkSecurityGroups.Length -gt 0) {
      Write-Output -InputObject ('removing {0} stale AzNetworkSecurityGroup objects in {1}' -f $orphanedAzNetworkSecurityGroups.Length, $group);
    }
    foreach ($orphanedAzNetworkSecurityGroup in $orphanedAzNetworkSecurityGroups) {
      try {
        Write-Output -InputObject ('removing stale AzNetworkSecurityGroup {0} / {1} / {2}' -f $orphanedAzNetworkSecurityGroup.Location, $orphanedAzNetworkSecurityGroup.ResourceGroupName, $orphanedAzNetworkSecurityGroup.Name);
        if (Remove-AzNetworkSecurityGroup `
          -ResourceGroupName $orphanedAzNetworkSecurityGroup.ResourceGroupName `
          -Name $orphanedAzNetworkSecurityGroup.Name `
          -AsJob `
          -Force) {
          Write-Output -InputObject ('removed stale AzNetworkSecurityGroup {0} / {1} / {2}' -f $orphanedAzNetworkSecurityGroup.Location, $orphanedAzNetworkSecurityGroup.ResourceGroupName, $orphanedAzNetworkSecurityGroup.Name);
        } else {
          Write-Output -InputObject ('failed to remove stale AzNetworkSecurityGroup {0} / {1} / {2}' -f $orphanedAzNetworkSecurityGroup.Location, $orphanedAzNetworkSecurityGroup.ResourceGroupName, $orphanedAzNetworkSecurityGroup.Name);
        }
      } catch {
        Write-Output -InputObject ('exception removing stale AzNetworkSecurityGroup {0} / {1} / {2}. {3}' -f $orphanedAzNetworkSecurityGroup.Location, $orphanedAzNetworkSecurityGroup.ResourceGroupName, $orphanedAzNetworkSecurityGroup.Name, $_.Exception.Message);
      }
    }
  }
}

if ((-not $resources) -or ($resources -contains 'all') -or ($resources -contains 'vn')) {
  foreach ($group in $groups) {
    $orphanedAzVirtualNetworks = @(Get-AzVirtualNetwork -ResourceGroupName $group | ? { (-not $_.Subnets) -or (-not $_.Subnets[0].IpConfigurations) });
    if ($orphanedAzVirtualNetworks.Length -gt 0) {
      Write-Output -InputObject ('removing {0} orphaned AzVirtualNetwork objects in {1}' -f $orphanedAzVirtualNetworks.Length, $group);
    }
    foreach ($orphanedAzVirtualNetwork in $orphanedAzVirtualNetworks) {
      Write-Output -InputObject ('removing orphaned AzVirtualNetwork {0} / {1} / {2}' -f $orphanedAzVirtualNetwork.Location, $orphanedAzVirtualNetwork.ResourceGroupName, $orphanedAzVirtualNetwork.Name);
      foreach ($orphanedAzVirtualNetworkSubnetConfig in $orphanedAzVirtualNetwork.Subnets) {
        Write-Output -InputObject ('skipped removing orphaned AzVirtualNetworkSubnetConfig {0}' -f $orphanedAzVirtualNetworkSubnetConfig.Name);
        #Remove-AzVirtualNetworkSubnetConfig -Name $orphanedAzVirtualNetworkSubnetConfig.Name -VirtualNetwork $orphanedAzVirtualNetwork;
      }
      $orphanedAzVirtualNetwork | Remove-AzVirtualNetwork -Force;
    }
  }
}

if ((-not $resources) -or ($resources -contains 'all') -or ($resources -contains 'disk')) {
  foreach ($group in $groups) {
    $orphanedAzDisks = @(Get-AzDisk -ResourceGroupName $group | ? { $_.DiskState -eq 'Unattached' });
    if ($orphanedAzDisks.Length -gt 0) {
      Write-Output -InputObject ('removing {0} orphaned AzDisk objects in {1}' -f $orphanedAzDisks.Length, $group);
    }
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
}

if ((-not $resources) -or ($resources -contains 'all') -or ($resources -contains 'snap')) {
  $allAzSnapshots = @(Get-AzSnapshot);
  foreach ($group in $groups) {
    $prefix = $group.Replace('rg-', '');
    $rgSnapshots = @($allAzSnapshots | ? { $_.Name.StartsWith(('{0}-' -f $prefix)) });
    $keys = @($rgSnapshots | % { $_.Name.SubString(0, ($_.Name.Length - 8)).Replace(('{0}-' -f $prefix), '').Trim() } | Select-Object -Unique);
    foreach ($key in $keys) {
      $workerSnapshots = @($rgSnapshots | ? { $_.Name.StartsWith(('{0}-{1}' -f $prefix, $key)) } | Sort-Object -Property 'TimeCreated' -Descending);
      if ($workerSnapshots.Length -gt 1) {
        # delete all but newest snapshot
        for ($i = ($workerSnapshots.Length -1); $i -gt 0; $i --) {
          try {
            Write-Output -InputObject ('removing deprecated AzSnapshot {0} / {1} / {2}, created {3}' -f $workerSnapshots[$i].Location, $workerSnapshots[$i].ResourceGroupName, $workerSnapshots[$i].Name, $workerSnapshots[$i].TimeCreated);
            if (Remove-AzSnapshot `
              -ResourceGroupName $workerSnapshots[$i].ResourceGroupName `
              -Name $workerSnapshots[$i].Name `
              -AsJob `
              -Force) {
              Write-Output -InputObject ('removed deprecated AzSnapshot {0} / {1} / {2}, created {3}' -f $workerSnapshots[$i].Location, $workerSnapshots[$i].ResourceGroupName, $workerSnapshots[$i].Name, $workerSnapshots[$i].TimeCreated);
            } else {
              Write-Output -InputObject ('failed to remove deprecated AzSnapshot {0} / {1} / {2}, created {3}' -f $workerSnapshots[$i].Location, $workerSnapshots[$i].ResourceGroupName, $workerSnapshots[$i].Name, $workerSnapshots[$i].TimeCreated);
            }
          } catch {
            Write-Output -InputObject ('exception removing deprecated AzSnapshot {0} / {1} / {2}, created {3}. {4}' -f $workerSnapshots[$i].Location, $workerSnapshots[$i].ResourceGroupName, $workerSnapshots[$i].Name, $workerSnapshots[$i].TimeCreated, $_.Exception.Message);
          }
        }
      }
      Write-Output -InputObject ('skipping latest AzSnapshot {0} / {1} / {2}, created {3}' -f $workerSnapshots[0].Location, $workerSnapshots[0].ResourceGroupName, $workerSnapshots[0].Name, $workerSnapshots[0].TimeCreated);
    }
  }
}

if ((-not $resources) -or ($resources -contains 'all') -or ($resources -contains 'image')) {
  $allAzImages = @(Get-AzImage);
  foreach ($group in $groups) {
    $prefix = $group.Replace('rg-', '');
    $rgImages = @($allAzImages | ? { $_.Name.StartsWith(('{0}-' -f $prefix)) });
    $keys = @($rgImages | % { $_.Name.SubString(0, ($_.Name.Length - 8)).Replace(('{0}-' -f $prefix), '').Trim() } | Select-Object -Unique);
    foreach ($key in $keys) {
      $workerImages = @($rgImages | ? { $_.Name.StartsWith(('{0}-{1}' -f $prefix, $key)) -and $_.Tags.ContainsKey('machineImageCommitTime') } | % { Add-Member -InputObject $_ -MemberType 'NoteProperty' -Name 'TimeCreated' -Value ([DateTime]$_.Tags['machineImageCommitTime']) -PassThru -Force } | Sort-Object -Property 'TimeCreated' -Descending);
      if ($workerImages.Length -gt 2) {
        # delete all but newest and penultimate image
        for ($i = ($workerImages.Length -1); $i -gt 1; $i --) {
          try {
            Write-Output -InputObject ('removing deprecated AzImage {0} / {1} / {2}, created {3:s}' -f $workerImages[$i].Location, $workerImages[$i].ResourceGroupName, $workerImages[$i].Name, $workerImages[$i].TimeCreated);
            if (Remove-AzImage `
              -ResourceGroupName $workerImages[$i].ResourceGroupName `
              -Name $workerImages[$i].Name `
              -AsJob `
              -Force) {
              Write-Output -InputObject ('removed deprecated AzImage {0} / {1} / {2}, created {3:s}' -f $workerImages[$i].Location, $workerImages[$i].ResourceGroupName, $workerImages[$i].Name, $workerImages[$i].TimeCreated);
            } else {
              Write-Output -InputObject ('failed to remove deprecated AzImage {0} / {1} / {2}, created {3:s}' -f $workerImages[$i].Location, $workerImages[$i].ResourceGroupName, $workerImages[$i].Name, $workerImages[$i].TimeCreated);
            }
          } catch {
            Write-Output -InputObject ('exception removing deprecated AzImage {0} / {1} / {2}, created {3:s}. {4}' -f $workerImages[$i].Location, $workerImages[$i].ResourceGroupName, $workerImages[$i].Name, $workerImages[$i].TimeCreated, $_.Exception.Message);
          }
        }
      }
      if ($workerImages.Length -gt 0) {
        Write-Output -InputObject ('skipping latest AzImage {0} / {1} / {2}, created {3:s}' -f $workerImages[0].Location, $workerImages[0].ResourceGroupName, $workerImages[0].Name, $workerImages[0].TimeCreated);
        if ($workerImages.Length -gt 1) {
          Write-Output -InputObject ('skipping penultimate AzImage {0} / {1} / {2}, created {3:s}' -f $workerImages[1].Location, $workerImages[1].ResourceGroupName, $workerImages[1].Name, $workerImages[1].TimeCreated);
        }
      }
    }
  }
}

#foreach ($vmDeleteOperation in $jobs) {
  # todo: log job status
#}