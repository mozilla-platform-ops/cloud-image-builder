param (
  [Parameter(Mandatory = $true)]
  [ValidateSet('amazon', 'azure', 'google')]
  [string] $platform,

  [Parameter(Mandatory = $true)]
  [ValidateSet('win10-64-occ', 'win10-64', 'win10-64-gpu', 'win7-32', 'win7-32-gpu', 'win2012', 'win2019')]
  [string] $imageKey,
  [string] $group,
  [switch] $enableSnapshotCopy = $false
)

function Invoke-BootstrapExecution {
  param (
    [int] $executionNumber,
    [int] $executionCount,
    [string] $instanceName,
    [string] $groupName,
    [object] $execution,
    [int] $attemptNumber = 1
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7} has been invoked' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName);
    $runCommandScriptContent = [String]::Join('; ', @(
      $execution.commands | % {
        # tokenised commands (eg: commands containing secrets), need to have each of their token values evaluated (eg: to perform a secret lookup)
        if ($_.format -and $_.tokens) {
          ($_.format -f @($_.tokens | % $($_)))
        } else {
          $_
        }
      }
    ));
    $runCommandScriptPath = ('{0}\{1}.ps1' -f $env:Temp, $execution.name);
    Set-Content -Path $runCommandScriptPath -Value $runCommandScriptContent;
    switch ($execution.shell) {
      'azure-powershell' {
        $runCommandResult = (Invoke-AzVMRunCommand `
          -ResourceGroupName $groupName `
          -VMName $instanceName `
          -CommandId 'RunPowerShellScript' `
          -ScriptPath $runCommandScriptPath);
        Remove-Item -Path $runCommandScriptPath;
        Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, has status: {7}' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName, $runCommandResult.Status.ToLower());
        if ($runCommandResult.Value[0].Message) {
          Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, has std out:\n{7}' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName, $runCommandResult.Value[0].Message);
        } else {
          Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, did not produce output on std out stream' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName);
        }
        if ($runCommandResult.Value[1].Message) {
          Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, has std err:\n{7}' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName, $runCommandResult.Value[1].Message);
        } else {
          Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, did not produce output on std err stream' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName);
        }
        if ($execution.test) {
          if ($execution.test.std) {
            if ($execution.test.std.out) {
              if ($execution.test.std.out.match) {
                if ($runCommandResult.Value[0].Message -match $execution.test.std.out.match) {
                  if ($execution.on.success) {
                    Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, has triggered success action: {7}' -f $($MyInvocation.MyCommand.Name), $beI, $beC, $execution.name, $execution.shell, $groupName, $instanceName, $execution.on.success);
                    switch ($execution.on.success) {
                      'reboot' {
                        Restart-AzVM -ResourceGroupName $groupName -Name $instanceName;
                      }
                      default {
                        Write-Output -InputObject ('{0} :: no implementation found for std out regex match success action: {1}' -f $($MyInvocation.MyCommand.Name), $execution.on.success);
                      }
                    }
                  }
                } else {
                  if ($execution.on.failure) {
                    Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, has triggered failure action: {7}' -f $($MyInvocation.MyCommand.Name), $beI, $beC, $execution.name, $execution.shell, $groupName, $instanceName, $execution.on.failure);
                    switch ($execution.on.failure) {
                      'reboot' {
                        Restart-AzVM -ResourceGroupName $groupName -Name $instanceName;
                      }
                      'retry' {
                        Invoke-BootstrapExecution -executionNumber $executionNumber -executionCount $executionCount -instanceName $instanceName -groupName $groupName -execution $execution -attemptNumber ($attemptNumber + 1)
                      }
                      'retry-task' {
                        try {
                          Remove-AzVm `
                            -ResourceGroupName $groupName `
                            -Name $instanceName `
                            -Force;
                          Write-Output -InputObject (('{0} :: instance: {1}, deletion appears successful' -f $($MyInvocation.MyCommand.Name), $instanceName));
                        } catch {
                          Write-Output -InputObject (('{0} :: instance: {1}, deletion threw exception. {2}' -f $($MyInvocation.MyCommand.Name), $instanceName, $_.Exception.Message));
                        }
                        exit 123;
                      }
                      'fail' {
                        try {
                          Remove-AzVm `
                            -ResourceGroupName $groupName `
                            -Name $instanceName `
                            -Force;
                          Write-Output -InputObject (('{0} :: instance: {1}, deletion appears successful' -f $($MyInvocation.MyCommand.Name), $instanceName));
                        } catch {
                          Write-Output -InputObject (('{0} :: instance: {1}, deletion threw exception. {2}' -f $($MyInvocation.MyCommand.Name), $instanceName, $_.Exception.Message));
                        }
                        exit 1;
                      }
                      default {
                        Write-Output -InputObject (('{0} :: no implementation found for std out regex match failure action: {1}' -f $($MyInvocation.MyCommand.Name), $execution.on.failure));
                      }
                    }
                  }
                }
              }
            }
            if ($execution.test.std.err) {
              Write-Output -InputObject (('{0} :: no implementation found for std err test action' -f $($MyInvocation.MyCommand.Name)));
            }
          }
        }
      }
    }
    Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7} has been completed' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName);
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}

