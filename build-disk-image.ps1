param (
  [Parameter(Mandatory = $true)]
  [ValidateSet('amazon', 'azure', 'google')]
  [string] $platform,

  [Parameter(Mandatory = $true)]
  [ValidateSet('win10-64-occ', 'win10-64', 'win10-64-gpu', 'win7-32', 'win7-32-gpu', 'win2012', 'win2019')]
  [string] $imageKey
)

# job settings. change these for the tasks at hand.
#$VerbosePreference = 'continue';
$workFolder = (Resolve-Path -Path ('{0}\..' -f $PSScriptRoot));

# constants and script config. these are probably ok as they are.
$revision = $(& git rev-parse HEAD);
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
    'version' = '0.0.91'
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
Write-Output -InputObject ('workFolder: {0}, revision: {1}, platform: {2}, imageKey: {3}' -f $workFolder, $revision, $platform, $imageKey);

$secret = (Invoke-WebRequest -Uri 'http://taskcluster/secrets/v1/secret/project/relops/image-builder/dev' -UseBasicParsing | ConvertFrom-Json).secret;
Set-AWSCredential `
  -AccessKey $secret.amazon.id `
  -SecretKey $secret.amazon.key `
  -StoreAs 'default' | Out-Null;


switch ($platform) {
  'azure' {
    Connect-AzAccount `
      -ServicePrincipal `
      -Credential (New-Object System.Management.Automation.PSCredential($secret.azure.id, (ConvertTo-SecureString `
        -String $secret.azure.key `
        -AsPlainText `
        -Force))) `
      -Tenant $secret.azure.account | Out-Null;

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
          Write-Output -InputObject ('failed to extract azcopy from: {0}. {1}' -f $azcopyZipPath, , $_.Exception.Message);
        }
      } else {
        Write-Output -InputObject ('failed to download: {0} from: {1}' -f $azcopyZipPath, $azcopyZipUrl);
        exit 123;
      }
    }
  }
}

# computed target specific settings. these are probably ok as they are.
$config = (Get-Content -Path ('{0}\cloud-image-builder\config\{1}.yaml' -f $workFolder, $imageKey) -Raw | ConvertFrom-Yaml);
if (-not ($config)) {
  Write-Output -InputObject ('error: failed to find image config for {0}' -f $imageKey);
  exit 1
}
$exportImageName = ('{0}-{1}-{2}-{3}{4}-{5}.{6}' -f $config.image.os.ToLower().Replace(' ', ''),
  $config.image.edition.ToLower(),
  $config.image.language.ToLower(),
  $config.image.architecture,
  $(if ($config.image.gpu) { '-gpu' } else { '' }),
  $config.image.type.ToLower(),
  $config.image.format.ToLower());
$vhdLocalPath = ('{0}{1}{2}-{3}-{4}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $revision.Substring(0, 7), $platform, $exportImageName);

if (Test-Path -Path $vhdLocalPath -ErrorAction SilentlyContinue) {
  Write-Output -InputObject ('detected existing vhd: {0}, skipping image creation for {1}' -f $vhdLocalPath, $imageKey);
} else {
  $isoLocalPath = ('{0}{1}{2}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $config.iso.source.key);
  $unattendLocalPath = ('{0}{1}{2}-unattend-{3}-{4}.xml' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $revision.Substring(0, 7), $platform, $exportImageName.Replace('.', '-'));
  $driversLocalPath = ('{0}{1}{2}-drivers-{3}-{4}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $revision.Substring(0, 7), $platform, $exportImageName.Replace('.', '-'));
  $packagesLocalPath = ('{0}{1}{2}-packages-{3}-{4}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $revision.Substring(0, 7), $platform, $exportImageName.Replace('.', '-'));
  # https://docs.microsoft.com/en-us/windows-server/get-started/kmsclientkeys
  $productKey = (Get-Content -Path ('{0}\cloud-image-builder\config\product-keys.yaml' -f $workFolder) -Raw | ConvertFrom-Yaml)."$($config.image.os)"."$($config.image.edition)";
  $drivers = @((Get-Content -Path ('{0}\cloud-image-builder\config\drivers.yaml' -f $workFolder) -Raw | ConvertFrom-Yaml) | ? {
    $_.target.os.Contains($config.image.os) -and
    $_.target.architecture.Contains($config.image.architecture) -and
    $_.target.cloud.Contains($platform) -and
    $_.target.gpu.Contains($config.image.gpu)
  });
  $unattendCommands = @((Get-Content -Path ('{0}\cloud-image-builder\config\unattend-commands.yaml' -f $workFolder) -Raw | ConvertFrom-Yaml) | ? {
    $_.target.os.Contains($config.image.os) -and
    $_.target.architecture.Contains($config.image.architecture) -and
    $_.target.cloud.Contains($platform) -and
    $_.target.gpu.Contains($config.image.gpu)
  });
  $packages = @((Get-Content -Path ('{0}\cloud-image-builder\config\packages.yaml' -f $workFolder) -Raw | ConvertFrom-Yaml) | ? {
    $_.target.os.Contains($config.image.os) -and
    $_.target.architecture.Contains($config.image.architecture) -and
    $_.target.cloud.Contains($platform) -and
    $_.target.gpu.Contains($config.image.gpu)
  });
  $disableWindowsService = @((Get-Content -Path ('{0}\cloud-image-builder\config\disable-windows-service.yaml' -f $workFolder) -Raw | ConvertFrom-Yaml) | ? {
    $_.target.os.Contains($config.image.os) -and
    $_.target.architecture.Contains($config.image.architecture) -and
    $_.target.cloud.Contains($platform)
  } | % { $_.name });
  if (-not (Test-Path -Path $isoLocalPath -ErrorAction SilentlyContinue)) {
    Get-CloudBucketResource `
      -platform $config.iso.source.platform `
      -bucket $config.iso.source.bucket `
      -key $config.iso.source.key `
      -destination $isoLocalPath `
      -force;  
  }
  $unattendGenerationAttemptCount = 0;
  do {
    $unattendGenerationAttemptCount += 1;
    $commands = @($unattendCommands | Sort-Object -Property 'priority' | % {
      @{
        'Description'   = $_.description;
        'CommandLine'   = $_.command;
        'Synchronicity' = $(if ($_.synchronicity) { $_.synchronicity } else { 'synchronous' });
        'Pass'          = $(if ($_.pass) { $_.pass } else { 'oobeSystem' });
        'WillReboot'    = $(if ($_.reboot) { $_.reboot } else { 'Never' })
      } 
    }) + @($packages | % { $_.unattend } | Sort-Object -Property 'priority' | % {
      @{
        'Description'   = $_.description;
        'CommandLine'   = $_.command;
        'Synchronicity' = $(if ($_.synchronicity) { $_.synchronicity } else { 'synchronous' });
        'Pass'          = $(if ($_.pass) { $_.pass } else { 'oobeSystem' });
        'WillReboot'    = $(if ($_.reboot) { $_.reboot } else { 'Never' })
      }
    });
    try {
      $administratorPassword = (New-Password);
      New-UnattendFile `
        -destinationPath $unattendLocalPath `
        -processorArchitecture $(if ($config.image.architecture -eq 'x86-64') { 'amd64' } else { $config.image.architecture }) `
        -computerName $(if ($config.image.hostname) { $config.image.hostname } else { '*' }) `
        -productKey $productKey `
        -timeZone $(if ($config.image.timezone) { $config.image.timezone } else { 'UTC' }) `
        -administratorPassword $administratorPassword `
        -obfuscatePassword:$(if ($config.image.obfuscate) { $true } else { $false }) `
        -oobeSystemResealMode $(if (($config.image.reseal) -and ($config.image.reseal.mode)) { $config.image.reseal.mode } else { 'OOBE' }) `
        -oobeSystemResealShutdown:$(if (($config.image.reseal) -and ($config.image.reseal.shutdown)) { $true } else { $false }) `
        -oobeSystemResealOmit $(if ((-not ($config.image.reseal)) -or $config.image.reseal.omit) { $true } else { $false }) `
        -generalizeMode $(if (($config.image.generalize) -and ($config.image.generalize.mode)) { $config.image.generalize.mode } else { 'OOBE' }) `
        -generalizeShutdown:$(if (($config.image.generalize) -and ($config.image.generalize.shutdown)) { $true } else { $false }) `
        -generalizeOmit $(if ((-not ($config.image.generalize)) -or $config.image.generalize.omit) { $true } else { $false }) `
        -auditSystemResealOmit $true `
        -auditUserResealOmit $true `
        -uiLanguage $config.image.language `
        -registeredOwner $config.image.owner `
        -registeredOrganization $config.image.organization `
        -networkLocation $(if ($config.image.network) { $config.image.network } else { 'Other' }) `
        -commands $commands `
        -os $config.image.os `
        -enableRDP $(if ($config.image.rdp) { $true } else { $false });
      Copy-Item -Path $unattendLocalPath -Destination ('{0}{1}unattend.xml' -f $workFolder, ([IO.Path]::DirectorySeparatorChar))
    } catch {
      Write-Output -InputObject ('exception creating unattend: {0}. retrying... {1}' -f $unattendLocalPath, $_.Exception.Message);
    }
  } until ((Test-Path -Path $unattendLocalPath -ErrorAction SilentlyContinue) -or ($unattendGenerationAttemptCount -gt 9))
  if (-not (Test-Path -Path $unattendLocalPath -ErrorAction SilentlyContinue)) {
    Write-Output -InputObject ('failed to generate unattend file at: {0}, in {1} attempts' -f $unattendLocalPath, $unattendGenerationAttemptCount);
    exit 1
  }
  Remove-Item -Path $driversLocalPath -Force -Recurse -ErrorAction SilentlyContinue;
  New-Item -Path $driversLocalPath -ItemType Directory -Force | Out-Null;
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
  if (($drivers) -and ($drivers.Length)) {
    Convert-WindowsImage `
      -SourcePath $isoLocalPath `
      -VhdPath $vhdLocalPath `
      -VhdFormat $config.image.format `
      -VhdType $config.image.type `
      -VhdPartitionStyle $config.image.partition `
      -Edition $(if ($config.iso.wimindex) { $config.iso.wimindex } else { $config.image.edition }) -UnattendPath $unattendLocalPath `
      -Driver @($drivers | % { '{0}{1}{2}' -f $driversLocalPath, ([IO.Path]::DirectorySeparatorChar), $_.infpath }) `
      -RemoteDesktopEnable:$true `
      -DisableWindowsService $disableWindowsService `
      -DisableNotificationCenter:($config.image.os -eq 'Windows 10') `
      -Verbose;
  } else {
    Convert-WindowsImage `
      -SourcePath $isoLocalPath `
      -VhdPath $vhdLocalPath `
      -VhdFormat $config.image.format `
      -VhdType $config.image.type `
      -VhdPartitionStyle $config.image.partition `
      -Edition $(if ($config.iso.wimindex) { $config.iso.wimindex } else { $config.image.edition }) -UnattendPath $unattendLocalPath `
      -RemoteDesktopEnable:$true `
      -DisableWindowsService $disableWindowsService `
      -DisableNotificationCenter:($config.image.os -eq 'Windows 10') `
      -Verbose;
  }


  $vhdMountPoint = (Join-Path -Path $workFolder -ChildPath ([System.Guid]::NewGuid().Guid.Substring(24)));
  New-Item -Path $vhdMountPoint -ItemType Directory -Force | Out-Null;
  try {
    Mount-WindowsImage -ImagePath $vhdLocalPath -Path $vhdMountPoint -Index 1
    Write-Output -InputObject ('mounted: {0} at mount point: {1}' -f $vhdLocalPath, $vhdMountPoint);
  } catch {
    Write-Output -InputObject ('failed to mount: {0} at mount point: {1}. {2}' -f $vhdLocalPath, $vhdMountPoint, $_.Exception.Message);
    Dismount-WindowsImage -Path $vhdMountPoint -Save -ErrorAction SilentlyContinue
    throw
  }

  New-Item -Path $packagesLocalPath -ItemType Directory -Force | Out-Null;
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
    Dismount-WindowsImage -Path $vhdMountPoint -Save | Out-Null
    Write-Output -InputObject ('dismount success for: {0} at mount point: {1}' -f $vhdLocalPath, $vhdMountPoint);

    # todo: set key in artifacts
    $vhdBucketKey = ('vhd/{0}/{1}' -f (Get-Date -UFormat '+%Y-%m-%d'), [System.IO.Path]::GetFileName($vhdLocalPath));
    Set-CloudBucketResource `
      -platform $config.image.target.platform `
      -bucket $config.image.target.bucket `
      -key $vhdBucketKey `
      -source $vhdLocalPath;
    if (Test-CloudBucketResource `
      -platform $config.image.target.platform `
      -bucket $config.image.target.bucket `
      -key $vhdBucketKey) {
      Write-Output -InputObject ('upload success for: {0} to: {1}/{2}/{3}' -f $vhdLocalPath, $config.image.target.platform, $config.image.target.bucket, $vhdBucketKey);
      $imageArtifactDescriptor = @{
        'build' = @{
          'date' = (Get-Date -UFormat '+%Y-%m-%d');
          'time' = (Get-Date -UFormat '+%Y-%m-%dT%H:%M:%S%Z');
          'revision' = $revision;
          'task' = @{
            'id' = $env:TASK_ID;
            'run' = $env:RUN_ID;
          }
        };
        'image' = @{
          'platform' = $config.image.target.platform;
          'bucket' = $config.image.target.bucket;
          'key' = $vhdBucketKey
        }
      };
      $imageArtifactDescriptorLocalPath = ('{0}{1}image-bucket-resource.json' -f $workFolder, ([IO.Path]::DirectorySeparatorChar));
      Out-File -FilePath $imageArtifactDescriptorLocalPath -Encoding 'utf8' -InputObject (ConvertTo-Json -InputObject $imageArtifactDescriptor);
      if (Test-Path -Path $imageArtifactDescriptorLocalPath -ErrorAction SilentlyContinue) {
        Write-Output -InputObject ('image artifact descriptor written to: {0}' -f $imageArtifactDescriptorLocalPath);
      }
    } else {
      Write-Output -InputObject ('upload failure for: {0} to: {1}/{2}/{3}' -f $vhdLocalPath, $config.image.target.platform, $config.image.target.bucket, $vhdBucketKey);
      exit 1;
    }
  } catch {
    Write-Output -InputObject ('failed to dismount: {0} at mount point: {1}. {2}' -f $vhdLocalPath, $vhdMountPoint, $_.Exception.Message);
    throw
  } finally {
    Remove-Item -Path $vhdMountPoint -Force
  }
}
