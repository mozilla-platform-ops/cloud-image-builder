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
# constants. these are probably ok as they are.
$pmmModuleName = 'posh-minions-managed';
$pmmModuleVersion = '0.0.21';
$pmmModule = (Get-Module -Name $pmmModuleName -ErrorAction SilentlyContinue);
if ($pmmModule) {
  if ($pmmModule.Version -lt $pmmModuleVersion) {
    Update-Module $pmmModuleName -RequiredVersion $pmmModuleVersion
  }
} else {
  Install-Module $pmmModuleName -RequiredVersion $pmmModuleVersion
}

foreach ($imageKey in $imagesToBuild) {
  # computed target specific settings. these are probably ok as they are.
  $config = (Invoke-WebRequest -Uri 'https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/config.json' -UseBasicParsing | ConvertFrom-Json)."$imageKey";
  $imageName = ('{0}-{1}-{2}-{3}{4}-{5}.{6}' -f $config.image.os.ToLower().Replace(' ', ''),
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
    $productKey = (Invoke-WebRequest -Uri 'https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/product-keys.json' -UseBasicParsing | ConvertFrom-Json)."$($config.image.os)"."$($config.image.edition)";
    $drivers = @((Invoke-WebRequest -Uri 'https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/drivers.json' -UseBasicParsing | ConvertFrom-Json) | ? {
      $_.target.os.Contains($config.image.os) -and
      $_.target.architecture.Contains($config.image.architecture) -and
      $_.target.cloud.Contains($targetCloudPlatform) -and
      $_.target.gpu.Contains($config.image.gpu)
    });
    $packages = @((Invoke-WebRequest -Uri 'https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/packages.json' -UseBasicParsing | ConvertFrom-Json) | ? {
      $_.target.os.Contains($config.image.os) -and
      $_.target.architecture.Contains($config.image.architecture) -and
      $_.target.cloud.Contains($targetCloudPlatform) -and
      $_.target.gpu.Contains($config.image.gpu)
    });
    $disableWindowsService = @((Invoke-WebRequest -Uri 'https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/disable-windows-service.json' -UseBasicParsing | ConvertFrom-Json) | ? {
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
      try {
        New-UnattendFile `
          -destinationPath $unattendLocalPath `
          -uiLanguage $config.image.language `
          -productKey $productKey `
          -registeredOwner $config.image.owner `
          -registeredOrganization $config.image.organization `
          -administratorPassword (New-Password) `
          -commands @($packages | % { $_.unattend } | % { @{ 'Description' = $_.description; 'CommandLine' = $_.command } });
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
      -Package @($packages | % { '{0}{1}{2}' -f $packagesLocalPath, ([IO.Path]::DirectorySeparatorChar), $_.savepath }) `
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
}
