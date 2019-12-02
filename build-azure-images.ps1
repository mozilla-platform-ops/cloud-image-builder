# usage:
# Invoke-Expression (New-Object Net.WebClient).DownloadString(('https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/build-azure-images.ps1?{0}' -f [Guid]::NewGuid()))

# job settings. change these for the tasks at hand.
$targetCloudPlatform = 'azure';
$workFolder = ('{0}{1}{2}-ci' -f 'D:', ([IO.Path]::DirectorySeparatorChar), $targetCloudPlatform);
$imagesToBuild = @(
  ('win10-64-{0}' -f $targetCloudPlatform),
  ('win10-64-gpu-{0}' -f $targetCloudPlatform),
  ('win2012-{0}' -f $targetCloudPlatform),
  ('win2019-{0}' -f $targetCloudPlatform)
 );

# constants and script config. these are probably ok as they are.
$revision = (Invoke-WebRequest -Uri 'https://api.github.com/gists/3f2fbc64e7210de136e7eb69aae63f81' -UseBasicParsing | ConvertFrom-Json).history[0].version;
foreach ($rm in @(
  @{ 'module' = 'posh-minions-managed'; 'version' = '0.0.21' },
  @{ 'module' = 'powershell-yaml'; 'version' = '0.4.1' }
)) {
  $module = (Get-Module -Name $rm.module -ErrorAction SilentlyContinue);
  if ($module) {
    if ($module.Version -lt $rm.version) {
      Update-Module $rm.module -RequiredVersion $rm.version
    }
  } else {
    Install-Module $rm.module -RequiredVersion $rm.version
  }
  Import-Module $rm.module -RequiredVersion $rm.version -ErrorAction SilentlyContinue
}

