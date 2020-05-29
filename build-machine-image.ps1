param (
  [Parameter(Mandatory = $true)]
  [ValidateSet('amazon', 'azure', 'google')]
  [string] $platform,

  [Parameter(Mandatory = $true)]
  [ValidateSet('win10-64-occ', 'win10-64', 'win10-64-gpu', 'win7-32', 'win7-32-gpu', 'win2012', 'win2019')]
  [string] $imageKey,

  [string] $group,
  [switch] $enableSnapshotCopy = $false,
  [switch] $overwrite = $false,

  [switch] $disableCleanup = $false
)

function Invoke-OptionalSleep {
  param (
    [string] $command,
    [string] $separator = ' ',
    [string] $action = $(
      if (($command.Split($separator).Length -gt 1) -and ($command.Split($separator)[1] -in @('in', 'after'))) {
        $command.Split($separator)[1]
      } else {
        $null
      }
    ),
    [int] $duration = $(
      if (($command.Split($separator).Length -gt 2) -and ($command.Split($separator)[2] -match "^\d+$")) {
        [int]$command.Split($separator)[2]
      } else {
        0
      }
    ),
    [string] $unit = $(
      if (($command.Split($separator).Length -gt 3) -and ($command.Split($separator)[3] -in @('millisecond', 'milliseconds', 'ms', 'second', 'seconds', 's', 'minute', 'minutes', 'm'))) {
        $command.Split($separator)[1]
      } else {
        'seconds'
      }
    )
  )
  begin {
    if ($action -and ($duration -gt 0)) {
      Write-Output -InputObject ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
    }
  }
  process {
    if ($action -and ($duration -gt 0)) {
      Write-Output -InputObject ('{0} :: sleeping for {1} {2}' -f $($MyInvocation.MyCommand.Name), $duration, $unit);
      switch -regex ($unit) {
        '^(millisecond|milliseconds|ms)$' {
          Start-Sleep -Milliseconds $duration;
        }
        '^(second|seconds|s)$' {
          Start-Sleep -Seconds $duration;
        }
        '^(minute|minutes|m)$' {
          Start-Sleep -Seconds ($duration * 60);
        }
      }
    }
  }
  end {
    if ($action -and ($duration -gt 0)) {
      Write-Output -InputObject ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
    }
  }
}

