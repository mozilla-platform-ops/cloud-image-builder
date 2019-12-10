param (
  [string] $imageKey
)

# job settings. change these for the tasks at hand.
$VerbosePreference = 'continue';
$targetCloudPlatform = 'azure';
$workFolder = (Resolve-Path -Path ('{0}\..' -f $PSScriptRoot));

# constants and script config. these are probably ok as they are.
$revision = $(& git rev-parse HEAD);
if (@(Get-PSRepository -Name 'PSGallery')[0].InstallationPolicy -ne 'Trusted') {
  Set-PSRepository -Name 'PSGallery' -InstallationPolicy 'Trusted'
}
foreach ($rm in @(
  @{ 'module' = 'posh-minions-managed'; 'version' = '0.0.40' },
  @{ 'module' = 'powershell-yaml'; 'version' = '0.4.1' }
)) {
  $module = (Get-Module -Name $rm.module -ErrorAction SilentlyContinue);
  if ($module) {
    if ($module.Version -lt $rm.version) {
      Update-Module $rm.module -RequiredVersion $rm.version
    }
  } else {
    Install-Module $rm.module -RequiredVersion $rm.version -AllowClobber
  }
  Import-Module $rm.module -RequiredVersion $rm.version -ErrorAction SilentlyContinue
}
Write-Output -InputObject ('workFolder: {0}, revision: {1}, targetCloudPlatform: {2}, imageKey: {3}' -f $workFolder, $revision, $targetCloudPlatform, $imageKey);

