# usage:
# Invoke-Expression (New-Object Net.WebClient).DownloadString(('https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/build-azure-images.ps1?{0}' -f [Guid]::NewGuid()))

# job settings. change these for the tasks at hand.
$targetCloudPlatform = 'azure';
$workFolder = ('{0}{1}{2}-ci' -f 'D:', ([IO.Path]::DirectorySeparatorChar), $targetCloudPlatform);
$workerTypes = @(
  #('gecko-t-win10-64-{0}' -f $targetCloudPlatform),
  #('gecko-t-win10-64-gpu-{0}' -f $targetCloudPlatform),
  ('gecko-1-win2012-{0}' -f $targetCloudPlatform)#,
  #('gecko-1-win2019-{0}' -f $targetCloudPlatform)
 );

# computed settings. these are probably ok as they are.
$pmmModuleName = 'posh-minions-managed';
$pmmModuleVersion = '0.0.20';
$pmmModule = (Get-Module -Name $pmmModuleName -ErrorAction SilentlyContinue);
if ($pmmModule) {
  if ($pmmModule.Version -lt $pmmModuleVersion) {
    Update-Module $pmmModuleName -RequiredVersion $pmmModuleVersion
  }
} else {
  Install-Module $pmmModuleName -RequiredVersion $pmmModuleVersion
}

foreach ($workerType in $workerTypes) {
  # worker type settings. these are probably ok as they are.
  $config = (Invoke-WebRequest -Uri 'https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/config.json' -UseBasicParsing | ConvertFrom-Json)."$workerType";
  $imageName = ('{0}-{1}-{2}-{3}{4}-{5}.{6}' -f $config.image.os.ToLower().Replace(' ', ''),
    $config.image.edition.ToLower(),
    $config.image.language.ToLower(),
    $config.image.architecture,
    $(if ($config.image.gpu) { '-gpu' } else { '' }),
    $config.image.type.ToLower(),
    $config.image.format.ToLower());
  $vhdLocalPath = ('{0}{1}{2}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $imageName);
  $isoLocalPath = ('{0}{1}{2}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $config.iso.source.key);
  $unattendLocalPath = ('{0}{1}unattend-{2}-{3}.xml' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $targetCloudPlatform, $imageName);
  $administratorPassword = (New-Password);
  # https://docs.microsoft.com/en-us/windows-server/get-started/kmsclientkeys
  $productKey = (Invoke-WebRequest -Uri 'https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/product-keys.json' -UseBasicParsing | ConvertFrom-Json)."$($config.image.os)"."$($config.image.edition)";
  $drivers = @((Invoke-WebRequest -Uri 'https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/drivers.json' -UseBasicParsing | ConvertFrom-Json) | ? {
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
  $driverFolder = ('{0}{1}driver' -f $workFolder, ([IO.Path]::DirectorySeparatorChar));
  if (-not (Test-Path -Path $isoLocalPath -ErrorAction SilentlyContinue)) {
    Get-CloudBucketResource `
      -platform $config.iso.source.platform `
      -bucket $config.iso.source.bucket `
      -key $config.iso.source.key `
      -destination $isoLocalPath `
      -force;  
  }
  #New-Item -Path ([System.IO.Path]::GetDirectoryName($unattendLocalPath)) -ItemType Directory -Force
  New-UnattendFile `
    -destinationPath $unattendLocalPath `
    -uiLanguage $config.image.language `
    -productKey $productKey `
    -registeredOwner $config.image.owner `
    -registeredOrganization $config.image.organization `
    -administratorPassword $administratorPassword;
  Remove-Item -Path $driverFolder -Force -Recurse -ErrorAction SilentlyContinue;
  foreach ($driver in $drivers) {
    $driverLocalPath = ('{0}{1}{2}{3}' -f $driverFolder, ([IO.Path]::DirectorySeparatorChar), $driver.name, $(if ($driver.extract) { '.zip' } else { '' }));
    Get-CloudBucketResource `
      -platform $driver.source.platform `
      -bucket $driver.source.bucket `
      -key $driver.source.key `
      -destination $driverLocalPath `
      -force;
    if ($driver.extract) {
      Expand-Archive -Path $driverLocalPath -DestinationPath ('{0}{1}{2}' -f $driverFolder, ([IO.Path]::DirectorySeparatorChar), $driver.name)
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
    -Driver @($drivers | % { '{0}{1}{2}' -f $driverFolder, ([IO.Path]::DirectorySeparatorChar), $_.infpath }) `
    -RemoteDesktopEnable:$true `
    -DisableWindowsService $disableWindowsService `
    -DisableNotificationCenter:($config.image.os -eq 'Windows 10');
}