foreach ($imageKey in $imagesToBuild) {
  # computed target specific settings. these are probably ok as they are.
  $config = (Invoke-WebRequest -Uri ('https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/{0}/config.yaml' -f $revision) -UseBasicParsing | ConvertFrom-Yaml)."$imageKey";
  $imageName = ('{0}-{1}-{2}-{3}-{4}{5}-{6}.{7}' -f $revision.Substring(0, 7)
    $config.image.os.ToLower().Replace(' ', ''),
    $config.image.edition.ToLower(),
    $config.image.language.ToLower(),
    $config.image.architecture,
    $(if ($config.image.gpu) { '-gpu' } else { '' }),
    $config.image.type.ToLower(),
    $config.image.format.ToLower());
  $vhdLocalPath = ('{0}{1}{2}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $imageName);

  if (Test-Path -Path $vhdLocalPath -ErrorAction SilentlyContinue) {
    Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('detected existing vhd: {0}, skipping image creation for {1}' -f $vhdLocalPath, $imageKey) -severity 'info';
  } else {
    $isoLocalPath = ('{0}{1}{2}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $config.iso.source.key);
    $unattendLocalPath = ('{0}{1}unattend-{2}-{3}.xml' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $targetCloudPlatform, $imageName.Replace('.', '-'));
    $driversLocalPath = ('{0}{1}drivers-{2}-{3}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $targetCloudPlatform, $imageName.Replace('.', '-'));
    $packagesLocalPath = ('{0}{1}packages-{2}-{3}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $targetCloudPlatform, $imageName.Replace('.', '-'));
    # https://docs.microsoft.com/en-us/windows-server/get-started/kmsclientkeys
    $productKey = (Invoke-WebRequest -Uri ('https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/{0}/product-keys.yaml' -f $revision) -UseBasicParsing | ConvertFrom-Yaml)."$($config.image.os)"."$($config.image.edition)";
    $drivers = @((Invoke-WebRequest -Uri ('https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/{0}/drivers.yaml' -f $revision) -UseBasicParsing | ConvertFrom-Yaml) | ? {
      $_.target.os.Contains($config.image.os) -and
      $_.target.architecture.Contains($config.image.architecture) -and
      $_.target.cloud.Contains($targetCloudPlatform) -and
      $_.target.gpu.Contains($config.image.gpu)
    });
    $unattendCommands = @((Invoke-WebRequest -Uri ('https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/{0}/unattend-commands.yaml' -f $revision) -UseBasicParsing | ConvertFrom-Yaml) | ? {
      $_.target.os.Contains($config.image.os) -and
      $_.target.architecture.Contains($config.image.architecture) -and
      $_.target.cloud.Contains($targetCloudPlatform) -and
      $_.target.gpu.Contains($config.image.gpu)
    });
    $packages = @((Invoke-WebRequest -Uri ('https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/{0}/packages.yaml' -f $revision) -UseBasicParsing | ConvertFrom-Yaml) | ? {
      $_.target.os.Contains($config.image.os) -and
      $_.target.architecture.Contains($config.image.architecture) -and
      $_.target.cloud.Contains($targetCloudPlatform) -and
      $_.target.gpu.Contains($config.image.gpu)
    });
    $disableWindowsService = @((Invoke-WebRequest -Uri ('https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/{0}/disable-windows-service.yaml' -f $revision) -UseBasicParsing | ConvertFrom-Yaml) | ? {
      $_.target.os.Contains($config.image.os) -and
      $_.target.architecture.Contains($config.image.architecture) -and
      $_.target.cloud.Contains($targetCloudPlatform)
    } | % { $_.name });
    if (-not (Test-Path -Path $isoLocalPath -ErrorAction SilentlyContinue)) {
      Get-CloudBucketResource `
        -platform $config.iso.source.platform `
        -bucket $config.iso.source.bucket `
        -key $config.iso.source.key `
        -destination $isoLocalPath `
        -force;  
    }
    do {
      $commands = @($unattendCommands | % { $_.unattend } | % { @{ 'Description' = $_.description; 'CommandLine' = $_.command } }) + @($packages | % { $_.unattend } | % { @{ 'Description' = $_.description; 'CommandLine' = $_.command } });
      try {
        New-UnattendFile `
          -destinationPath $unattendLocalPath `
          -uiLanguage $config.image.language `
          -productKey $productKey `
          -registeredOwner $config.image.owner `
          -registeredOrganization $config.image.organization `
          -administratorPassword (New-Password) `
          -commands $commands;
      } catch {
        Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('exception creating unattend: {0}. retrying... {1}' -f $unattendLocalPath, $_.Exception.Message) -severity 'warn';
      }
    } until (Test-Path -Path $unattendLocalPath -ErrorAction SilentlyContinue)
    Remove-Item -Path $driversLocalPath -Force -Recurse -ErrorAction SilentlyContinue;
    foreach ($driver in $drivers) {
      $driverLocalPath = ('{0}{1}{2}{3}' -f $driversLocalPath, ([IO.Path]::DirectorySeparatorChar), $driver.name, $(if ($driver.extract) { '.zip' } else { '' }));
      $sourceIndex = $driver.sources.Length;
      do {
        $source = $driver.sources[(--$sourceIndex)];
        if ($source.platform -eq 'url') {
          try {
            (New-Object Net.WebClient).DownloadFile($source.url, $driverLocalPath);
          } catch {
            Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('exception in driver download with Net.WebClient.DownloadFile from url: {0}, to: {1}. {2}' -f $source.url, $driverLocalPath, $_.Exception.Message) -severity 'error';
            try {
              Invoke-WebRequest -Uri $source.url -OutFile $driverLocalPath -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
            } catch {
              Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('exception in driver download with Invoke-WebRequest from url: {0}, to: {1}. {2}' -f $source.url, $driverLocalPath, $_.Exception.Message) -severity 'error';
            }
          }
        } else {
          try {
            Get-CloudBucketResource `
              -platform $source.platform `
              -bucket $source.bucket `
              -key $source.key `
              -destination $driverLocalPath `
              -force;
          } catch {
            Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('exception in driver download with Get-CloudBucketResource from bucket: {0}/{1}/{2}, to: {3}. {4}' -f $source.platform, $source.bucket, $source.key, $packageLocalTempPath, $_.Exception.Message) -severity 'error';
          }
        }
      } until ((Test-Path -Path $driverLocalPath -ErrorAction SilentlyContinue) -or ($sourceIndex -lt 0));
      if ($driver.extract) {
        Expand-Archive -Path $driverLocalPath -DestinationPath ('{0}{1}{2}' -f $driversLocalPath, ([IO.Path]::DirectorySeparatorChar), $driver.name)
      }
    }
    Convert-WindowsImage `
      -verbose:$true `
      -SourcePath $isoLocalPath `
      -VhdPath $vhdLocalPath `
      -VhdFormat $config.image.format `
      -VhdType $config.image.type `
      -VhdPartitionStyle $config.image.partition `
      -Edition $(if ($config.iso.wimindex) { $config.iso.wimindex } else { $config.image.edition }) -UnattendPath $unattendLocalPath `
      -Driver @($drivers | % { '{0}{1}{2}' -f $driversLocalPath, ([IO.Path]::DirectorySeparatorChar), $_.infpath }) `
      -RemoteDesktopEnable:$true `
      -DisableWindowsService $disableWindowsService `
      -DisableNotificationCenter:($config.image.os -eq 'Windows 10');


    $vhdMountPoint = (Join-Path -Path $workFolder -ChildPath ([System.Guid]::NewGuid().Guid.Substring(24)));
    New-Item -Path $vhdMountPoint -ItemType directory -force;
    try {
      Mount-WindowsImage -ImagePath $vhdLocalPath -Path $vhdMountPoint -Index 1
      Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('mounted: {0} at mount point: {1}' -f $vhdLocalPath, $vhdMountPoint) -severity 'trace';
    } catch {
      Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('failed to mount: {0} at mount point: {1}. {2}' -f $vhdLocalPath, $vhdMountPoint, $_.Exception.Message) -severity 'error';
      Dismount-WindowsImage -Path $vhdMountPoint -Save -ErrorAction SilentlyContinue
      throw
    }

    foreach ($package in $packages) {
      $packageLocalTempPath = ('{0}{1}{2}{3}' -f $packagesLocalPath, ([IO.Path]::DirectorySeparatorChar), $package.name, $(if (($package.extract) -and (-not $package.savepath.ToLower().EndsWith('.zip'))) { '.zip' } else { '' }));
      $sourceIndex = $package.sources.Length;
      do {
        $source = $package.sources[(--$sourceIndex)];
        if ($source.platform -eq 'url') {
          try {
            (New-Object Net.WebClient).DownloadFile($source.url, $packageLocalTempPath);
            Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('downloaded: {0} to: {1} with Net.WebClient.DownloadFile' -f $source.url, $packageLocalTempPath) -severity 'trace';
          } catch {
            Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('exception in package download with Net.WebClient.DownloadFile from url: {0}, to: {1}. {2}' -f $source.url, $packageLocalTempPath, $_.Exception.Message) -severity 'error';
            try {
              Invoke-WebRequest -Uri $source.url -OutFile $packageLocalTempPath -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
              Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('downloaded: {0} to: {1} with Invoke-WebRequest' -f $source.url, $packageLocalTempPath) -severity 'trace';
            } catch {
              Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('exception in package download with Invoke-WebRequest from url: {0}, to: {1}. {2}' -f $source.url, $packageLocalTempPath, $_.Exception.Message) -severity 'error';
            }
          }
        } else {
          try {
            Get-CloudBucketResource `
              -platform $source.platform `
              -bucket $source.bucket `
              -key $source.key `
              -destination $packageLocalTempPath `
              -force;
          } catch {
            Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('exception in package download with Get-CloudBucketResource from bucket: {0}/{1}/{2}, to: {3}. {4}' -f $source.platform, $source.bucket, $source.key, $packageLocalTempPath, $_.Exception.Message) -severity 'error';
          }
        }
      } until ((Test-Path -Path $packageLocalTempPath -ErrorAction SilentlyContinue) -or ($sourceIndex -lt 0));
      if (Test-Path -Path $packageLocalTempPath -ErrorAction SilentlyContinue) {
        $packageLocalMountPath = (Join-Path -Path $vhdMountPoint -ChildPath $package.savepath);
        if ($package.extract) {
          Expand-Archive -Path $packageLocalTempPath -DestinationPath $packageLocalMountPath;
        } else {
          Copy-Item -Path $packageLocalTempPath -Destination $packageLocalMountPath
        }
      } else {
        Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('failed to load image: {0} with package: {1}' -f $imageName, $package.savepath) -severity 'warn';
      }
    }
    # dismount the vhd, save it and remove the mount point
    try {
      Dismount-WindowsImage -Path $vhdMountPoint -Save
      Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('dismount success for: {0} at mount point: {1}' -f $vhdLocalPath, $vhdMountPoint) -severity 'trace';
    } catch {
      Write-Log -source ('build-{0}-images' -f $targetCloudPlatform) -message ('failed to dismount: {0} at mount point: {1}. {2}' -f $vhdLocalPath, $vhdMountPoint, $_.Exception.Message) -severity 'error';
      throw
    } finally {
      Remove-Item -Path $vhdMountPoint -Force
    }
  }

  foreach ($target in $config.target) {
    switch ($target.platform) {
      'azure' {
        Write-Log -source ('build-{0}-images' -f $target.platform) -message ('begin image: {0} deployment to: {1} cloud platform' -f $imageName, $target.platform) -severity 'info';

        $osDiskConfig = (@($target.disk | ? { $_.os })[0]);

        $diskConfig = (New-AzDiskConfig `
          -SkuName $osDiskConfig.type `
          -OsType 'Windows' `
          -UploadSizeInBytes ((Get-Item -Path $vhdLocalPath).Length) `
          -Location $target.region `
          -CreateOption 'Upload');
        $disk = New-AzDisk `
          -ResourceGroupName $target.group `
          -DiskName $osDiskConfig.source `
          -Disk $diskConfig;
        $diskAccess = Grant-AzDiskAccess `
          -ResourceGroupName $target.group `
          -DiskName $disk.Name `
          -DurationInSecond 86400 `
          -Access 'Write';
        & AzCopy.exe @('copy', $vhdLocalPath, ($diskAccess.AccessSAS), '--blob-type', 'PageBlob');
        Revoke-AzDiskAccess `
          -ResourceGroupName $target.group `
          -DiskName $disk.Name;

        switch ($target.hostname.slug.type) {
          'uuid' {
            $resourceId = (([Guid]::NewGuid()).ToString().Substring((36 - $target.hostname.slug.length)));
            $instanceName = ($target.hostname.format -f $resourceId);
            break;
          }
          default {
            $resourceId = (([Guid]::NewGuid()).ToString().Substring(24));
            $instanceName = ('vm-{0}' -f $resourceId);
            break;
          }
        }

        # networking
        $virtualNetwork = (Get-AzVirtualNetwork -Name $target.network.name);
        $networkSecurityGroup = (Get-AzNetworkSecurityGroup -Name $target.network.flow[0]);
        $publicIpAddress = New-AzPublicIpAddress `
          -Name ('ip-{0}' -f $resourceId) `
          -ResourceGroupName $target.group `
          -Location $target.region `
          -AllocationMethod 'Dynamic';

        $networkInterface = New-AzNetworkInterface `
          -Name ('ni-{0}' -f $resourceId) `
          -ResourceGroupName $target.group `
          -Location $target.region `
          -SubnetId $virtualNetwork.Subnets[0].Id `
          -PublicIpAddressId $publicIpAddress.Id `
          -NetworkSecurityGroupId $networkSecurityGroup.Id;

        # virtual machine
        $vm = Add-AzVMNetworkInterface `
          -VM (New-AzVMConfig -VMName $instanceName -VMSize $target.machine.type) `
          -Id $networkInterface.Id;
        $vm = Set-AzVMOSDisk `
          -VM $vm `
          -ManagedDiskId $disk.Id `
          -StorageAccountType $osDiskConfig.type `
          -DiskSizeInGB $osDiskConfig.size `
          -CreateOption 'Attach' `
          -Windows:$true;
        New-AzVM `
          -ResourceGroupName $target.group `
          -Location $target.region `
          -VM $vm;
        Get-AzVM `
          -ResourceGroupName $target.group `
          -Name $instanceName;

        Write-Log -source ('build-{0}-images' -f $target.platform) -message ('end image: {0} deployment to: {1} cloud platform' -f $imageName, $target.platform) -severity 'info';
        break;
      }
      default {
        Write-Log -source ('build-{0}-images' -f $target.platform) -message ('failed to load image: {0} with package: {1}' -f $imageName, $package.savepath) -severity 'warn';
        break;
      }
    }
  }
}