function Invoke-BootstrapExecution {
  param (
    [int] $executionNumber,
    [int] $executionCount,
    [string] $instanceName,
    [string] $groupName,
    [object] $execution,
    [object] $flow,
    [int] $attemptNumber = 1,
    [switch] $disableCleanup = $false
  )
  begin {
    Write-Output -InputObject ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
  process {
    Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7} has been invoked' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName);
    $tokenisedCommandEvaluationErrors = @();
    $runCommandScriptContent = [String]::Join('; ', @(
      $execution.commands | % {
        # tokenised commands (usually commands containing secrets), need to have each of their token values evaluated (eg: to perform a secret lookup)
        if ($_.format -and $_.tokens) {
          $tokenisedCommand = $_;
          try {
            ($tokenisedCommand.format -f @($tokenisedCommand.tokens | % { (Invoke-Expression -Command $_) } ))
          } catch {
            $tokenisedCommandEvaluationErrors += @{
              'format' = $tokenisedCommand.format;
              'tokens' = $tokenisedCommand.tokens;
              'exception' = $_.Exception
            };
          }
        } else {
          $_
        }
      }
    ));
    if ($tokenisedCommandEvaluationErrors.Length) {
      foreach ($tokenisedCommandEvaluationError in $tokenisedCommandEvaluationErrors) {
        Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, threw exception evaluating tokenised command (format: "{8}", tokens: "{9}")' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName, $tokenisedCommandEvaluationError.format, [String]::Join(', ', $tokenisedCommandEvaluationError.tokens));
        Write-Output -InputObject ($tokenisedCommandEvaluationError.exception.Message);
      }
      if (-not $disableCleanup) {
        Remove-Resource -resourceId $instanceName.Replace('vm-', '') -resourceGroupName $groupName;
      }
      exit 1;
    }
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
        Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, has status: {8}' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName, $(if (($runCommandResult) -and ($runCommandResult.Status)) { $runCommandResult.Status.ToLower() } else { '-' }));
        if ($runCommandResult.Value[0].Message) {
          Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, has std out:' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName);
          Write-Output -InputObject $runCommandResult.Value[0].Message;
        } else {
          Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, did not produce output on std out stream' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName);
        }
        if ($runCommandResult.Value[1].Message) {
          Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, has std err:' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName);
          Write-Output -InputObject $runCommandResult.Value[1].Message;
        } else {
          Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, did not produce output on std err stream' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName);
        }
        if ($execution.test) {
          if ($execution.test.std) {
            if ($execution.test.std.out) {
              if ($execution.test.std.out.match) {
                if ($runCommandResult.Value[0].Message -match $execution.test.std.out.match) {
                  Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, matched: "{8}" in std out' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName, $execution.test.std.out.match);
                  if ($execution.on.success) {
                    Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, has triggered success action: {8}' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName, $execution.on.success);
                    switch ($execution.on.success.Split(' ')[0]) {
                      'reboot' {
                        Invoke-OptionalSleep -command $execution.on.success;
                        Restart-AzVM -ResourceGroupName $groupName -Name $instanceName;
                      }
                      default {
                        Write-Output -InputObject ('{0} :: no implementation found for std out regex match success action: {1}' -f $($MyInvocation.MyCommand.Name), $execution.on.success);
                      }
                    }
                  }
                } else {
                  Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, did not match: "{8}" in std out' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName, $execution.test.std.out.match);
                  if ($execution.on.failure) {
                    Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7}, has triggered failure action: {8}' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName, $execution.on.failure);
                    switch ($execution.on.failure.Split(' ')[0]) {
                      'reboot' {
                        Invoke-OptionalSleep -command $execution.on.failure;
                        Restart-AzVM -ResourceGroupName $groupName -Name $instanceName;
                      }
                      'retry' {
                        Invoke-OptionalSleep -command $execution.on.failure;
                        Invoke-BootstrapExecution -executionNumber $executionNumber -executionCount $executionCount -instanceName $instanceName -groupName $groupName -execution $execution -attemptNumber ($attemptNumber + 1) -flow $flow -disableCleanup:$disableCleanup;
                      }
                      'retry-task' {
                        Invoke-OptionalSleep -command $execution.on.failure;
                        Remove-Resource -resourceId $instanceName.Replace('vm-', '') -resourceGroupName $groupName;
                        exit 123;
                      }
                      'fail' {
                        Invoke-OptionalSleep -command $execution.on.failure;
                        if (-not $disableCleanup) {
                          Remove-Resource -resourceId $instanceName.Replace('vm-', '') -resourceGroupName $groupName;
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
      # bootstrap over winrm for architectures that do not have an azure vm agent
      'winrm-powershell' {
        $publicIpAddress = (Get-PublicIpAddress -platform $platform -group $groupName -resourceId $resourceId);
        if (-not ($publicIpAddress)) {
          Write-Output -InputObject ('{0} :: failed to determine public ip address for resource: {1}, in group: {2}, on platform: {3}' -f $($MyInvocation.MyCommand.Name), $resourceId, $groupName, $platform);
          exit 1;
        } else {
          Write-Output -InputObject ('{0} :: public ip address: {1}, found for resource: {2}, in group: {3}, on platform: {4}' -f $($MyInvocation.MyCommand.Name), $publicIpAddress, $resourceId, $groupName, $platform);
        }
        $adminPassword = (Get-AdminPassword -platform $platform -imageKey $imageKey);
        if (-not ($adminPassword)) {
          Write-Output -InputObject ('{0} :: failed to determine admin password for image: {1}, on platform: {2}, using: {3}/api/index/v1/task/project.relops.cloud-image-builder.{2}.{1}.latest/artifacts/public/unattend.xml' -f $($MyInvocation.MyCommand.Name), $imageKey, $platform, $env:TASKCLUSTER_ROOT_URL);
          exit 1;
        } else {
          Write-Output -InputObject ('{0} :: admin password for image: {1}, on platform: {2}, found at: {3}/api/index/v1/task/project.relops.cloud-image-builder.{2}.{1}.latest/artifacts/public/unattend.xml' -f $($MyInvocation.MyCommand.Name), $imageKey, $platform, $env:TASKCLUSTER_ROOT_URL);
        }
        $credential = (New-Object `
          -TypeName 'System.Management.Automation.PSCredential' `
          -ArgumentList @('.\Administrator', (ConvertTo-SecureString $adminPassword -AsPlainText -Force)));

        # modify security group of remote azure instance to allow winrm from public ip of local task instance
        try {
          $taskRunnerIpAddress = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/public-ipv4');
          $azNetworkSecurityGroup = (Get-AzNetworkSecurityGroup -Name $flow.name);
          $winrmAzNetworkSecurityRuleConfig = (Get-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $azNetworkSecurityGroup -Name 'allow-winrm' -ErrorAction SilentlyContinue);
          if ($winrmAzNetworkSecurityRuleConfig) {
            $setAzNetworkSecurityRuleConfigResult = (Set-AzNetworkSecurityRuleConfig `
              -Name 'allow-winrm' `
              -NetworkSecurityGroup $azNetworkSecurityGroup `
              -SourceAddressPrefix @(@($taskRunnerIpAddress) + $winrmAzNetworkSecurityRuleConfig.SourceAddressPrefix));
          } else {
            $winrmRuleFromConfig = @($flow.rules | ? { $_.name -eq 'allow-winrm' })[0];
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
            Write-Output -InputObject ('winrm firewall configuration at: {0}/allow-winrm, modified to allow inbound from: {1}' -f $flow.name, [String]::Join(', ', $updatedIps));
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

          & winrm @('set', 'winrm/config/client', '@{AllowUnencrypted="true"}');
          Write-Output -InputObject 'winrm-client allow-unencrypted set to: "true"';

          $trustedHostsPreBootstrap = (Get-Item -Path 'WSMan:\localhost\Client\TrustedHosts').Value;
          Write-Output -InputObject ('winrm-client trusted-hosts detected as: "{0}"' -f $trustedHostsPreBootstrap);
          $trustedHostsForBootstrap = $(if (($trustedHostsPreBootstrap) -and ($trustedHostsPreBootstrap.Length -gt 0)) { ('{0},{1}' -f $trustedHostsPreBootstrap, $publicIpAddress) } else { $publicIpAddress });
          #Set-Item -Path 'WSMan:\localhost\Client\TrustedHosts' -Value $trustedHostsForBootstrap -Force;
          & winrm @('set', 'winrm/config/client', ('@{{TrustedHosts="{0}"}}' -f $trustedHostsForBootstrap));
          Write-Output -InputObject ('winrm-client trusted-hosts set to: "{0}"' -f (Get-Item -Path 'WSMan:\localhost\Client\TrustedHosts').Value);
        } catch {
          Write-Output -InputObject ('error: failed to modify winrm firewall configuration. {0}' -f $_.Exception.Message);
          exit 1;
        }
        $invocationResponse = $null;
        $invocationAttempt = 0;
        do {
          $invocationAttempt += 1;
          # run remote bootstrap scripts over winrm
          try {
            $invocationResponse = (Invoke-Command `
              -ComputerName $publicIpAddress `
              -Credential $credential `
              -ScriptBlock { $runCommandScriptContent });
          } catch {
            Write-Output -InputObject ('error: failed to execute bootstrap commands over winrm on attempt {0}. {1}' -f $invocationAttempt, $_.Exception.Message);
            exit 1;
          } finally {
            if ($invocationResponse) {
              Write-Output -InputObject $invocationResponse;
              if ($invocationResponse -match 'WinRMOperationTimeout') {
                Write-Output -InputObject 'awaiting manual intervention to correct the winrm connection issue';
                Start-Sleep -Seconds 120
              }
            } else {
              Write-Output -InputObject ('error: no response received during execution of bootstrap commands over winrm on attempt {0}' -f $invocationAttempt);
            }
          }
        } while (
          # repeat the winrm invocation until it works or the task exceeds its timeout, allowing for manual
          # intervention on the host instance to enable the winrm connection or connection issue debugging.
          ($invocationResponse -eq $null) -or
          ($invocationResponse -match 'WinRMOperationTimeout')
        )
        # modify azure security group to remove public ip of task instance from winrm exceptions
        $allowedIps = @($flow.rules | ? { $_.name -eq 'allow-winrm' })[0].sourceAddressPrefix
        $setAzNetworkSecurityRuleConfigResult = (Set-AzNetworkSecurityRuleConfig `
          -Name 'allow-winrm' `
          -NetworkSecurityGroup $azNetworkSecurityGroup `
          -SourceAddressPrefix $allowedIps);
        if ($setAzNetworkSecurityRuleConfigResult.ProvisioningState -eq 'Succeeded') {
          $updatedIps = @($setAzNetworkSecurityRuleConfigResult.SecurityRules | ? { $_.Name -eq 'allow-winrm' })[0].SourceAddressPrefix;
          Write-Output -InputObject ('winrm firewall configuration at: {0}/allow-winrm, reverted to allow inbound from: {1}' -f $flow.name, [String]::Join(', ', $updatedIps));
        } else {
          Write-Output -InputObject ('error: failed to revert winrm firewall configuration. provisioning state: {0}' -f $setAzNetworkSecurityRuleConfigResult.ProvisioningState);
        }

        #Set-Item -Path 'WSMan:\localhost\Client\TrustedHosts' -Value $(if (($trustedHostsPreBootstrap) -and ($trustedHostsPreBootstrap.Length -gt 0)) { $trustedHostsPreBootstrap } else { '' }) -Force;
        & winrm @('set', 'winrm/config/client', ('@{{TrustedHosts="{0}"}}' -f $trustedHostsPreBootstrap));
        Write-Output -InputObject ('winrm-client trusted-hosts reverted to: "{0}"' -f (Get-Item -Path 'WSMan:\localhost\Client\TrustedHosts').Value);
        & winrm @('set', 'winrm/config/client', '@{AllowUnencrypted="false"}');
        Write-Output -InputObject 'winrm-client allow-unencrypted reverted to: "false"';
      }
    }
    Write-Output -InputObject ('{0} :: bootstrap execution {1}/{2}, attempt {3}; {4}, using shell: {5}, on: {6}/{7} has been completed' -f $($MyInvocation.MyCommand.Name), $executionNumber, $executionCount, $attemptNumber, $execution.name, $execution.shell, $groupName, $instanceName);
  }
  end {
    Write-Output -InputObject ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
}

function Invoke-BootstrapExecutions {
  param (
    [string] $instanceName,
    [string] $groupName,
    [object[]] $executions,
    [object] $flow,
    [switch] $disableCleanup = $false
  )
  begin {
    Write-Output -InputObject ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
  process {
    if ($executions -and $executions.Length) {
      $executionNumber = 1;
      Write-Output -InputObject ('{0} :: detected {1} bootstrap command execution configurations for: {2}/{3}' -f $($MyInvocation.MyCommand.Name), $executions.Length, $groupName, $instanceName);
      foreach ($execution in $executions) {
        Invoke-BootstrapExecution -executionNumber $executionNumber -executionCount $executions.Length -instanceName $instanceName -groupName $groupName -execution $execution -flow $flow -disableCleanup:$disableCleanup;
        $executionNumber += 1;
      }
      $successfulBootstrapDetected = $true;
    }
  }
  end {
    Write-Output -InputObject ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
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
    Write-Output -InputObject ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
  process {
    # instance instantiation failures leave behind a disk, public ip and network interface which need to be deleted.
    # the deletion will fail if the failed instance deletion is not complete.
    # retry for a while before giving up.
    do {
      foreach ($resourceName in $resourceNames) {
        $resourceType = @{
          'vm' = 'virtual machine';
          'ni' = 'network interface';
          'ip' = 'public ip address';
          'disk' = 'disk'
        }[$resourceName.Split('-')[0]];
        switch ($resourceType) {
          'virtual machine' {
            if (Get-AzVM -ResourceGroupName $resourceGroupName -Name $resourceName -ErrorAction SilentlyContinue) {
              try {
                Remove-AzVm -ResourceGroupName $resourceGroupName -Name $resourceName -Force;
                Write-Output -InputObject (('{0} :: {1}: {2}/{3}, removal appears successful' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $resourceName));
              } catch {
                Write-Output -InputObject (('{0} :: {1}: {2}/{3}, removal threw exception. {4}' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $resourceName, $_.Exception.Message));
              }
            } else {
              Write-Output -InputObject (('{0} :: {1}: {2}/{3} not found. removal skipped' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $resourceName));
            }
          }
          'network interface' {
            if (Get-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name $resourceName -ErrorAction SilentlyContinue) {
              try {
                Remove-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name $resourceName -Force;
                Write-Output -InputObject (('{0} :: {1}: {2}/{3}, removal appears successful' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $resourceName));
              } catch {
                Write-Output -InputObject (('{0} :: {1}: {2}/{3}, removal threw exception. {4}' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $resourceName, $_.Exception.Message));
              }
            } else {
              Write-Output -InputObject (('{0} :: {1}: {2}/{3} not found. removal skipped' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $resourceName));
            }
          }
          'public ip address' {
            if (Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name $resourceName -ErrorAction SilentlyContinue) {
              try {
                Remove-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name $resourceName -Force;
                Write-Output -InputObject (('{0} :: {1}: {2}/{3}, removal appears successful' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $resourceName));
              } catch {
                Write-Output -InputObject (('{0} :: {1}: {2}/{3}, removal threw exception. {4}' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $resourceName, $_.Exception.Message));
              }
            } else {
              Write-Output -InputObject (('{0} :: {1}: {2}/{3} not found. removal skipped' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $resourceName));
            }
          }
          'disk' {
            if (Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $resourceName -ErrorAction SilentlyContinue) {
              foreach ($azDisk in @(Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $resourceName -ErrorAction SilentlyContinue)) {
                try {
                  Remove-AzDisk -ResourceGroupName $resourceGroupName -DiskName $azDisk.Name -Force;
                  Write-Output -InputObject (('{0} :: {1}: {2}/{3}, removal appears successful' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $azDisk.Name));
                } catch {
                  Write-Output -InputObject (('{0} :: {1}: {2}/{3}, removal threw exception. {4}' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $azDisk.Name, $_.Exception.Message));
                }
              }
            } else {
              Write-Output -InputObject (('{0} :: {1}: {2}/{3} not found. removal skipped' -f $($MyInvocation.MyCommand.Name), $resourceType, $resourceGroupName, $resourceName));
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
    Write-Output -InputObject ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
}

function Update-RequiredModules {
  param (
    [string] $repository = 'PSGallery',
    [hashtable[]] $requiredModules = @(
      @{
        'module' = 'posh-minions-managed';
        'version' = '0.0.79'
      },
      @{
        'module' = 'powershell-yaml';
        'version' = '0.4.1'
      }
    )
  )
  begin {
    Write-Output -InputObject ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
  process {
    if (@(Get-PSRepository -Name $repository)[0].InstallationPolicy -ne 'Trusted') {
      try {
        Set-PSRepository -Name $repository -InstallationPolicy 'Trusted';
        Write-Output -InputObject ('{0} :: setting of installation policy to trusted for repository: {1}, succeeded' -f $($MyInvocation.MyCommand.Name), $repository);
      } catch {
        Write-Output -InputObject ('{0} :: setting of installation policy to trusted for repository: {1}, failed. {2}' -f $($MyInvocation.MyCommand.Name), $repository, $_.Exception.Message);
      }
    }
    foreach ($rm in $requiredModules) {
      $module = (Get-Module -Name $rm.module -ErrorAction SilentlyContinue);
      if ($module) {
        if ($module.Version -lt $rm.version) {
          try {
            Update-Module -Name $rm.module -RequiredVersion $rm.version;
            Write-Output -InputObject ('{0} :: update of required module: {1}, version: {2}, succeeded' -f $($MyInvocation.MyCommand.Name), $rm.module, $rm.version);
          } catch {
            Write-Output -InputObject ('{0} :: update of required module: {1}, version: {2}, failed. {3}' -f $($MyInvocation.MyCommand.Name), $rm.module, $rm.version, $_.Exception.Message);
          }
        }
      } else {
        try {
          Install-Module -Name $rm.module -RequiredVersion $rm.version -AllowClobber;
          Write-Output -InputObject ('{0} :: install of required module: {1}, version: {2}, succeeded' -f $($MyInvocation.MyCommand.Name), $rm.module, $rm.version);
        } catch {
          Write-Output -InputObject ('{0} :: install of required module: {1}, version: {2}, failed. {3}' -f $($MyInvocation.MyCommand.Name), $rm.module, $rm.version, $_.Exception.Message);
        }
      }
      try {
        Import-Module -Name $rm.module -RequiredVersion $rm.version -ErrorAction SilentlyContinue;
        Write-Output -InputObject ('{0} :: import of required module: {1}, version: {2}, succeeded' -f $($MyInvocation.MyCommand.Name), $rm.module, $rm.version);
      } catch {
        Write-Output -InputObject ('{0} :: import of required module: {1}, version: {2}, failed. {3}' -f $($MyInvocation.MyCommand.Name), $rm.module, $rm.version, $_.Exception.Message);
        # if we get here, the instance is borked and will throw exceptions on all subsequent tasks.
        & shutdown @('/s', '/t', '3', '/c', 'borked powershell module library detected', '/f', '/d', '1:1');
        exit 123;
      }
    }
  }
  end {
    Write-Output -InputObject ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
}

function Initialize-Platform {
  param (
    [string] $platform,
    [object] $secret
  )
  begin {
    Write-Output -InputObject ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
  process {
    switch ($platform) {
      'azure' {
        try {
          Connect-AzAccount `
            -ServicePrincipal `
            -Credential (New-Object System.Management.Automation.PSCredential($secret.azure.id, (ConvertTo-SecureString `
              -String $secret.azure.key `
              -AsPlainText `
              -Force))) `
            -Tenant $secret.azure.account | Out-Null;
          Write-Output -InputObject ('{0} :: for platform: {1}, setting of credentials, succeeded' -f $($MyInvocation.MyCommand.Name), $platform);
        } catch {
          Write-Output -InputObject ('{0} :: for platform: {1}, setting of credentials, failed. {2}' -f $($MyInvocation.MyCommand.Name), $platform, $_.Exception.Message);
        }
        try {
          $azcopyExePath = ('{0}\azcopy.exe' -f $workFolder);
          $azcopyZipPath = ('{0}\azcopy.zip' -f $workFolder);
          $azcopyZipUrl = 'https://aka.ms/downloadazcopy-v10-windows';
          if (-not (Test-Path -Path $azcopyExePath -ErrorAction SilentlyContinue)) {
            (New-Object Net.WebClient).DownloadFile($azcopyZipUrl, $azcopyZipPath);
            if (Test-Path -Path $azcopyZipPath -ErrorAction SilentlyContinue) {
              Write-Output -InputObject ('{0} :: downloaded: {1} from: {2}' -f $($MyInvocation.MyCommand.Name), $azcopyZipPath, $azcopyZipUrl);
              Expand-Archive -Path $azcopyZipPath -DestinationPath $workFolder;
              try {
                $extractedAzcopyExePath = (@(Get-ChildItem -Path ('{0}\azcopy.exe' -f $workFolder) -Recurse -ErrorAction SilentlyContinue -Force)[0].FullName);
                Write-Output -InputObject ('{0} :: extracted: {1} from: {2}' -f $($MyInvocation.MyCommand.Name), $extractedAzcopyExePath, $azcopyZipPath);
                Copy-Item -Path $extractedAzcopyExePath -Destination $azcopyExePath;
                if (Test-Path -Path $azcopyExePath -ErrorAction SilentlyContinue) {
                  Write-Output -InputObject ('{0} :: copied: {1} to: {2}' -f $($MyInvocation.MyCommand.Name), $extractedAzcopyExePath, $azcopyExePath);
                  $env:PATH = ('{0};{1}' -f $env:PATH, $workFolder);
                  [Environment]::SetEnvironmentVariable('PATH', $env:PATH, 'User');
                  Write-Output -InputObject ('{0} :: user env PATH set to: {1}' -f $($MyInvocation.MyCommand.Name), $env:PATH);
                }
              } catch {
                Write-Output -InputObject ('{0} :: failed to extract azcopy from: {1}' -f $($MyInvocation.MyCommand.Name), $azcopyZipPath);
              }
            } else {
              Write-Output -InputObject ('{0} :: failed to download: {1} from: {2}' -f $($MyInvocation.MyCommand.Name), $azcopyZipPath, $azcopyZipUrl);
              exit 123;
            }
          }
          Write-Output -InputObject ('{0} :: for platform: {1}, acquire of platform tools, succeeded' -f $($MyInvocation.MyCommand.Name), $platform);
        } catch {
          Write-Output -InputObject ('{0} :: for platform: {1}, acquire of platform tools, failed. {2}' -f $($MyInvocation.MyCommand.Name), $platform, $_.Exception.Message);
        }
      }
      'amazon' {
        try {
          Set-AWSCredential `
            -AccessKey $secret.amazon.id `
            -SecretKey $secret.amazon.key `
            -StoreAs 'default' | Out-Null;
          Write-Output -InputObject ('{0} :: on platform: {1}, setting of credentials, succeeded' -f $($MyInvocation.MyCommand.Name), $platform);
        } catch {
          Write-Output -InputObject ('{0} :: on platform: {1}, setting of credentials, failed. {2}' -f $($MyInvocation.MyCommand.Name), $platform, $_.Exception.Message);

        }
      }
    }
  }
  end {
    Write-Output -InputObject ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
}

function Get-ImageArtifactDescriptor {
  param (
    [string] $platform,
    [string] $imageKey,
    [string] $uri = ('{0}/api/index/v1/task/project.relops.cloud-image-builder.{1}.{2}.latest/artifacts/public/image-bucket-resource.json' -f $env:TASKCLUSTER_ROOT_URL, $platform, $imageKey)
  )
  begin {
    Write-Debug -Message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
  process {
    $imageArtifactDescriptor = $null;
    try {
      $memoryStream = (New-Object System.IO.MemoryStream(, (New-Object System.Net.WebClient).DownloadData($uri)));
      $streamReader = (New-Object System.IO.StreamReader(New-Object System.IO.Compression.GZipStream($memoryStream, [System.IO.Compression.CompressionMode] 'Decompress')));
      $imageArtifactDescriptor = ($streamReader.ReadToEnd() | ConvertFrom-Json);
      Write-Debug -Message ('{0} :: disk image config for: {1}, on {2}, fetch and extraction from: {3}, suceeded' -f $($MyInvocation.MyCommand.Name), $imageKey, $platform, $uri);
    } catch {
      Write-Debug -Message ('{0} :: disk image config for: {1}, on {2}, fetch and extraction from: {3}, failed. {4}' -f $($MyInvocation.MyCommand.Name), $imageKey, $platform, $uri, $_.Exception.Message);
      exit 1
    }
    return $imageArtifactDescriptor;
  }
  end {
    Write-Debug -Message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
}

function Invoke-SnapshotCopy {
  param (
    [string] $platform,
    [string] $imageKey,
    [object] $target,
    [string] $targetImageName,
    [object] $imageArtifactDescriptor,
    [string] $targetSnapshotName = ('{0}-{1}-{2}' -f $target.group.Replace('rg-', ''), $imageKey, $imageArtifactDescriptor.build.revision.Substring(0, 7))
  )
  begin {
    Write-Output -InputObject ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
  process {
    # check if the image snapshot exists in another regional resource-group
    foreach ($source in @($config.target | ? { (($_.platform -eq $platform) -and $_.group -ne $group) })) {
      $sourceSnapshotName = ('{0}-{1}-{2}' -f $source.group.Replace('rg-', ''), $imageKey, $imageArtifactDescriptor.build.revision.Substring(0, 7));
      $sourceSnapshot = (Get-AzSnapshot `
        -ResourceGroupName $source.group `
        -SnapshotName $sourceSnapshotName `
        -ErrorAction SilentlyContinue);
      if ($sourceSnapshot) {
        Write-Output -InputObject ('{0} :: found snapshot: {1}, in group: {2}, in cloud platform: {3}. triggering machine copy from {2} to {4}...' -f $($MyInvocation.MyCommand.Name), $sourceSnapshotName, $source.group, $source.platform, $target.group);

        # get/create storage account in target region
        $storageAccountName = ('{0}cib' -f $target.group.Replace('rg-', '').Replace('-', ''));
        $targetAzStorageAccount = (Get-AzStorageAccount `
          -ResourceGroupName $target.group `
          -Name $storageAccountName);
        if ($targetAzStorageAccount) {
          Write-Output -InputObject ('{0} :: detected storage account: {1}, for resource group: {2}' -f $($MyInvocation.MyCommand.Name), $storageAccountName, $target.group);
        } else {
          $targetAzStorageAccount = (New-AzStorageAccount `
            -ResourceGroupName $target.group `
            -AccountName $storageAccountName `
            -Location $target.region.Replace(' ', '').ToLower() `
            -SkuName 'Standard_LRS');
          Write-Output -InputObject ('{0} :: created storage account: {1}, for resource group: {2}' -f $($MyInvocation.MyCommand.Name), $storageAccountName, $target.group);
        }
        if (-not ($targetAzStorageAccount)) {
          Write-Output -InputObject ('{0} :: failed to get or create az storage account: {1}' -f $($MyInvocation.MyCommand.Name), $storageAccountName);
          exit 1;
        }

        # get/create storage container (bucket) in target region
        $storageContainerName = ('{0}cib' -f $target.group.Replace('rg-', '').Replace('-', ''));
        $targetAzStorageContainer = (Get-AzStorageContainer `
          -Name $storageContainerName `
          -Context $targetAzStorageAccount.Context);
        if ($targetAzStorageContainer) {
          Write-Output -InputObject ('{0} :: detected storage container: {1}' -f $($MyInvocation.MyCommand.Name), $storageContainerName);
        } else {
          $targetAzStorageContainer = (New-AzStorageContainer `
            -Name $storageContainerName `
            -Context $targetAzStorageAccount.Context `
            -Permission 'Container');
          Write-Output -InputObject ('{0} :: created storage container: {1}' -f $($MyInvocation.MyCommand.Name), $storageContainerName);
        }
        if (-not ($targetAzStorageContainer)) {
          Write-Output -InputObject ('{0} :: failed to get or create az storage container: {1}' -f $($MyInvocation.MyCommand.Name), $storageContainerName);
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
        Write-Output -InputObject ('{0} :: provisioning of snapshot: {1}, has state: {2}' -f $($MyInvocation.MyCommand.Name), $targetSnapshotName, $targetAzSnapshot.ProvisioningState.ToLower());
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
          Write-Output -InputObject ('{0} :: provisioning of image: {1}, failed' -f $($MyInvocation.MyCommand.Name), $targetImageName);
          exit 1;
        }
        Write-Output -InputObject ('{0} :: provisioning of image: {1}, has state: {2}' -f $($MyInvocation.MyCommand.Name), $targetImageName, $targetAzImage.ProvisioningState.ToLower());
        exit;
      }
    }
  }
  end {
    Write-Output -InputObject ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
}

function Get-AzureSkuFamily {
  param (
    [string] $sku
  )
  begin {
    Write-Debug -Message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
  process {
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
        $skuFamily = $null;
        break;
      }
    }
    if ($skuFamily) {
      Write-Debug -Message ('{0} :: azure sku family determined as {1} from sku {2}' -f $($MyInvocation.MyCommand.Name), $skuFamily, $sku);
    } else {
      Write-Debug -Message ('{0} :: failed to determine azure sku family from sku {1}' -f $($MyInvocation.MyCommand.Name), $sku);
    }
    return $skuFamily;
  }
  end {
    Write-Debug -Message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
}

function Get-PublicIpAddress {
  param (
    [string] $platform,
    [string] $group,
    [string] $resourceId
  )
  begin {
    Write-Debug -Message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
  process {
    $publicIpAddress = $null;
    try {
      switch ($platform) {
        'azure' {
          $publicIpAddress = (Get-AzPublicIpAddress -ResourceGroupName $group -Name ('ip-{0}' -f $resourceId)).IpAddress;
          Write-Debug -Message ('{0} :: public ip address for resource: {1}, in group: {2}, on platform: {3}, determined as: {4}' -f $($MyInvocation.MyCommand.Name), $resourceId, $group, $platform, $publicIpAddress);
        }
        default {
          Write-Debug -Message ('{0} :: not implementated for platform: {1}' -f $($MyInvocation.MyCommand.Name), $platform);
        }
      }
    } catch {
      Write-Debug -Message ('{0} :: failed to determine public ip address for resource: {1}, in group: {2}, on platform: {3}. {4}' -f $($MyInvocation.MyCommand.Name), $resourceId, $group, $platform, $_.Exception.Message);
    }
    return $publicIpAddress;
  }
  end {
    Write-Debug -Message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
}

function Get-AdminPassword {
  param (
    [string] $platform,
    [string] $imageKey,
    [string] $uri = ('{0}/api/index/v1/task/project.relops.cloud-image-builder.{1}.{2}.latest/artifacts/public/unattend.xml' -f $env:TASKCLUSTER_ROOT_URL, $platform, $imageKey)
  )
  begin {
    Write-Debug -Message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
  process {
    try {
      $memoryStream = (New-Object System.IO.MemoryStream(, (New-Object System.Net.WebClient).DownloadData($uri)));
      $streamReader = (New-Object System.IO.StreamReader(New-Object System.IO.Compression.GZipStream($memoryStream, [System.IO.Compression.CompressionMode] 'Decompress')));
      [xml]$imageUnattendFileXml = [xml]$streamReader.ReadToEnd();
      Write-Debug -Message ('{0} :: unattend file for: {1}, on {2}, fetch and extraction from: {3}, suceeded' -f $($MyInvocation.MyCommand.Name), $imageKey, $platform, $uri);
    } catch {
      Write-Output -InputObject ('{0} :: unattend file for: {1}, on {2}, fetch and extraction from: {3}, failed. {4}' -f $($MyInvocation.MyCommand.Name), $imageKey, $platform, $uri, $_.Exception.Message);
      throw;
    }
    $administratorPassword = (($imageUnattendFileXml.unattend.settings | ? { $_.pass -eq 'oobeSystem' }).component | ? { $_.name -eq 'Microsoft-Windows-Shell-Setup' }).UserAccounts.AdministratorPassword;
    if ($administratorPassword.PlainText -eq 'false') {
      return [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($administratorPassword.Value));
    }
    return $administratorPassword.Value;
  }
  end {
    Write-Debug -Message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
}

function Do-Stuff {
  param (
    [string] $arg1 = ''
  )
  begin {
    Write-Output -InputObject ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
  process {
  }
  end {
    Write-Output -InputObject ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime());
  }
}

# job settings. change these for the tasks at hand.
#$VerbosePreference = 'continue';
$workFolder = (Resolve-Path -Path ('{0}\..' -f $PSScriptRoot));

# constants and script config. these are probably ok as they are.
$revision = $(& git rev-parse HEAD);
$revisionCommitDate = $(& git @('show', '-s', '--format=%ci', $revision));
Write-Output -InputObject ('workFolder: {0}, revision: {1}, platform: {2}, imageKey: {3}' -f $workFolder, $revision, $platform, $imageKey);

Update-RequiredModules

$secret = (Invoke-WebRequest -Uri ('{0}/secrets/v1/secret/project/relops/image-builder/dev' -f $env:TASKCLUSTER_PROXY_URL) -UseBasicParsing | ConvertFrom-Json).secret;

Initialize-Platform -platform 'amazon' -secret $secret
Initialize-Platform -platform $platform -secret $secret

try {
  $config = (Get-Content -Path ('{0}\cloud-image-builder\config\{1}.yaml' -f $workFolder, $imageKey) -Raw | ConvertFrom-Yaml);
} catch {
  Write-Output -InputObject ('error: failed to find image config for {0}. {1}' -f $imageKey, $_.Exception.Message);
  exit 1
}
if ($config) {
  Write-Output -InputObject ('parsed image config for {0}' -f $imageKey);
} else {
  Write-Output -InputObject ('error: failed to find image config for {0}' -f $imageKey);
  exit 1
}
$imageArtifactDescriptor = (Get-ImageArtifactDescriptor -platform $platform -imageKey $imageKey);
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
        if ($overwrite) {
          try {
            Write-Output -InputObject ('removing existing machine image {0} / {1} / {2}, created {3:s}' -f $existingImage.Location, $existingImage.ResourceGroupName, $existingImage.Name, $existingImage.Tags.MachineImageCommitTime);
            if (Remove-AzImage `
              -ResourceGroupName $existingImage.ResourceGroupName `
              -Name $existingImage.Name `
              -AsJob `
              -Force) {
              Write-Output -InputObject ('removed existing machine image {0} / {1} / {2}, created {3:s}' -f $existingImage.Location, $existingImage.ResourceGroupName, $existingImage.Name, $existingImage.Tags.MachineImageCommitTime);
            } else {
              Write-Output -InputObject ('failed to remove existing machine image {0} / {1} / {2}, created {3:s}' -f $existingImage.Location, $existingImage.ResourceGroupName, $existingImage.Name, $existingImage.Tags.MachineImageCommitTime);
            }
          } catch {
            Write-Output -InputObject ('exception removing existing machine image {0} / {1} / {2}, created {3:s}. {4}' -f $existingImage.Location, $existingImage.ResourceGroupName, $existingImage.Name, $existingImage.Tags.MachineImageCommitTime, $_.Exception.Message);
          }
        } else {
          Write-Output -InputObject ('skipped machine image creation for: {0}, in group: {1}, in cloud platform: {2}. machine image exists' -f $targetImageName, $target.group, $target.platform);
          exit;
        }
      } elseif ($enableSnapshotCopy) {
        Invoke-SnapshotCopy -platform $platform -imageKey $imageKey -target $target -targetImageName $targetImageName -imageArtifactDescriptor $imageArtifactDescriptor
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
        $skuFamily = (Get-AzureSkuFamily -sku $sku);
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
              'diskImageCommitTime' = (Get-Date -Date $imageArtifactDescriptor.build.time -UFormat '+%Y-%m-%dT%H:%M:%S%Z');
              'diskImageCommitSha' = $imageArtifactDescriptor.build.revision;
              'machineImageCommitTime' = (Get-Date -Date $revisionCommitDate -UFormat '+%Y-%m-%dT%H:%M:%S%Z');
              'machineImageCommitSha' = $revision;
              'imageKey' = $imageKey;
              'resourceId' = $resourceId;
              'os' = $config.image.os;
              'edition' = $config.image.edition;
              'language' = $config.image.language;
              'architecture' = $config.image.architecture;
              'isoIndex' = $config.iso.wimindex;
              'isoName' = ([System.IO.Path]::GetFileName($config.iso.source.key))
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
                if (-not $disableCleanup) {
                  Remove-Resource -resourceId $resourceId -resourceGroupName $target.group;
                }
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
                Invoke-BootstrapExecutions -instanceName $instanceName -groupName $target.group -executions $target.bootstrap.executions -flow $target.network.flow -disableCleanup:$disableCleanup;
                # todo implement success check
                $successfulBootstrapDetected = $true;
              } else {
                Write-Output -InputObject ('no bootstrap command execution configurations detected for: {0}/{1}' -f $target.group, $instanceName);
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
                  -imageName $targetImageName `
                  -imageTags $tags;
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
                if ($enableSnapshotCopy) {
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
                    if (-not $disableCleanup) {
                      Remove-Resource -resourceId $resourceId -resourceGroupName $target.group;
                    }
                  }
                } else {
                  Write-Output -InputObject ('snapshot creation skipped because enableSnapshotCopy is set to false');
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
          } finally {
            if (-not $disableCleanup) {
              Remove-Resource -resourceId $resourceId -resourceGroupName $target.group;
            }
          }
        }
      }
    }
  }
}
