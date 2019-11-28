# job settings. change these for the task at hand.
$workFolder = ('{0}{1}azure-ci' -f 'D:', ([IO.Path]::DirectorySeparatorChar));
$driverFolder = ('{0}{1}driver' -f $workFolder, ([IO.Path]::DirectorySeparatorChar));
$isoSource = @{
  'platform' = 'amazon';
  'bucket' = 'windows-ami-builder';
  'key' = 'iso/en_windows_10_business_editions_version_1903_updated_sept_2019_x64_dvd_a10b235d.iso';
  'wimindex' = 5
};
$os = 'Windows 10';
$edition = 'Professional';
$language = 'en-US';
$architecture = 'x86-64';
$gpu = $false;
$registeredOwner = 'Mozilla RelOps';
$registeredOrganization = 'Mozilla Corporation';
$targetCloudPlatform = 'azure';

# computed settings. these are probably ok as they are.
$vhdPartitionStyle = 'MBR';
$vhdType = $(if ($targetCloudPlatform.StartsWith('az')) { 'Fixed' } else { 'Dynamic' });
$vhdFormat = 'VHD';
$vhdLocalPath = ('{0}{1}{2}-{3}-{4}-{5}{6}-{7}.{8}' -f $workFolder,
  ([IO.Path]::DirectorySeparatorChar),
  $os.ToLower().Replace(' ', ''),
  $edition.ToLower(),
  $language.ToLower(),
  $architecture, $(if ($gpu) { '-gpu' } else { '' }),
  $vhdType.ToLower(),
  $vhdFormat.ToLower());