function Invoke-BootstrapExecutions {
  param (
    [string] $instanceName,
    [string] $groupName,
    [object[]] $executions
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    if ($executions -and $executions.Length) {
      $executionNumber = 1;
      Write-Output -InputObject ('{0} :: detected {1} bootstrap command execution configurations for: {2}/{3}' -f $($MyInvocation.MyCommand.Name), $executions.Length, $groupName, $instanceName);
      foreach ($execution in $executions) {
        Invoke-BootstrapExecution -executionNumber $executionNumber -executionCount $executions.Length -instanceName $instanceName -groupName $groupName -execution $execution
        $executionNumber += 1;
      }
      $successfulBootstrapDetected = $true;
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}

function Remove-Resource {
  param (
    [string] $resourceId,
    [string] $resourceGroupName,
    [string[]] $resourceNames = @(
      ('vm-{0}' -f $resourceId),
      ('ni-{0}' -f $resourceId),
      ('ip-{0}' -f $resourceId),
      ('disk-{0}*' -f $resourceId)
    )
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    # instance instantiation failures leave behind a disk, public ip and network interface which need to be deleted.
    # the deletion will fail if the failed instance deletion is not complete.
    # retry for a while before giving up.
    do {
      foreach ($resourceName in $resourceNames) {
        $resourceType = @(
          'vm' = 'virtual machine';
          'ni' = 'network interface';
          'ip' = 'public ip address';
          'disk' = 'disk'
        )[$resourceName.Split('-')[0]];
        switch ($resourceType) {
          'virtual machine' {
            if (Get-AzVM -ResourceGroupName $resourceGroupName -Name $resourceName -ErrorAction SilentlyContinue) {
              try {
                Remove-AzVm -ResourceGroupName $resourceGroupName -Name $resourceName -Force;
                Write-Output -InputObject (('{0} :: {1}: {2}/{3}, removal appears successful' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $vmName));
              } catch {
                Write-Output -InputObject (('{0} :: {1}: {2}/{3}, removal threw exception. {4}' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $vmName, $_.Exception.Message));
              }
            } else {
              Write-Output -InputObject (('{0} :: {1}: {2}/{3} not found. removal skipped' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $vmName));
            }
          }
          'network interface' {
            if (Get-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name $resourceName -ErrorAction SilentlyContinue) {
              try {
                Remove-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name $resourceName -Force;
                Write-Output -InputObject (('{0} ::{1}: {2}/{3}, removal appears successful' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $vmName));
              } catch {
                Write-Output -InputObject (('{0} :: {1}: {2}/{3}, removal threw exception. {4}' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $vmName, $_.Exception.Message));
              }
            } else {
              Write-Output -InputObject (('{0} :: {1}: {2}/{3} not found. removal skipped' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $vmName));
            }
          }
          'public ip address' {
            if (Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name $resourceName -ErrorAction SilentlyContinue) {
              try {
                Remove-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name $resourceName -Force;
                Write-Output -InputObject (('{0} ::{1}: {2}/{3}, removal appears successful' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $vmName));
              } catch {
                Write-Output -InputObject (('{0} :: {1}: {2}/{3}, removal threw exception. {4}' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $vmName, $_.Exception.Message));
              }
            } else {
              Write-Output -InputObject (('{0} :: {1}: {2}/{3} not found. removal skipped' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $vmName));
            }
          }
          'disk' {
            if (Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $resourceName -ErrorAction SilentlyContinue) {
              try {
                Remove-AzDisk -ResourceGroupName $resourceGroupName -DiskName $resourceName -Force;
                Write-Output -InputObject (('{0} ::{1}: {2}/{3}, removal appears successful' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $vmName));
              } catch {
                Write-Output -InputObject (('{0} :: {1}: {2}/{3}, removal threw exception. {4}' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $vmName, $_.Exception.Message));
              }
            } else {
              Write-Output -InputObject (('{0} :: {1}: {2}/{3} not found. removal skipped' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $vmName));
            }
          }
        }
      }
    } while (
      (Get-AzVM -ResourceGroupName $resourceGroupName -Name ('vm-{0}' -f $resourceId) -ErrorAction SilentlyContinue) -or
      (Get-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name ('ni-{0}' -f $resourceId) -ErrorAction SilentlyContinue) -or
      (Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name ('ip-{0}' -f $resourceId) -ErrorAction SilentlyContinue) -or
      (Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName ('disk-{0}*' -f $resourceId) -ErrorAction SilentlyContinue)
    )
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}

# job settings. change these for the tasks at hand.
#$VerbosePreference = 'continue';
$workFolder = (Resolve-Path -Path ('{0}\..' -f $PSScriptRoot));

# constants and script config. these are probably ok as they are.
$revision = $(& git rev-parse HEAD);
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

$secret = (Invoke-WebRequest -Uri ('{0}/secrets/v1/secret/project/relops/image-builder/dev' -f $env:TASKCLUSTER_PROXY_URL) -UseBasicParsing | ConvertFrom-Json).secret;
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

    $azcopyExePath = ('{0}\azcopy.exe' -f $workFolder);
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
            $env:PATH = ('{0};{1}' -f $env:PATH, $workFolder);
            [Environment]::SetEnvironmentVariable('PATH', $env:PATH, 'User');
            Write-Output -InputObject ('user env PATH set to: {0}' -f $env:PATH);
          }
        } catch {
          Write-Output -InputObject ('failed to extract azcopy from: {0}' -f $azcopyZipPath);
        }
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
$imageArtifactDescriptorUri = ('{0}/api/index/v1/task/project.relops.cloud-image-builder.{1}.{2}.latest/artifacts/public/image-bucket-resource.json' -f $env:TASKCLUSTER_ROOT_URL, $platform, $imageKey);
try {
  $memoryStream = (New-Object System.IO.MemoryStream(, (New-Object System.Net.WebClient).DownloadData($imageArtifactDescriptorUri)));
  $streamReader = (New-Object System.IO.StreamReader(New-Object System.IO.Compression.GZipStream($memoryStream, [System.IO.Compression.CompressionMode] 'Decompress')));
  $imageArtifactDescriptor = ($streamReader.ReadToEnd() | ConvertFrom-Json);
  Write-Output -InputObject ('fetched disk image config for: {0}, from: {1}' -f $imageKey, $imageArtifactDescriptorUri);
} catch {
  Write-Output -InputObject ('error: failed to decompress or parse json from: {0}. {1}' -f $imageArtifactDescriptorUri, $_.Exception.Message);
  exit 1
}
$exportImageName = [System.IO.Path]::GetFileName($imageArtifactDescriptor.image.key);
$vhdLocalPath = ('{0}{1}{2}' -f $workFolder, ([IO.Path]::DirectorySeparatorChar), $exportImageName);

foreach ($target in @($config.target | ? { (($_.platform -eq $platform) -and $_.group -eq $group) })) {
  $bootstrapRevision = @($target.tag | ? { $_.name -eq 'deploymentId' })[0].value;
  if ($bootstrapRevision.Length -gt 7) {
    $bootstrapRevision = $bootstrapRevision.Substring(0, 7);
  }
  $targetImageName = ('{0}-{1}-{2}-{3}' -f $target.group.Replace('rg-', ''), $imageKey, $imageArtifactDescriptor.build.revision.Substring(0, 7), $bootstrapRevision);

  switch ($platform) {
    'azure' {
      $existingImage = (Get-AzImage `
        -ResourceGroupName $target.group `
        -ImageName $targetImageName `
        -ErrorAction SilentlyContinue);
      if ($existingImage) {
        Write-Output -InputObject ('skipped machine image creation for: {0}, in group: {1}, in cloud platform: {2}. machine image exists' -f $targetImageName, $target.group, $target.platform);
        exit;
      } elseif ($enableSnapshotCopy) {
        # check if the image snapshot exists in another regional resource-group
        $targetSnapshotName = ('{0}-{1}-{2}' -f $target.group.Replace('rg-', ''), $imageKey, $imageArtifactDescriptor.build.revision.Substring(0, 7));
        foreach ($source in @($config.target | ? { (($_.platform -eq $platform) -and $_.group -ne $group) })) {
          $sourceSnapshotName = ('{0}-{1}-{2}' -f $source.group.Replace('rg-', ''), $imageKey, $imageArtifactDescriptor.build.revision.Substring(0, 7));
          $sourceSnapshot = (Get-AzSnapshot `
            -ResourceGroupName $alternateTarget.group `
            -SnapshotName $sourceSnapshotName `
            -ErrorAction SilentlyContinue);
          if ($sourceSnapshot) {
            Write-Output -InputObject ('found snapshot: {0}, in group: {1}, in cloud platform: {2}. triggering machine copy from {1} to {3}...' -f $sourceSnapshotName, $source.group, $source.platform, $target.group);

            # get/create storage account in target region
            $storageAccountName = ('{0}cib' -f $target.group.Replace('rg-', '').Replace('-', ''));
            $targetAzStorageAccount = (Get-AzStorageAccount `
              -ResourceGroupName $target.group `
              -Name $storageAccountName);
            if ($targetAzStorageAccount) {
              Write-Output -InputObject ('detected storage account: {0}, for resource group: {1}' -f $storageAccountName, $target.group);
            } else {
              $targetAzStorageAccount = (New-AzStorageAccount `
                -ResourceGroupName $target.group `
                -AccountName $storageAccountName `
                -Location $target.region.Replace(' ', '').ToLower() `
                -SkuName 'Standard_LRS');
              Write-Output -InputObject ('created storage account: {0}, for resource group: {1}' -f $storageAccountName, $target.group);
            }
            if (-not ($targetAzStorageAccount)) {
              Write-Output -InputObject ('failed to get or create az storage account: {0}' -f $storageAccountName);
              exit 1;
            }

            # get/create storage container (bucket) in target region
            $storageContainerName = ('{0}cib' -f $target.group.Replace('rg-', '').Replace('-', ''));
            $targetAzStorageContainer = (Get-AzStorageContainer `
              -Name $storageContainerName `
              -Context $targetAzStorageAccount.Context);
            if ($targetAzStorageContainer) {
              Write-Output -InputObject ('detected storage container: {0}' -f $storageContainerName);
            } else {
              $targetAzStorageContainer = (New-AzStorageContainer `
                -Name $storageContainerName `
                -Context $targetAzStorageAccount.Context `
                -Permission 'Container');
              Write-Output -InputObject ('created storage container: {0}' -f $storageContainerName);
            }
            if (-not ($targetAzStorageContainer)) {
              Write-Output -InputObject ('failed to get or create az storage container: {0}' -f $storageContainerName);
              exit 1;
            }
             
            # copy snapshot to target container (bucket)
            $sourceAzSnapshotAccess = (Grant-AzSnapshotAccess `
              -ResourceGroupName $source.group `
              -SnapshotName $sourceSnapshotName `
              -DurationInSecond 3600 `
              -Access 'Read');
            Start-AzStorageBlobCopy `
              -AbsoluteUri $sourceAzSnapshotAccess.AccessSAS `
              -DestContainer $storageContainerName `
              -DestContext $targetAzStorageAccount.Context `
              -DestBlob $targetSnapshotName;
            # todo: wrap above cmdlet in try/catch and handle exceptions
            $targetAzStorageBlobCopyState = (Get-AzStorageBlobCopyState `
              -Container $storageContainerName `
              -Blob $targetSnapshotName `
              -Context $targetAzStorageAccount.Context `
              -WaitForComplete);
            $targetAzSnapshotConfig = (New-AzSnapshotConfig `
              -AccountType 'Standard_LRS' `
              -OsType 'Windows' `
              -Location $target.region.Replace(' ', '').ToLower() `
              -CreateOption 'Import' `
              -SourceUri ('{0}{1}/{2}' -f $targetAzStorageAccount.Context.BlobEndPoint, $storageContainerName, $targetSnapshotName) `
              -StorageAccountId $targetAzStorageAccount.Id);
            $targetAzSnapshot = (New-AzSnapshot `
              -ResourceGroupName $target.group `
              -SnapshotName $targetSnapshotName `
              -Snapshot $targetAzSnapshotConfig);
            Write-Output -InputObject ('provisioning of snapshot: {0}, has state: {1}' -f $targetSnapshotName, $targetAzSnapshot.ProvisioningState.ToLower());
            $targetAzImageConfig = (New-AzImageConfig `
              -Location $target.region.Replace(' ', '').ToLower());
            $targetAzImageConfig = (Set-AzImageOsDisk `
              -Image $targetAzImageConfig `
              -OsType 'Windows' `
              -OsState 'Generalized' `
              -SnapshotId $targetAzSnapshot.Id);
            $targetAzImage = (New-AzImage `
              -ResourceGroupName $target.group `
              -ImageName $targetImageName `
              -Image $targetAzImageConfig);
            if (-not $targetAzImage) {
              Write-Output -InputObject ('provisioning of image: {0}, failed' -f $targetImageName);
              exit 1;
            }
            Write-Output -InputObject ('provisioning of image: {0}, has state: {1}' -f $targetImageName, $targetAzImage.ProvisioningState.ToLower());
            exit;
          }
        }
      }
    }
  }
  if (-not (Test-Path -Path $vhdLocalPath -ErrorAction SilentlyContinue)) {
    Get-CloudBucketResource `
      -platform $imageArtifactDescriptor.image.platform `
      -bucket $imageArtifactDescriptor.image.bucket `
      -key $imageArtifactDescriptor.image.key `
      -destination $vhdLocalPath `
      -force;
    if (Test-Path -Path $vhdLocalPath -ErrorAction SilentlyContinue) {
      Write-Output -InputObject ('download success for: {0} from: {1}/{2}/{3}' -f $vhdLocalPath, $imageArtifactDescriptor.image.platform, $imageArtifactDescriptor.image.bucket, $imageArtifactDescriptor.image.key);
    } else {
      Write-Output -InputObject ('download failure for: {0} from: {1}/{2}/{3}' -f $vhdLocalPath, $imageArtifactDescriptor.image.platform, $imageArtifactDescriptor.image.bucket, $imageArtifactDescriptor.image.key);
      exit 1;
    }
  }

  switch ($platform) {
    'azure' {
      $sku = ($target.machine.format -f $target.machine.cpu);
      if (-not (Get-AzComputeResourceSku | where { (($_.Locations -icontains $target.region.Replace(' ', '').ToLower()) -and ($_.Name -eq $sku)) })) {
        Write-Output -InputObject ('skipped image export: {0}, to region: {1}, in cloud platform: {2}. {3} is not available' -f $exportImageName, $target.region, $target.platform, $sku);
        exit 1;
      } else {
        switch -regex ($sku) {
          '^Basic_A[0-9]+$' {
            $skuFamily = 'Basic A Family vCPUs';
            break;
          }
          '^Standard_A[0-7]$' {
            $skuFamily = 'Standard A0-A7 Family vCPUs';
            break;
          }
          '^Standard_A(8|9|10|11)$' {
            $skuFamily = 'Standard A8-A11 Family vCPUs';
            break;
          }
          '^(Basic|Standard)_(B|D|E|F|H|L|M)[0-9]+m?r?$' {
            $skuFamily = '{0} {1} Family vCPUs' -f $matches[1], $matches[2];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)[0-9]+m?r?_Promo$' {
            $skuFamily = '{0} {1} Promo Family vCPUs' -f $matches[1], $matches[2];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)[0-9]+[lmt]?s$' {
            $skuFamily = '{0} {1}S Family vCPUs' -f $matches[1], $matches[2];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M|P)([BC])[0-9]+r?s$' {
            $skuFamily = '{0} {1}{2}S Family vCPUs' -f $matches[1], $matches[2], $matches[3];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)[0-9]+(-(1|2|4|8|16|32|64))?m?s$' {
            $skuFamily = '{0} {1}S Family vCPUs' -f $matches[1], $matches[2];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)S[0-9]+$' {
            $skuFamily = '{0} {1}S Family vCPUs' -f $matches[1], $matches[2];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)1?[0-9]+m?_v([2-4])$' {
            $skuFamily = '{0} {1}v{2} Family vCPUs' -f $matches[1], $matches[2], $matches[3];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)?[0-9]+_v([2-4])_Promo$' {
            $skuFamily = '{0} {1}v{2} Promo Family vCPUs' -f $matches[1], $matches[2], $matches[3];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)1?[0-9]+_v([2-4])$' {
            $skuFamily = '{0} {1}v{2} Family vCPUs' -f $matches[1], $matches[2], $matches[3];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)1?[0-9]+m?s_v([2-4])$' {
            $skuFamily = '{0} {1}Sv{2} Family vCPUs' -f $matches[1], $matches[2], $matches[3];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)[0-9]+(-(1|2|4|8|16|32|64))?s_v([2-4])$' {
            $skuFamily = '{0} {1}Sv{2} Family vCPUs' -f $matches[1], $matches[2], $matches[5];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)S[0-9]+(-(1|2|4|8|16|32|64))?_v([2-4])$' {
            $skuFamily = '{0} {1}Sv{2} Family vCPUs' -f $matches[1], $matches[2], $matches[5];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)[0-9]+(-(1|2|4|8|16|32|64))?i_v([2-4])$' {
            $skuFamily = '{0} {1}Iv{2} Family vCPUs' -f $matches[1], $matches[2], $matches[5];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)[0-9]+(-(1|2|4|8|16|32|64))?is_v([2-4])$' {
            $skuFamily = '{0} {1}ISv{2} Family vCPUs' -f $matches[1], $matches[2], $matches[5];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)S[0-9]+_v([2-4])_Promo$' {
            $skuFamily = '{0} {1}Sv{2} Promo Family vCPUs' -f $matches[1], $matches[2], $matches[3];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)1?[0-9]+a_v([2-4])$' {
            $skuFamily = '{0} {1}Av{2} Family vCPUs' -f $matches[1], $matches[2], $matches[3];
            break;
          }
          '^(Basic|Standard)_(A|B|D|E|F|H|L|M)1?[0-9]+as_v([2-4])$' {
            $skuFamily = '{0} {1}ASv{2} Family vCPUs' -f $matches[1], $matches[2], $matches[3];
            break;
          }
          '^Standard_N([CV])[0-9]+r?$' {
            $skuFamily = 'Standard N{0} Family vCPUs' -f $matches[1];
            break;
          }
          '^Standard_N([CV])[0-9]+r?_Promo$' {
            $skuFamily = 'Standard N{0} Promo Family vCPUs' -f $matches[1];
            break;
          }
          '^Standard_N([DP])S[0-9]+$' {
            $skuFamily = 'Standard N{0}S Family vCPUs' -f $matches[1];
            break;
          }
          '^Standard_N([DP])[0-9]+r?s$' {
            $skuFamily = 'Standard N{0}S Family vCPUs' -f $matches[1];
            break;
          }
          '^Standard_N([CDV])[0-9]+r?s_v([2-4])$' {
            $skuFamily = 'Standard N{0}Sv{1} Family vCPUs' -f $matches[1], $matches[2];
            break;
          }
          default {
            $skuFamily = $false;
            break;
          }
        }
        if ($skuFamily) {
          Write-Output -InputObject ('mapped machine sku: {0}, to machine family: {1}' -f $sku, $skuFamily);
          $azVMUsage = @(Get-AzVMUsage -Location $target.region | ? { $_.Name.LocalizedValue -eq $skuFamily })[0];
        } else {
          Write-Output -InputObject ('failed to map machine sku: {0}, to machine family (no regex match)' -f $sku);
          $azVMUsage = $false;
          exit 1;
        }
        if (-not $azVMUsage) {
          Write-Output -InputObject ('skipped image export: {0}, to region: {1}, in cloud platform: {2}. failed to obtain vm usage for machine sku: {3}, family: {4}' -f $exportImageName, $target.region, $target.platform, $sku, $skuFamily);
          exit 1;
        } elseif ($azVMUsage.Limit -lt ($azVMUsage.CurrentValue + $target.machine.cpu)) {
          Write-Output -InputObject ('skipped image export: {0}, to region: {1}, in cloud platform: {2}. {3}/{4} cores quota in use for machine sku: {5}, family: {6}. no capacity for requested aditional {7} cores' -f $exportImageName, $target.region, $target.platform, $azVMUsage.CurrentValue, $azVMUsage.Limit, $sku, $skuFamily, $target.machine.cpu);
          exit 123;
        } else {
          Write-Output -InputObject ('quota usage check: usage limit: {0}, usage current value: {1}, core request: {2}, for machine sku: {3}, family: {4}' -f $azVMUsage.Limit, $azVMUsage.CurrentValue, $target.machine.cpu, $sku, $skuFamily);
          try {
            Write-Output -InputObject ('begin image export: {0}, to region: {1}, in cloud platform: {2}' -f $exportImageName, $target.region, $target.platform);
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
            $tags = @{
              'diskImageBuildDate' = $imageArtifactDescriptor.build.date;
              'diskImageBuildTime' = $imageArtifactDescriptor.build.time;
              'diskImageBuildRevision' = $imageArtifactDescriptor.build.revision;
              'machineImageBuildDate' = (Get-Date -UFormat '+%Y-%m-%d');
              'machineImageBuildTime' = (Get-Date -UFormat '+%Y-%m-%dT%H:%M:%S%Z');
              'machineImageBuildRevision' = $revision;
              'imageKey' = $imageKey;
              'resourceId' = $resourceId;
              'sourceIso' = ([System.IO.Path]::GetFileName($config.iso.source.key))
            };
            foreach ($tag in $target.tag) {
              $tags[$tag.name] = $tag.value;
            }

            # check (again) that another task hasn't already created the image
            $existingImage = (Get-AzImage `
              -ResourceGroupName $target.group `
              -ImageName $targetImageName `
              -ErrorAction SilentlyContinue);
            if ($existingImage) {
              Write-Output -InputObject ('skipped machine image creation for: {0}, in group: {1}, in cloud platform: {2}. machine image exists' -f $targetImageName, $target.group, $target.platform);
              exit;
            }

            $newCloudInstanceInstantiationAttempts = 0;
            do {
              # todo: get instance screenshots
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
                -targetInstanceDisks @($target.disk | % {@{ 'Variant' = $_.variant; 'SizeInGB' = $_.size; 'Os' = $_.os }}) `
                -targetInstanceTags $tags `
                -targetVirtualNetworkName $target.network.name `
                -targetVirtualNetworkAddressPrefix $target.network.prefix `
                -targetVirtualNetworkDnsServers $target.network.dns `
                -targetSubnetName $target.network.subnet.name `
                -targetSubnetAddressPrefix $target.network.subnet.prefix `
                -targetFirewallConfigurationName $target.network.flow.name `
                -targetFirewallRules $target.network.flow.rules;

              $newCloudInstanceInstantiationAttempts += 1;
              $azVm = (Get-AzVm -ResourceGroupName $target.group -Name $instanceName -ErrorAction SilentlyContinue);
              if ($azVm) {
                if (@('Succeeded', 'Failed') -contains $azVm.ProvisioningState) {
                  Write-Output -InputObject ('provisioning of vm: {0}, {1} on attempt: {2}' -f $instanceName, $azVm.ProvisioningState.ToLower(), $newCloudInstanceInstantiationAttempts);
                } else {
                  Write-Output -InputObject ('provisioning of vm: {0}, in progress with state: {1} on attempt: {2}' -f $instanceName, $azVm.ProvisioningState.ToLower(), $newCloudInstanceInstantiationAttempts);
                  Start-Sleep -Seconds 60
                }
              } else {
                # if we reach here, we most likely hit an azure quota exception which we may recover from when some quota becomes available.
                Remove-Resource -resourceId $resourceId -resourceGroupName $target.group
                try {
                  $taskDefinition = (Invoke-WebRequest -Uri ('{0}/api/queue/v1/task/{1}' -f $env:TASKCLUSTER_ROOT_URL, $env:TASK_ID) -UseBasicParsing | ConvertFrom-Json);
                  [DateTime] $taskStart = $taskDefinition.created;
                  [DateTime] $taskExpiry = $taskStart.AddSeconds($taskDefinition.payload.maxRunTime);
                  if ($taskExpiry -lt (Get-Date).AddMinutes(30)) {
                    Write-Output -InputObject ('provisioning of vm: {0}, failed on attempt: {1}. passing control to task retry logic...' -f $instanceName, $newCloudInstanceInstantiationAttempts);
                    exit 123;
                  }
                } catch {
                  Write-Output -InputObject ('failed to determine task expiry time using root url {0} and task id: {1}. {2}' -f $env:TASKCLUSTER_ROOT_URL, $env:TASK_ID, $_.Exception.Message);
                }
                $sleepInSeconds = (Get-Random -Minimum (3 * 60) -Maximum (10 * 60));
                Write-Output -InputObject ('provisioning of vm: {0}, failed on attempt: {1}. retrying in {2:1} minutes...' -f $instanceName, $newCloudInstanceInstantiationAttempts, ($sleepInSeconds / 60));
                Start-Sleep -Seconds $sleepInSeconds;
              }
            } until (@('Succeeded', 'Failed') -contains $azVm.ProvisioningState)
            Write-Output -InputObject ('end image export: {0} to: {1} cloud platform' -f $exportImageName, $target.platform);

            if ($azVm -and ($azVm.ProvisioningState -eq 'Succeeded')) {
              Write-Output -InputObject ('begin image import: {0} in region: {1}, cloud platform: {2}' -f $targetImageName, $target.region, $target.platform);
              if ($target.bootstrap.executions) {
                Invoke-BootstrapExecutions -instanceName $instanceName -groupName $target.group -executions $target.bootstrap.executions
                # todo implement success check
                $successfulBootstrapDetected = $true;
              } else {
                Write-Output -InputObject ('no bootstrap command execution configurations detected for: {0}/{1}' -f $target.group, $instanceName);

                # begin nasty hardcoded bootstrap sequence ##############################################################
                # todo: remove this code chunk when all yaml configs have been updated with bootstrap.executions sections
                $successfulBootstrapDetected = $false;

                $bootstrapOrg = @($target.tag | ? { $_.name -eq 'sourceOrganisation' })[0].value;
                $bootstrapRepo = @($target.tag | ? { $_.name -eq 'sourceRepository' })[0].value;
                $bootstrapRef = @($target.tag | ? { $_.name -eq 'sourceRevision' })[0].value;
                $bootstrapScript = @($target.tag | ? { $_.name -eq 'sourceScript' })[0].value;
                $bootstrapUrl = ('https://raw.githubusercontent.com/{0}/{1}/{2}/{3}' -f $bootstrapOrg, $bootstrapRepo, $bootstrapRef, $bootstrapScript);
                $workerDomain = $target.group.Replace(('rg-{0}-' -f $target.region.Replace(' ', '-').ToLower()), '');
                $workerVariant = ('{0}-{1}' -f $imageKey, $target.platform);
                $accessToken = ($secret.accessToken.production."$($target.platform)"."$workerDomain"."$workerVariant");
                if (($accessToken) -and ($accessToken.Length -eq 44)) {
                  Write-Output -InputObject ('access-token determined for client-id {0}/{1}/{2}' -f $target.platform, $workerDomain, $workerVariant)
                } else {
                  Write-Output -InputObject ('failed to determine access-token for client-id {0}/{1}/{2}' -f $target.platform, $workerDomain, $workerVariant);
                  Remove-Resource -resourceId $resourceId -resourceGroupName $target.group
                  exit 123;
                }
                $tooltoolToken = ($secret.tooltoolToken.production."$($target.platform)"."$workerDomain"."$workerVariant");
                if (($tooltoolToken) -and ($tooltoolToken.Length -eq 44)) {
                  Write-Output -InputObject ('tooltool-token determined for client-id {0}/{1}/{2}' -f $target.platform, $workerDomain, $workerVariant)
                }

                if ($config.image.architecture -eq 'x86-64') {
                  $bootstrapPath = ('{0}\bootstrap.ps1' -f $env:Temp)
                  (New-Object Net.WebClient).DownloadFile($bootstrapUrl, $bootstrapPath);
                  if (Test-Path -Path $bootstrapPath -ErrorAction SilentlyContinue) {
                    Write-Output -InputObject ('downloaded {0} from {1}' -f $bootstrapPath, $bootstrapUrl);
                  } else {
                    Write-Output -InputObject ('failed to download {0} from {1}' -f $bootstrapPath, $bootstrapUrl);
                    Remove-Resource -resourceId $resourceId -resourceGroupName $target.group
                    exit 1;
                  }      

                  Set-Content -Path ('{0}\sethostname.ps1' -f $env:Temp) -Value ('[Environment]::SetEnvironmentVariable("COMPUTERNAME", "{0}", "Machine"); $env:COMPUTERNAME = "{0}"; (Get-WmiObject Win32_ComputerSystem).Rename("{0}");' -f $instanceName);
                  $setHostnameCommandResult = (Invoke-AzVMRunCommand `
                    -ResourceGroupName $target.group `
                    -VMName $instanceName `
                    -CommandId 'RunPowerShellScript' `
                    -ScriptPath ('{0}\sethostname.ps1' -f $env:Temp));
                  Write-Output -InputObject ('set hostname {0} on instance: {1} in region: {2}, cloud platform: {3}' -f $(if ($setHostnameCommandResult -and $setHostnameCommandResult.Status) { $setHostnameCommandResult.Status.ToLower() } else { 'status unknown' }), $instanceName, $target.region, $target.platform);
                  Write-Output -InputObject ('set hostname std out: {0}' -f $setHostnameCommandResult.Value[0].Message);
                  Write-Output -InputObject ('set hostname std err: {0}' -f $setHostnameCommandResult.Value[1].Message);
                  Restart-AzVM -ResourceGroupName $target.group -Name $instanceName;

                  # set secrets in the instance registry
                  #Set-Content -Path ('{0}\setsecrets.ps1' -f $env:Temp) -Value ('New-Item -Path "HKLM:\SOFTWARE" -Name "Mozilla" -Force; New-Item -Path "HKLM:\SOFTWARE\Mozilla" -Name "GenericWorker" -Force; Set-ItemProperty -Path "HKLM:\SOFTWARE\Mozilla\GenericWorker" -Name "clientId" -Value "{0}/{1}/{2}" -Type "String"; Set-ItemProperty -Path "HKLM:\SOFTWARE\Mozilla\GenericWorker" -Name "accessToken" -Value "{3}" -Type "String"' -f $target.platform, $workerDomain, $workerVariant, $accessToken);
                  #$setSecretsCommandResult = (Invoke-AzVMRunCommand `
                  #  -ResourceGroupName $target.group `
                  #  -VMName $instanceName `
                  #  -CommandId 'RunPowerShellScript' `
                  #  -ScriptPath ('{0}\setsecrets.ps1' -f $env:Temp));
                  #Write-Output -InputObject ('set secrets {0} on instance: {1} in region: {2}, cloud platform: {3}' -f $(if ($setSecretsCommandResult -and $setSecretsCommandResult.Status) { $setSecretsCommandResult.Status.ToLower() } else { 'status unknown' }), $instanceName, $target.region, $target.platform);
                  #Write-Output -InputObject ('set secrets std out: {0}' -f $setSecretsCommandResult.Value[0].Message);
                  #Write-Output -InputObject ('set secrets std err: {0}' -f $setSecretsCommandResult.Value[1].Message);
                  #Remove-Item -Path ('{0}\setsecrets.ps1' -f $env:Temp);
                  Set-Content -Path ('{0}\setsecrets.ps1' -f $env:Temp) -Value ('New-Item -Path "HKLM:\SOFTWARE" -Name "Mozilla" -Force; New-Item -Path "HKLM:\SOFTWARE\Mozilla" -Name "tooltool" -Force; Set-ItemProperty -Path "HKLM:\SOFTWARE\Mozilla\tooltool" -Name "token" -Value "{0}" -Type "String"' -f $tooltoolToken);
                  $setSecretsCommandResult = (Invoke-AzVMRunCommand `
                    -ResourceGroupName $target.group `
                    -VMName $instanceName `
                    -CommandId 'RunPowerShellScript' `
                    -ScriptPath ('{0}\setsecrets.ps1' -f $env:Temp));
                  Write-Output -InputObject ('set secrets {0} on instance: {1} in region: {2}, cloud platform: {3}' -f $(if ($setSecretsCommandResult -and $setSecretsCommandResult.Status) { $setSecretsCommandResult.Status.ToLower() } else { 'status unknown' }), $instanceName, $target.region, $target.platform);
                  Write-Output -InputObject ('set secrets std out: {0}' -f $setSecretsCommandResult.Value[0].Message);
                  Write-Output -InputObject ('set secrets std err: {0}' -f $setSecretsCommandResult.Value[1].Message);

                  $bootstrapTriggerCommandResult = (Invoke-AzVMRunCommand `
                    -ResourceGroupName $target.group `
                    -VMName $instanceName `
                    -CommandId 'RunPowerShellScript' `
                    -ScriptPath $bootstrapPath); #-Parameter @{"arg1" = "var1";"arg2" = "var2"}
                  Write-Output -InputObject ('bootstrap trigger {0} on instance: {1} in region: {2}, cloud platform: {3}' -f $(if ($bootstrapTriggerCommandResult -and $bootstrapTriggerCommandResult.Status) { $bootstrapTriggerCommandResult.Status.ToLower() } else { 'status unknown' }), $instanceName, $target.region, $target.platform);
                  Write-Output -InputObject ('bootstrap trigger std out: {0}' -f $bootstrapTriggerCommandResult.Value[0].Message);
                  Write-Output -InputObject ('bootstrap trigger std err: {0}' -f $bootstrapTriggerCommandResult.Value[1].Message);

                  if ($bootstrapTriggerCommandResult.Status -eq 'Succeeded') {
                    Set-Content -Path ('{0}\verifyBootstrapCompletion.ps1' -f $env:Temp) -Value 'if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Mozilla\ronin_puppet" -Name "bootstrap_stage").bootstrap_stage -like "complete") { Write-Output -InputObject "completed" } else { Write-Output -InputObject "incomplete" }';
                    $verifyBootstrapCompletionCommandOutput = '';
                    $verifyBootstrapCompletionIteration = 0;
                    do {
                      $verifyBootstrapCompletionResult = (Invoke-AzVMRunCommand `
                        -ResourceGroupName $target.group `
                        -VMName $instanceName `
                        -CommandId 'RunPowerShellScript' `
                        -ScriptPath ('{0}\verifyBootstrapCompletion.ps1' -f $env:Temp) `
                        -ErrorAction SilentlyContinue);
                      Write-Output -InputObject ('verify bootstrap completion(iteration {0}) command {1} on instance: {2} in region: {3}, cloud platform: {4}' -f $verifyBootstrapCompletionIteration, $(if ($verifyBootstrapCompletionResult -and $verifyBootstrapCompletionResult.Status) { $verifyBootstrapCompletionResult.Status.ToLower() } else { 'status unknown' }), $instanceName, $target.region, $target.platform);
                      if ($verifyBootstrapCompletionResult.Value) {
                        $verifyBootstrapCompletionCommandOutput = $verifyBootstrapCompletionResult.Value[0].Message;
                        Write-Output -InputObject ('verify bootstrap completion(iteration {0}) std out: {1}' -f $verifyBootstrapCompletionIteration, $verifyBootstrapCompletionResult.Value[0].Message);
                        Write-Output -InputObject ('verify bootstrap completion(iteration {0}) std err: {1}' -f $verifyBootstrapCompletionIteration, $verifyBootstrapCompletionResult.Value[1].Message);
                      } else {
                        Write-Output -InputObject ('verify bootstrap completion(iteration {0}) command did not return a value' -f $verifyBootstrapCompletionIteration);
                      }
                      if ($verifyBootstrapCompletionCommandOutput -match 'completed') {
                        Write-Output -InputObject ('verify bootstrap completion(iteration {0}) detected bootstrap completion on: {1}' -f $verifyBootstrapCompletionIteration, $instanceName);
                        $successfulBootstrapDetected = $true;
                      } else {
                        Write-Output -InputObject ('verify bootstrap completion(iteration {0}) awaiting bootstrap completion on: {1}' -f $verifyBootstrapCompletionIteration, $instanceName);
                        Start-Sleep -Seconds 30;
                      }
                      $verifyBootstrapCompletionIteration += 1;
                    } until ($verifyBootstrapCompletionCommandOutput -match 'completed')
                    Remove-Item -Path ('{0}\verifyBootstrapCompletion.ps1' -f $env:Temp);
                  }
                } else {
                  # bootstrap over winrm for architectures that do not have an azure vm agent

                  # determine public ip of remote azure instance
                  try {
                    $azPublicIpAddress = (Get-AzPublicIpAddress `
                      -ResourceGroupName $target.group `
                      -Name ('ip-{0}' -f $resourceId) `
                      -ErrorAction SilentlyContinue);
                    if ($azPublicIpAddress -and $azPublicIpAddress.IpAddress) {
                      Write-Output -InputObject ('public ip address : "{0}", determined for: ip-{1}' -f $azPublicIpAddress.IpAddress, $resourceId);
                    } else {
                      Write-Output -InputObject ('error: failed to determine public ip address for: ip-{0}' -f $resourceId);
                      exit 1;
                    }
                  } catch {
                    Write-Output -InputObject ('error: failed to determine public ip address for: ip-{0}. {1}' -f $resourceId, $_.Exception.Message);
                    exit 1;
                  }

                  # determine administrator password of remote azure instance
                  $imageUnattendFileUri = ('{0}/api/index/v1/task/project.relops.cloud-image-builder.{1}.{2}.latest/artifacts/public/unattend.xml' -f $env:TASKCLUSTER_ROOT_URL, $platform, $imageKey);
                  try {
                    $memoryStream = (New-Object System.IO.MemoryStream(, (New-Object System.Net.WebClient).DownloadData($imageUnattendFileUri)));
                    $streamReader = (New-Object System.IO.StreamReader(New-Object System.IO.Compression.GZipStream($memoryStream, [System.IO.Compression.CompressionMode] 'Decompress')));
                    [xml]$imageUnattendFileXml = [xml]$streamReader.ReadToEnd();
                    Write-Output -InputObject ('fetched disk image unattend file for: {0}, from: {1}' -f $imageKey, $imageUnattendFileUri);
                  } catch {
                    Write-Output -InputObject ('error: failed to decompress or parse xml from: {0}. {1}' -f $imageUnattendFileUri, $_.Exception.Message);
                    exit 1;
                  }
                  $imagePassword = $imageUnattendFileXml.unattend.settings.component.UserAccounts.AdministratorPassword.Value.InnerText;
                  if ($imagePassword) {
                    Write-Output -InputObject ('image password with length: {0}, extracted from: {1}' -f $imagePassword.Length, $imageUnattendFileUri);
                  } else {
                    Write-Output -InputObject ('error: failed to extract image password from: {0}' -f $imageUnattendFileUri);
                    exit 1;
                  }
                  $credential = (New-Object `
                    -TypeName 'System.Management.Automation.PSCredential' `
                    -ArgumentList @('.\Administrator', (ConvertTo-SecureString $imagePassword -AsPlainText -Force)));

                  # modify security group of remote azure instance to allow winrm from public ip of local task instance
                  try {
                    $taskRunnerIpAddress = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/public-ipv4');
                    $azNetworkSecurityGroup = (Get-AzNetworkSecurityGroup -Name $target.network.flow.name);
                    $winrmAzNetworkSecurityRuleConfig = (Get-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $azNetworkSecurityGroup -Name 'allow-winrm' -ErrorAction SilentlyContinue);
                    if ($winrmAzNetworkSecurityRuleConfig) {
                      $setAzNetworkSecurityRuleConfigResult = (Set-AzNetworkSecurityRuleConfig `
                        -Name 'allow-winrm' `
                        -NetworkSecurityGroup $azNetworkSecurityGroup `
                        -SourceAddressPrefix @(@($taskRunnerIpAddress) + $winrmAzNetworkSecurityRuleConfig.SourceAddressPrefix));
                    } else {
                      $winrmRuleFromConfig = @($target.network.flow.rules | ? { $_.name -eq 'allow-winrm' })[0];
                      $setAzNetworkSecurityRuleConfigResult = (Add-AzNetworkSecurityRuleConfig `
                        -Name $winrmRuleFromConfig.name `
                        -Description $winrmRuleFromConfig.Description `
                        -Access $winrmRuleFromConfig.Access `
                        -Protocol $winrmRuleFromConfig.Protocol `
                        -Direction $winrmRuleFromConfig.Direction `
                        -Priority $winrmRuleFromConfig.Priority `
                        -SourceAddressPrefix @(@($taskRunnerIpAddress) + $winrmRuleFromConfig.SourceAddressPrefix) `
                        -SourcePortRange $winrmRuleFromConfig.SourcePortRange `
                        -DestinationAddressPrefix $winrmRuleFromConfig.DestinationAddressPrefix `
                        -DestinationPortRange $winrmRuleFromConfig.DestinationPortRange);
                    }
                    if ($setAzNetworkSecurityRuleConfigResult.ProvisioningState -eq 'Succeeded') {
                      $updatedIps = @($setAzNetworkSecurityRuleConfigResult.SecurityRules | ? { $_.Name -eq 'allow-winrm' })[0].SourceAddressPrefix;
                      Write-Output -InputObject ('winrm firewall configuration at: {0}/allow-winrm, modified to allow inbound from: {1}' -f $target.network.flow.name, [String]::Join(', ', $updatedIps));
                    } else {
                      Write-Output -InputObject ('error: failed to modify winrm firewall configuration. provisioning state: {0}' -f $setAzNetworkSecurityRuleConfigResult.ProvisioningState);
                      exit 1;
                    }
                  } catch {
                    Write-Output -InputObject ('error: failed to modify winrm firewall configuration. {0}' -f $_.Exception.Message);
                    exit 1;
                  }

                  # enable remoting and add remote azure instance to trusted host list
                  try {
                    #Enable-PSRemoting -SkipNetworkProfileCheck -Force
                    #Write-Output -InputObject 'powershell remoting enabled for session';
                    $trustedHostsPreBootstrap = (Get-Item -Path 'WSMan:\localhost\Client\TrustedHosts').Value;
                    Write-Output -InputObject ('local wsman trusted hosts list detected as: "{0}"' -f $trustedHostsPreBootstrap);
                    $trustedHostsForBootstrap = $(if (($trustedHostsPreBootstrap) -and ($trustedHostsPreBootstrap.Length -gt 0)) { ('{0},{1}' -f $trustedHostsPreBootstrap, $azPublicIpAddress.IpAddress) } else { $azPublicIpAddress.IpAddress });
                    #Set-Item -Path 'WSMan:\localhost\Client\TrustedHosts' -Value $trustedHostsForBootstrap -Force;
                    & winrm @('set', 'winrm/config/client', ('@{{TrustedHosts="{0}"}}' -f $trustedHostsForBootstrap));
                    Write-Output -InputObject ('local wsman trusted hosts list updated to: "{0}"' -f (Get-Item -Path 'WSMan:\localhost\Client\TrustedHosts').Value);
                  } catch {
                    Write-Output -InputObject ('error: failed to modify winrm firewall configuration. {0}' -f $_.Exception.Message);
                    exit 1;
                  }

                  # run remote bootstrap scripts over winrm
                  try {
                    Invoke-Command -ComputerName $azPublicIpAddress.IpAddress -Credential $credential -ScriptBlock {

                      # todo:
                      # - set secrets in the instance registry
                      # - rename host
                      # - run bootstrap
                      # - halt system

                      Get-UICulture
                    }
                  } catch {
                    Write-Output -InputObject ('error: failed to execute bootstrap commands over winrm. {0}' -f $_.Exception.Message);
                    exit 1;
                  }

                  # modify azure security group to remove public ip of task instance from winrm exceptions
                  $allowedIps = @($target.network.flow.rules | ? { $_.name -eq 'allow-winrm' })[0].sourceAddressPrefix
                  $setAzNetworkSecurityRuleConfigResult = (Set-AzNetworkSecurityRuleConfig `
                    -Name 'allow-winrm' `
                    -NetworkSecurityGroup $azNetworkSecurityGroup `
                    -SourceAddressPrefix $allowedIps);
                  if ($setAzNetworkSecurityRuleConfigResult.ProvisioningState -eq 'Succeeded') {
                    $updatedIps = @($setAzNetworkSecurityRuleConfigResult.SecurityRules | ? { $_.Name -eq 'allow-winrm' })[0].SourceAddressPrefix;
                    Write-Output -InputObject ('winrm firewall configuration at: {0}/allow-winrm, reverted to allow inbound from: {1}' -f $target.network.flow.name, [String]::Join(', ', $updatedIps));
                  } else {
                    Write-Output -InputObject ('error: failed to revert winrm firewall configuration. provisioning state: {0}' -f $setAzNetworkSecurityRuleConfigResult.ProvisioningState);
                  }

                  #Set-Item -Path 'WSMan:\localhost\Client\TrustedHosts' -Value $(if (($trustedHostsPreBootstrap) -and ($trustedHostsPreBootstrap.Length -gt 0)) { $trustedHostsPreBootstrap } else { '' }) -Force;
                  & winrm @('set', 'winrm/config/client', ('@{{TrustedHosts="{0}"}}' -f $trustedHostsPreBootstrap))
                  Write-Output -InputObject ('local wsman trusted hosts list reverted to: "{0}"' -f (Get-Item -Path 'WSMan:\localhost\Client\TrustedHosts').Value);
                }
                # end nasty hardcoded bootstrap sequence ################################################################

              }

              # check (again) that another task hasn't already created the image
              $existingImage = (Get-AzImage `
                -ResourceGroupName $target.group `
                -ImageName $targetImageName `
                -ErrorAction SilentlyContinue);
              if ($existingImage) {
                Write-Output -InputObject ('skipped machine image creation for: {0}, in group: {1}, in cloud platform: {2}. machine image exists' -f $targetImageName, $target.group, $target.platform);
                exit;
              }

              if ($successfulBootstrapDetected -or ($config.image.architecture -ne 'x86-64')) {
                New-CloudImageFromInstance `
                  -platform $target.platform `
                  -resourceGroupName $target.group `
                  -region $target.region `
                  -instanceName $instanceName `
                  -imageName $targetImageName;
                  #-imageTags $tags; # todo: tag image when azure ps isn't broken
                try {
                  $azImage = (Get-AzImage `
                    -ResourceGroupName $target.group `
                    -ImageName $targetImageName `
                    -ErrorAction SilentlyContinue);
                  if ($azImage) {
                    Write-Output -InputObject ('image: {0}, creation appears successful in region: {1}, cloud platform: {2}' -f $targetImageName, $target.region, $target.platform);
                  } else {
                    Write-Output -InputObject ('image: {0}, creation appears unsuccessful in region: {1}, cloud platform: {2}' -f $targetImageName, $target.region, $target.platform);
                  }
                } catch {
                  Write-Output -InputObject ('image: {0}, fetch threw exception in region: {1}, cloud platform: {2}. {3}' -f $targetImageName, $target.region, $target.platform, $_.Exception.Message);
                }
                try {
                  $azVm = (Get-AzVm `
                    -ResourceGroupName $target.group `
                    -Name $instanceName `
                    -Status `
                    -ErrorAction SilentlyContinue);
                  if (($azVm) -and (@($azVm.Statuses | ? { ($_.Code -eq 'OSState/generalized') -or ($_.Code -eq 'PowerState/deallocated') }).Length -eq 2)) {
                    # create a snapshot
                    # todo: move this functionality to posh-minions-managed
                    $azVm = (Get-AzVm `
                      -ResourceGroupName $target.group `
                      -Name $instanceName `
                      -ErrorAction SilentlyContinue);
                    if ($azVm -and $azVm.StorageProfile.OsDisk.Name) {
                      $azDisk = (Get-AzDisk `
                        -ResourceGroupName $target.group `
                        -DiskName $azVm.StorageProfile.OsDisk.Name);
                      if ($azDisk -and $azDisk[0].Id) {
                        $azSnapshotConfig = (New-AzSnapshotConfig `
                          -SourceUri $azDisk[0].Id `
                          -CreateOption 'Copy' `
                          -Location $target.region.Replace(' ', '').ToLower());
                        $azSnapshot = (New-AzSnapshot `
                          -ResourceGroupName $target.group `
                          -Snapshot $azSnapshotConfig `
                          -SnapshotName $targetImageName);
                      } else {
                        Write-Output -InputObject ('provisioning of snapshot: {0}, from instance: {1}, skipped due to undetermined osdisk id' -f $targetImageName, $instanceName);
                      }
                    } else {
                      Write-Output -InputObject ('provisioning of snapshot: {0}, from instance: {1}, skipped due to undetermined osdisk name' -f $targetImageName, $instanceName);
                    }
                    Write-Output -InputObject ('provisioning of snapshot: {0}, from instance: {1}, has state: {2}' -f $targetImageName, $instanceName, $azSnapshot.ProvisioningState.ToLower());
                  } else {
                    Write-Output -InputObject ('provisioning of snapshot: {0}, from instance: {1}, skipped due to undetermined vm state' -f $targetImageName, $instanceName);
                  }
                } catch {
                  Write-Output -InputObject ('provisioning of snapshot: {0}, from instance: {1}, threw exception. {2}' -f $targetImageName, $instanceName, $_.Exception.Message);
                } finally {
                  Remove-Resource -resourceId $resourceId -resourceGroupName $target.group
                }
              }
              Write-Output -InputObject ('end image import: {0} in region: {1}, cloud platform: {2}' -f $targetImageName, $target.region, $target.platform);
            } else {
              Write-Output -InputObject ('skipped image import: {0} in region: {1}, cloud platform: {2}' -f $targetImageName, $target.region, $target.platform);
              exit 1;
            }
          } catch {
            Write-Output -InputObject ('error: failure in image export: {0}, to region: {1}, in cloud platform: {2}. {3}' -f $exportImageName, $target.region, $target.platform, $_.Exception.Message);
            throw;
            exit 1;
          }
        }
      }
    }
  }
}