$secret = (Invoke-WebRequest -Uri 'http://taskcluster/secrets/v1/secret/project/relops/image-builder/dev' -UseBasicParsing | ConvertFrom-Json).secret;
Set-AWSCredential `
  -AccessKey $secret.amazon.id `
  -SecretKey $secret.amazon.key `
  -StoreAs 'default';

Connect-AzAccount `
  -ServicePrincipal `
  -Credential (New-Object System.Management.Automation.PSCredential($secret.azure.id, (ConvertTo-SecureString `
    -String $secret.azure.key `
    -AsPlainText `
    -Force))) `
  -Tenant $secret.azure.account;

$azcopyExePath = ('{0}\System32\azcopy.exe' -f $env:WinDir);
$azcopyZipPath = ('{0}\azcopy.zip' -f $workFolder);
$azcopyZipUrl = 'https://aka.ms/downloadazcopy-v10-windows';
if (-not (Test-Path -Path $azcopyExePath -ErrorAction SilentlyContinue)) {
  (New-Object Net.WebClient).DownloadFile($azcopyZipUrl, $azcopyZipPath);
  if (Test-Path -Path $azcopyZipPath -ErrorAction SilentlyContinue) {
    Write-Output -InputObject ('downloaded: {0} from: {1}' -f $azcopyZipPath, $azcopyZipUrl);
    Expand-Archive -Path $azcopyZipPath -DestinationPath $workFolder;
    try {
      $extractedAzcopyExePath = (@(Get-ChildItem -Path ('{0}\azcopy.exe' -f $workFolder) -Recurse -ErrorAction SilentlyContinue -Force)[0].FullName);
      Write-Output -InputObject ('extracted: {0} from: {1}' -f $extractedAzcopyExePath, $azcopyZipPath);
      Copy-Item -Path $extractedAzcopyExePath -Destination $azcopyExePath;
      if (Test-Path -Path $azcopyExePath -ErrorAction SilentlyContinue) {
        Write-Output -InputObject ('copied: {0} to: {1}' -f $extractedAzcopyExePath, $azcopyExePath);
      }
    } catch {
      Write-Output -InputObject ('failed to extract azcopy from: {0}' -f $azcopyZipPath);
    }
  }
}

# computed target specific settings. these are probably ok as they are.
$config = (Get-Content -Path ('{0}\cloud-image-builder\config\{1}.yaml' -f $workFolder, $imageKey) -Raw | ConvertFrom-Yaml);
if (-not ($config)) {
  Write-Output -InputObject ('error: failed to find image config for {0}' -f $imageKey);
  exit 1
} else {
  Write-Output -InputObject $config.image
}
$exportImageName = ('{0}-{1}-{2}-{3}{4}-{5}.{6}' -f $config.image.os.ToLower().Replace(' ', ''),
  $config.image.edition.ToLower(),
  $config.image.language.ToLower(),
  $config.image.architecture,
  $(if ($config.image.gpu) { '-gpu' } else { '' }),
  $config.image.type.ToLower(),
  $config.image.format.ToLower());
$vhdLocalPath = ('{0}{1}{2}-{3}-{4}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $revision.Substring(0, 7), $targetCloudPlatform, $exportImageName);

if (Test-Path -Path $vhdLocalPath -ErrorAction SilentlyContinue) {
  Write-Output -InputObject ('detected existing vhd: {0}, skipping image creation for {1}' -f $vhdLocalPath, $imageKey);
} else {
  $isoLocalPath = ('{0}{1}{2}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $config.iso.source.key);
  $unattendLocalPath = ('{0}{1}{2}-unattend-{3}-{4}.xml' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $revision.Substring(0, 7), $targetCloudPlatform, $exportImageName.Replace('.', '-'));
  $driversLocalPath = ('{0}{1}{2}-drivers-{3}-{4}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $revision.Substring(0, 7), $targetCloudPlatform, $exportImageName.Replace('.', '-'));
  $packagesLocalPath = ('{0}{1}{2}-packages-{3}-{4}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $revision.Substring(0, 7), $targetCloudPlatform, $exportImageName.Replace('.', '-'));
  # https://docs.microsoft.com/en-us/windows-server/get-started/kmsclientkeys
  $productKey = (Get-Content -Path ('config\product-keys.yaml' -f $workFolder) -Raw | ConvertFrom-Yaml)."$($config.image.os)"."$($config.image.edition)";
  $drivers = @((Get-Content -Path ('config\drivers.yaml' -f $workFolder) -Raw | ConvertFrom-Yaml) | ? {
    $_.target.os.Contains($config.image.os) -and
    $_.target.architecture.Contains($config.image.architecture) -and
    $_.target.cloud.Contains($targetCloudPlatform) -and
    $_.target.gpu.Contains($config.image.gpu)
  });
  $unattendCommands = @((Get-Content -Path ('config\unattend-commands.yaml' -f $workFolder) -Raw | ConvertFrom-Yaml) | ? {
    $_.target.os.Contains($config.image.os) -and
    $_.target.architecture.Contains($config.image.architecture) -and
    $_.target.cloud.Contains($targetCloudPlatform) -and
    $_.target.gpu.Contains($config.image.gpu)
  });
  $packages = @((Get-Content -Path ('config\packages.yaml' -f $workFolder) -Raw | ConvertFrom-Yaml) | ? {
    $_.target.os.Contains($config.image.os) -and
    $_.target.architecture.Contains($config.image.architecture) -and
    $_.target.cloud.Contains($targetCloudPlatform) -and
    $_.target.gpu.Contains($config.image.gpu)
  });
  $disableWindowsService = @((Get-Content -Path ('config\disable-windows-service.yaml' -f $workFolder) -Raw | ConvertFrom-Yaml) | ? {
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
      # todo: set processorArchitecture, computerName, administratorPassword
      #-processorArchitecture $(if ($config.image.architecture -eq 'x86-64') { 'amd64' } else { $config.image.architecture }) `
      #-computerName '*' `
      #-administratorPassword (New-Password) `
      New-UnattendFile `
        -destinationPath $unattendLocalPath `
        -uiLanguage $config.image.language `
        -productKey $productKey `
        -registeredOwner $config.image.owner `
        -registeredOrganization $config.image.organization `
        -commands $commands;
    } catch {
      Write-Output -InputObject ('exception creating unattend: {0}. retrying... {1}' -f $unattendLocalPath, $_.Exception.Message);
    }
  } until (Test-Path -Path $unattendLocalPath -ErrorAction SilentlyContinue)
  Remove-Item -Path $driversLocalPath -Force -Recurse -ErrorAction SilentlyContinue;
  New-Item -Path $driversLocalPath -ItemType Directory -Force;
  foreach ($driver in $drivers) {
    $driverLocalPath = ('{0}{1}{2}{3}' -f $driversLocalPath, ([IO.Path]::DirectorySeparatorChar), $driver.name, $(if ($driver.extract) { '.zip' } else { '' }));
    try {
      $sourceIndex = [int]$driver.sources.Length;
    } catch {
      $sourceIndex = 1;
    }
    do {
      $source = $driver.sources[(--$sourceIndex)];
      if ($source.platform -eq 'url') {
        try {
          (New-Object Net.WebClient).DownloadFile($source.url, $driverLocalPath);
        } catch {
          Write-Output -InputObject ('exception in driver download with Net.WebClient.DownloadFile from url: {0}, to: {1}. {2}' -f $source.url, $driverLocalPath, $_.Exception.Message);
          try {
            Invoke-WebRequest -Uri $source.url -OutFile $driverLocalPath -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
          } catch {
            Write-Output -InputObject ('exception in driver download with Invoke-WebRequest from url: {0}, to: {1}. {2}' -f $source.url, $driverLocalPath, $_.Exception.Message);
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
          Write-Output -InputObject ('exception in driver download with Get-CloudBucketResource from bucket: {0}/{1}/{2}, to: {3}. {4}' -f $source.platform, $source.bucket, $source.key, $driverLocalPath, $_.Exception.Message);
        }
      }
    } until ((Test-Path -Path $driverLocalPath -ErrorAction SilentlyContinue) -or ($sourceIndex -lt 0));
    if ($driver.extract) {
      Expand-Archive -Path $driverLocalPath -DestinationPath ('{0}{1}{2}' -f $driversLocalPath, ([IO.Path]::DirectorySeparatorChar), $driver.name);
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
  New-Item -Path $vhdMountPoint -ItemType Directory -Force;
  try {
    Mount-WindowsImage -ImagePath $vhdLocalPath -Path $vhdMountPoint -Index 1
    Write-Output -InputObject ('mounted: {0} at mount point: {1}' -f $vhdLocalPath, $vhdMountPoint);
  } catch {
    Write-Output -InputObject ('failed to mount: {0} at mount point: {1}. {2}' -f $vhdLocalPath, $vhdMountPoint, $_.Exception.Message);
    Dismount-WindowsImage -Path $vhdMountPoint -Save -ErrorAction SilentlyContinue
    throw
  }

  New-Item -Path $packagesLocalPath -ItemType Directory -Force;
  foreach ($package in $packages) {
    $packageLocalTempPath = ('{0}{1}{2}{3}' -f $packagesLocalPath, ([IO.Path]::DirectorySeparatorChar), $package.name, $(if (($package.extract) -and (-not $package.savepath.ToLower().EndsWith('.zip'))) { '.zip' } else { '' }));
    try {
      $sourceIndex = [int]$package.sources.Length;
    } catch {
      $sourceIndex = 1;
    }
    do {
      $source = $package.sources[(--$sourceIndex)];
      if ($source.platform -eq 'url') {
        try {
          (New-Object Net.WebClient).DownloadFile($source.url, $packageLocalTempPath);
          Write-Output -InputObject ('downloaded: {0} to: {1} with Net.WebClient.DownloadFile' -f $source.url, $packageLocalTempPath);
        } catch {
          Write-Output -InputObject ('exception in package download with Net.WebClient.DownloadFile from url: {0}, to: {1}. {2}' -f $source.url, $packageLocalTempPath, $_.Exception.Message);
          try {
            Invoke-WebRequest -Uri $source.url -OutFile $packageLocalTempPath -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
            Write-Output -InputObject ('downloaded: {0} to: {1} with Invoke-WebRequest' -f $source.url, $packageLocalTempPath);
          } catch {
            Write-Output -InputObject ('exception in package download with Invoke-WebRequest from url: {0}, to: {1}. {2}' -f $source.url, $packageLocalTempPath, $_.Exception.Message);
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
          Write-Output -InputObject ('exception in package download with Get-CloudBucketResource from bucket: {0}/{1}/{2}, to: {3}. {4}' -f $source.platform, $source.bucket, $source.key, $packageLocalTempPath, $_.Exception.Message);
        }
      }
    } until ((Test-Path -Path $packageLocalTempPath -ErrorAction SilentlyContinue) -or ($sourceIndex -lt 0));
    if (Test-Path -Path $packageLocalTempPath -ErrorAction SilentlyContinue) {
      $packageLocalMountPath = (Join-Path -Path $vhdMountPoint -ChildPath $package.savepath);
      if ($package.extract) {
        Expand-Archive -Path $packageLocalTempPath -DestinationPath $packageLocalMountPath;
      } else {
        Copy-Item -Path $packageLocalTempPath -Destination $packageLocalMountPath;
      }
    } else {
      Write-Output -InputObject ('failed to load image: {0} with package: {1}' -f $exportImageName, $package.savepath);
    }
  }
  # dismount the vhd, save it and remove the mount point
  try {
    Dismount-WindowsImage -Path $vhdMountPoint -Save
    Write-Output -InputObject ('dismount success for: {0} at mount point: {1}' -f $vhdLocalPath, $vhdMountPoint);
  } catch {
    Write-Output -InputObject ('failed to dismount: {0} at mount point: {1}. {2}' -f $vhdLocalPath, $vhdMountPoint, $_.Exception.Message);
    throw
  } finally {
    Remove-Item -Path $vhdMountPoint -Force
  }
}
foreach ($target in @($config.target | ? { $_.platform -eq $targetCloudPlatform })) {
  Write-Log -source ('build-{0}-images' -f $target.platform) -message ('begin image export: {0}, to region: {1}, in cloud platform: {2}' -f $exportImageName, $target.region, $target.platform);
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
  $osDiskConfig = (@($target.disk | ? { $_.os })[0]);
  $tags = @{
    'buildRevision' = $revision;
    'imageKey' = $imageKey;
    'resourceId' = $resourceId;
    'sourceIso' = ([System.IO.Path]::GetFileName($config.iso.source.key))
  };
  foreach ($tag in $target.tag) {
    $tags[$tag.name] = $tag.value;
  }
  New-CloudInstanceFromImageExport `
    -platform $target.platform `
    -localImagePath $vhdLocalPath `
    -targetResourceId $resourceId `
    -targetResourceGroupName $target.group `
    -targetResourceRegion $target.region `
    -targetInstanceMachineVariantFormat $target.machine.format `
    -targetInstanceCpuCount $target.machine.cpu `
    -targetInstanceRamGb $target.machine.ram `
    -targetInstanceName $instanceName `
    -targetInstanceDiskVariant $osDiskConfig.variant `
    -targetInstanceDiskSizeGb $osDiskConfig.size `
    -targetInstanceTags $tags `
    -targetVirtualNetworkName $target.network.name `
    -targetVirtualNetworkAddressPrefix $target.network.prefix `
    -targetVirtualNetworkDnsServers $target.network.dns `
    -targetSubnetName $target.network.subnet.name `
    -targetSubnetAddressPrefix $target.network.subnet.prefix

  do {
    $azVm = (Get-AzVm -ResourceGroupName $target.group -Name $instanceName -ErrorAction SilentlyContinue);
    if ($azVm) {
      if (@('Succeeded', 'Failed') -contains $azVm.ProvisioningState) {
        Write-Log -source ('build-{0}-images' -f $target.platform) -message ('provisioning of vm: {0}, {1}' -f $instanceName, $azVm.ProvisioningState.ToLower());
      } else {
        Write-Log -source ('build-{0}-images' -f $target.platform) -message ('provisioning of vm: {0}, in progress with state: {1}' -f $instanceName, $azVm.ProvisioningState.ToLower());
        Start-Sleep -Seconds 60
      }
    } else {
      Write-Log -source ('build-{0}-images' -f $target.platform) -message ('provisioning of vm: {0}, failed before it started' -f $instanceName);
    }
  } until ((-not $azVm) -or (@('Succeeded', 'Failed') -contains $azVm.ProvisioningState))
  Write-Log -source ('build-{0}-images' -f $target.platform) -message ('end image export: {0} to: {1} cloud platform' -f $exportImageName, $target.platform);

  if ($azVm) {
    $importImageName = ('{0}-{1}' -f $target.group, $imageKey.Replace(('-{0}' -f $targetCloudPlatform), ''));
    Write-Log -source ('build-{0}-images' -f $target.platform) -message ('begin image import: {0} in region: {1}, cloud platform: {2}' -f $importImageName, $target.region, $target.platform);
    
    (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/azure/userdata/rundsc.ps1', ('{0}\rundsc.ps1' -f $env:Temp));

    # the first time occ runs, it renames the instance and reboots
    $firstOccTriggerCommandResult = (Invoke-AzVMRunCommand `
      -ResourceGroupName $target.group `
      -VMName $instanceName `
      -CommandId 'RunPowerShellScript' `
      -ScriptPath ('{0}\rundsc.ps1' -f $env:Temp)); #-Parameter @{"arg1" = "var1";"arg2" = "var2"}
    Write-Log -source ('build-{0}-images' -f $target.platform) -message ('first occ trigger {0} on instance: {1} in region: {2}, cloud platform: {3}' -f $firstOccTriggerCommandResult.Status.ToLower(), $instanceName, $target.region, $target.platform);
    Write-Log -source ('build-{0}-images' -f $target.platform) -message ('first occ trigger std out: {0}' -f $firstOccTriggerCommandResult.Value[0].Message);
    Write-Log -source ('build-{0}-images' -f $target.platform) -message ('first occ trigger std err: {0}' -f $firstOccTriggerCommandResult.Value[1].Message);

    if ($firstOccTriggerCommandResult.Status -eq 'Succeeded') {

      Set-Content -Path ('{0}\computername.ps1' -f $env:Temp) -Value '$env:ComputerName';
      $echoHostnameCommandOutput = '';
      do {
        $echoHostnameResult = (Invoke-AzVMRunCommand `
          -ResourceGroupName $target.group `
          -VMName $instanceName `
          -CommandId 'RunPowerShellScript' `
          -ScriptPath ('{0}\computername.ps1' -f $env:Temp) `
          -ErrorAction SilentlyContinue);
        Write-Log -source ('build-{0}-images' -f $target.platform) -message ('echo hostname {0} on instance: {1} in region: {2}, cloud platform: {3}' -f $echoHostnameResult.Status.ToLower(), $instanceName, $target.region, $target.platform);
        if ($echoHostnameResult.Value) {
          $echoHostnameCommandOutput = $echoHostnameResult.Value[0].Message;
          Write-Log -source ('build-{0}-images' -f $target.platform) -message ('echo hostname std out: {0}' -f $echoHostnameResult.Value[0].Message);
          Write-Log -source ('build-{0}-images' -f $target.platform) -message ('echo hostname std err: {0}' -f $echoHostnameResult.Value[1].Message);
        } else {
          Write-Log -source ('build-{0}-images' -f $target.platform) -message 'echo hostname command did not return a value';
        }
        if ($echoHostnameCommandOutput -match $instanceName) {
          Write-Log -source ('build-{0}-images' -f $target.platform) -message ('host rename to: {0}, detected' -f $instanceName);
        } else {
          Write-Log -source ('build-{0}-images' -f $target.platform) -message ('awaiting host rename to: {0}' -f $instanceName);
          Start-Sleep -Seconds 30;
        }
      } until ($echoHostnameCommandOutput -match $instanceName)
      Remove-Item -Path ('{0}\computername.ps1' -f $env:Temp);
      # todo: validate that the instance rebooted after the host rename.

      # the second time occ runs, it invokes dsc
      $secondOccTriggerCommandResult = (Invoke-AzVMRunCommand `
        -ResourceGroupName $target.group `
        -VMName $instanceName `
        -CommandId 'RunPowerShellScript' `
        -ScriptPath ('{0}\rundsc.ps1' -f $env:Temp));
      Remove-Item -Path ('{0}\rundsc.ps1' -f $env:Temp);

      Write-Log -source ('build-{0}-images' -f $target.platform) -message ('seccond occ trigger {0} on instance: {1} in region: {2}, cloud platform: {3}' -f $secondOccTriggerCommandResult.Status.ToLower(), $instanceName, $target.region, $target.platform);
      Write-Log -source ('build-{0}-images' -f $target.platform) -message ('seccond occ trigger std out: {0}' -f $secondOccTriggerCommandResult.Value[0].Message);
      Write-Log -source ('build-{0}-images' -f $target.platform) -message ('seccond occ trigger std err: {0}' -f $secondOccTriggerCommandResult.Value[1].Message);

      if ($secondOccTriggerCommandResult.Status -eq 'Succeeded') {

        Set-Content -Path ('{0}\dirdsc.ps1' -f $env:Temp) -Value 'Get-ChildItem -Path "C:\dsc"';
        $dirDscCommandOutput = '';
        do {
          $dirDscResult = (Invoke-AzVMRunCommand `
            -ResourceGroupName $target.group `
            -VMName $instanceName `
            -CommandId 'RunPowerShellScript' `
            -ScriptPath ('{0}\dirdsc.ps1' -f $env:Temp) `
            -ErrorAction SilentlyContinue);
          Write-Log -source ('build-{0}-images' -f $target.platform) -message ('dir dsc {0} on instance: {1} in region: {2}, cloud platform: {3}' -f $dirDscResult.Status.ToLower(), $instanceName, $target.region, $target.platform);
          if ($dirDscResult.Value) {
            $dirDscCommandOutput = $dirDscResult.Value[0].Message;
            Write-Log -source ('build-{0}-images' -f $target.platform) -message ('dir dsc std out: {0}' -f $dirDscResult.Value[0].Message);
            Write-Log -source ('build-{0}-images' -f $target.platform) -message ('dir dsc std err: {0}' -f $dirDscResult.Value[1].Message);
          } else {
            Write-Log -source ('build-{0}-images' -f $target.platform) -message 'dir dsc command did not return a value';
          }
          if ($dirDscCommandOutput -match 'task-claim-state.valid') {
            Write-Log -source ('build-{0}-images' -f $target.platform) -message ('occ completion on: {0}, detected' -f $instanceName);
          } else {
            Write-Log -source ('build-{0}-images' -f $target.platform) -message ('awaiting occ completion on: {0}' -f $instanceName);
            Start-Sleep -Seconds 30;
          }
        } until ($dirDscCommandOutput -match 'task-claim-state.valid')
        Remove-Item -Path ('{0}\dirdsc.ps1' -f $env:Temp);

        New-CloudImageFromInstance `
          -platform $target.platform `
          -resourceGroupName $target.group `
          -region $target.region `
          -instanceName $instanceName `
          -imageName $importImageName;
        $azVm = (Get-AzVm `
          -ResourceGroupName $target.group `
          -Name $instanceName `
          -Status `
          -ErrorAction SilentlyContinue);
        $azImage = (Get-AzImage `
          -ResourceGroupName $target.group `
          -ImageName $importImageName `
          -ErrorAction SilentlyContinue);
        if ($azImage) {
          Write-Log -source ('build-{0}-images' -f $target.platform) -message ('image: {0}, creation appears successful in region: {1}, cloud platform: {2}' -f $importImageName, $target.region, $target.platform);
          if (($azVm) -and (@($azVm.Statuses | ? { ($_.Code -eq 'OSState/generalized') -or ($_.Code -eq 'PowerState/deallocated') }).Length -eq 2)) {
            Remove-AzVm `
              -ResourceGroupName $target.group `
              -Name $instanceName `
              -Force;
          }
        } else {
          Write-Log -source ('build-{0}-images' -f $target.platform) -message ('image: {0}, creation appears unsuccessful in region: {1}, cloud platform: {2}' -f $importImageName, $target.region, $target.platform);
        }
      }
    }
    Write-Log -source ('build-{0}-images' -f $target.platform) -message ('end image import: {0} in region: {1}, cloud platform: {2}' -f $importImageName, $target.region, $target.platform);
  } else {
    Write-Log -source ('build-{0}-images' -f $target.platform) -message ('skipped image import: {0} in region: {1}, cloud platform: {2}' -f $importImageName, $target.region, $target.platform);
  }
}