$isoLocalPath = ('{0}{1}{2}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $isoSource.key);
$unattendLocalPath = ('{0}{1}unattend.xml' -f $workFolder, ([IO.Path]::DirectorySeparatorChar));
$administratorPassword = (New-Password);
# https://docs.microsoft.com/en-us/windows-server/get-started/kmsclientkeys
$productKey = (Invoke-WebRequest -Uri 'https://gist.githubusercontent.com/grenade/3f2fbc64e7210de136e7eb69aae63f81/raw/product-keys.json' -UseBasicParsing | ConvertFrom-Json)[$os][$edition];
$drivers = @(@(
  @{
    'name'    = 'xenbus';
    'infpath' = 'xenbus';
    'extract' = $true;
    'target' = @{
      'cloud'        = @('amazon', 'azure', 'google');
      'os'           = @('Windows 7', 'Windows 8.1', 'Windows 10', 'Windows Server 2012 R2', 'Windows Server 2016', 'Windows Server 2019', 'Windows Server');
      'architecture' = @('x86-64');
      'gpu'          = @($true, $false);
    };
    'source' = @{
      'platform'     = 'amazon';
      'bucket'       = 'windows-ami-builder';
      'key'          = 'driver/aws-pv/xenbus.zip';
    };
  },
  @{
    'name'    = 'xeniface';
    'infpath' = 'xeniface';
    'extract' = $true;
    'target' = @{
      'cloud'        = @('amazon', 'azure', 'google');
      'os'           = @('Windows 7', 'Windows 8.1', 'Windows 10', 'Windows Server 2012 R2', 'Windows Server 2016', 'Windows Server 2019', 'Windows Server');
      'architecture' = @('x86-64');
      'gpu'          = @($true, $false);
    };
    'source' = @{
      'platform'     = 'amazon';
      'bucket'       = 'windows-ami-builder';
      'key'          = 'driver/aws-pv/xeniface.zip';
    };
  },
  @{
    'name'    = 'xennet';
    'infpath' = 'xennet';
    'extract' = $true;
    'target' = @{
      'cloud'        = @('amazon', 'azure', 'google');
      'os'           = @('Windows 7', 'Windows 8.1', 'Windows 10', 'Windows Server 2012 R2', 'Windows Server 2016', 'Windows Server 2019', 'Windows Server');
      'architecture' = @('x86-64');
      'gpu'          = @($true, $false);
    };
    'source' = @{
      'platform'     = 'amazon';
      'bucket'       = 'windows-ami-builder';
      'key'          = 'driver/aws-pv/xennet.zip';
    };
  },
  @{
    'name'    = 'xenvbd';
    'infpath' = 'xenvbd';
    'extract' = $true;
    'target' = @{
      'cloud'        = @('amazon', 'azure', 'google');
      'os'           = @('Windows 7', 'Windows 8.1', 'Windows 10', 'Windows Server 2012 R2', 'Windows Server 2016', 'Windows Server 2019', 'Windows Server');
      'architecture' = @('x86-64');
      'gpu'          = @($true, $false);
    };
    'source' = @{
      'platform'     = 'amazon';
      'bucket'       = 'windows-ami-builder';
      'key'          = 'driver/aws-pv/xenvbd.zip';
    };
  },
  @{
    'name'    = 'xenvif';
    'infpath' = 'xenvif';
    'extract' = $true;
    'target' = @{
      'cloud'        = @('amazon', 'azure', 'google');
      'os'           = @('Windows 7', 'Windows 8.1', 'Windows 10', 'Windows Server 2012 R2', 'Windows Server 2016', 'Windows Server 2019', 'Windows Server');
      'architecture' = @('x86-64');
      'gpu'          = @($true, $false);
    };
    'source' = @{
      'platform'     = 'amazon';
      'bucket'       = 'windows-ami-builder';
      'key'          = 'driver/aws-pv/xenvif.zip';
    };
  },
  @{
    'name'    = 'AwsEnaNetworkDriver';
    'infpath' = 'AwsEnaNetworkDriver\bin.10.0';
    'extract' = $true;
    'target' = @{
      'cloud'        = @('amazon');
      'os'           = @('Windows 7', 'Windows 8.1', 'Windows 10', 'Windows Server 2012 R2', 'Windows Server 2016', 'Windows Server 2019', 'Windows Server');
      'architecture' = @('x86-64');
      'gpu'          = @($true, $false);
    };
    'source' = @{
      'platform'     = 'amazon';
      'bucket'       = 'windows-ami-builder';
      'key'          = 'driver/AwsEnaNetworkDriver.zip';
    };
  },
  @{
    'name'    = '391.81_grid_win10_server2016_64bit_international';
    'infpath' = '391.81_grid_win10_server2016_64bit_international';
    'extract' = $true;
    'target' = @{
      'cloud'        = @('amazon', 'google');
      'os'           = @('Windows 10', 'Windows Server 2016');
      'architecture' = @('x86-64');
      'gpu'          = @($true);
    };
    'source' = @{
      'platform'     = 'amazon';
      'bucket'       = 'windows-ami-builder';
      'key'          = 'driver/391.81_grid_win10_server2016_64bit_international.zip';
    };
  }
) | ? {
  $_.target.os.Contains($os) -and
  $_.target.architecture.Contains($architecture) -and
  $_.target.cloud.Contains($targetCloudPlatform) -and
  $_.target.gpu.Contains($gpu)
});
$disableWindowsService = @(@(
  @{
    'name'    = 'SecurityHealthService';
    'target' = @{
      'cloud'        = @('amazon', 'azure', 'google');
      'os'           = @('Windows 10');
      'architecture' = @('x86', 'x86-64');
    };
  },
  @{
    'name'    = 'Sense';
    'target' = @{
      'cloud'        = @('amazon', 'azure', 'google');
      'os'           = @('Windows 10');
      'architecture' = @('x86', 'x86-64');
    };
  },
  @{
    'name'    = 'WdBoot';
    'target' = @{
      'cloud'        = @('amazon', 'azure', 'google');
      'os'           = @('Windows 10');
      'architecture' = @('x86', 'x86-64');
    };
  },
  @{
    'name'    = 'WdFilter';
    'target' = @{
      'cloud'        = @('amazon', 'azure', 'google');
      'os'           = @('Windows 10');
      'architecture' = @('x86', 'x86-64');
    };
  },
  @{
    'name'    = 'WdNisDrv';
    'target' = @{
      'cloud'        = @('amazon', 'azure', 'google');
      'os'           = @('Windows 10');
      'architecture' = @('x86', 'x86-64');
    };
  },
  @{
    'name'    = 'WdNisSvc';
    'target' = @{
      'cloud'        = @('amazon', 'azure', 'google');
      'os'           = @('Windows 10');
      'architecture' = @('x86', 'x86-64');
    };
  },
  @{
    'name'    = 'WinDefend';
    'target' = @{
      'cloud'        = @('amazon', 'azure', 'google');
      'os'           = @('Windows 10');
      'architecture' = @('x86', 'x86-64');
    };
  },
  @{
    'name'    = 'wscsvc';
    'target' = @{
      'cloud'        = @('amazon', 'azure', 'google');
      'os'           = @('Windows 10');
      'architecture' = @('x86', 'x86-64');
    };
  }
) | ? {
  $_.target.os.Contains($os) -and
  $_.target.architecture.Contains($architecture) -and
  $_.target.cloud.Contains($targetCloudPlatform)
} | % { $_.name });

Update-Module posh-minions-managed -RequiredVersion 0.0.20

if (-not (Test-Path -Path $isoLocalPath -ErrorAction SilentlyContinue)) {
  Get-CloudBucketResource `
    -platform $isoSource.platform `
    -bucket $isoSource.bucket `
    -key $isoSource.key `
    -destination $isoLocalPath `
    -force;  
}
New-UnattendFile `
  -destinationPath $unattendLocalPath `
  -uiLanguage $language `
  -productKey $productKey `
  -registeredOwner $registeredOwner `
  -registeredOrganization $registeredOrganization `
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
  -VhdFormat $vhdFormat `
  -VhdType $vhdType `
  -VhdPartitionStyle $vhdPartitionStyle `
  -Edition $(if ($isoSource.wimindex) { $isoSource.wimindex } else { $edition }) -UnattendPath $unattendLocalPath `
  -Driver @($drivers | % { '{0}{1}{2}' -f $driverFolder, ([IO.Path]::DirectorySeparatorChar), $_.infpath }) `
  -RemoteDesktopEnable:$true `
  -DisableWindowsService $disableWindowsService `
  -DisableNotificationCenter:($os -eq 'Windows 10');