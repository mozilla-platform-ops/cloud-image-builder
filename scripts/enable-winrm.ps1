

foreach ($network in @(([Activator]::CreateInstance([Type]::GetTypeFromCLSID('DCB00C01-570F-4A9B-8D69-199FDBA5723B'))).GetNetworkConnections() | % { $_.GetNetwork() } | ? { $_.IsConnected })) {
  $networkCategory = $network.GetCategory();
  if ($networkCategory -ne 0x01) {
    $network.SetCategory(0x01);
    Write-Output -InputObject ('changed network category from {0} to 1 on connection "{1}"' -f $networkCategory, $network.GetName());
  } else {
    Write-Output -InputObject ('detected network category {0} on connection "{1}"' -f $networkCategory, $network.GetName());
  }
}

$commands = @(
  @{
    'executable' = 'C:\Windows\System32\winrm.cmd';
    'arguments' = @('quickconfig', '-quiet', '-transport:http');
    'stdout' = 'C:\log\unattend-winrm-quickconfig-stdout.log';
    'stderr' = 'C:\log\unattend-winrm-quickconfig-stderr.log'
  },
  @{
    'executable' = 'C:\Windows\System32\winrm.cmd';
    'arguments' = @('set', 'winrm/config', '@{MaxTimeoutms="1800000"}');
    'stdout' = 'C:\log\unattend-winrm-set-max-timeout-stdout.log';
    'stderr' = 'C:\log\unattend-winrm-set-max-timeout-stderr.log'
  },
  @{
    'executable' = 'C:\Windows\System32\winrm.cmd';
    'arguments' = @('set', 'winrm/config/winrs', '@{MaxMemoryPerShellMB="2048"}');
    'stdout' = 'C:\log\unattend-winrm-set-winrs-shell-memory-stdout.log';
    'stderr' = 'C:\log\unattend-winrm-set-winrs-shell-memory-stderr.log'
  },
  @{
    'executable' = 'C:\Windows\System32\winrm.cmd';
    'arguments' = @('set', 'winrm/config/service', '@{AllowUnencrypted="true"}');
    'stdout' = 'C:\log\unattend-winrm-set-service-allow-unencrypted-stdout.log';
    'stderr' = 'C:\log\unattend-winrm-set-service-allow-unencrypted-stderr.log'
  },
  @{
    'executable' = 'C:\Windows\System32\winrm.cmd';
    'arguments' = @('set', 'winrm/config/service/auth', '@{Basic="true"}');
    'stdout' = 'C:\log\unattend-winrm-set-service-auth-basic-stdout.log';
    'stderr' = 'C:\log\unattend-winrm-set-service-auth-basic-stderr.log'
  },
  @{
    'executable' = 'C:\Windows\System32\winrm.cmd';
    'arguments' = @('set', 'winrm/config/client/auth', '@{Basic="true"}');
    'stdout' = 'C:\log\unattend-winrm-set-client-auth-basic-stdout.log';
    'stderr' = 'C:\log\unattend-winrm-set-client-auth-basic-stderr.log'
  },
  @{
    'executable' = 'C:\Windows\System32\winrm.cmd';
    'arguments' = @('set', 'winrm/config/client', '@{TrustedHosts="*"}');
    'stdout' = 'C:\log\unattend-winrm-set-client-trusted-hosts-stdout.log';
    'stderr' = 'C:\log\unattend-winrm-set-client-trusted-hosts-stderr.log'
  },
  @{
    'executable' = 'C:\Windows\System32\net.exe';
    'arguments' = @('stop', 'winrm');
    'stdout' = 'C:\log\unattend-net-stop-winrm-stdout.log';
    'stderr' = 'C:\log\unattend-net-stop-winrm-stderr.log'
  },
  @{
    'executable' = 'C:\Windows\System32\sc.exe';
    'arguments' = @('config', 'winrm', 'start=', 'auto');
    'stdout' = 'C:\log\unattend-winrm-set-service-auto-start-stdout.log';
    'stderr' = 'C:\log\unattend-winrm-set-service-auto-start-stderr.log'
  },
  @{
    'executable' = 'C:\Windows\System32\net.exe';
    'arguments' = @('start', 'winrm');
    'stdout' = 'C:\log\unattend-net-start-winrm-stdout.log';
    'stderr' = 'C:\log\unattend-net-start-winrm-stderr.log'
  },
  # disabling the windows 7 firewall below is a hack to get winrm working after
  # sysprep completes. it would be preferable to use a firewall exception for
  # inbound tcp on port 5985 (winrm http) on the firewall public profile, but for
  # some reason, that exception is not enough to allow inbound winrm connections.
  # the firewall should be re-enabled as part of the bootstrap process and in any
  # case, the azure security group firewalls remain in place, irrespective of
  # local system firewall state.
  @{
    'executable' = 'C:\Windows\System32\netsh.exe';
    'arguments' = @('advfirewall', 'set', 'allprofiles', 'state', 'off');
    'stdout' = 'C:\log\unattend-disable-firewall-stdout.log';
    'stderr' = 'C:\log\unattend-disable-firewall-stderr.log'
  }
);

foreach ($command in $commands) {
  try {
    $process = (Start-Process -FilePath $command.executable -ArgumentList $command.arguments -NoNewWindow -RedirectStandardOutput $command.stdout -RedirectStandardError $command.stderr -PassThru);
    Wait-Process -InputObject $process; # see: https://stackoverflow.com/a/43728914/68115
    Write-Output -InputObject ('{0} :: {1} - (`{2} {3}`) command exited with code: {4} after a processing time of: {5}.' -f 'enable-winrm', [IO.Path]::GetFileNameWithoutExtension($command.executable), $command.executable, ([string[]]$command.arguments -join ' '), $(if ($process.ExitCode -or ($process.ExitCode -eq 0)) { $process.ExitCode } else { '-' }), $(if ($process.TotalProcessorTime -or ($process.TotalProcessorTime -eq 0)) { $process.TotalProcessorTime } else { '-' }));
  } catch {
    Write-Output -InputObject ('{0} :: {1} - error executing command ({2} {3}). {4}' -f 'enable-winrm', [IO.Path]::GetFileNameWithoutExtension($command.executable), $command.executable, ([string[]]$command.arguments -join ' '), $_.Exception.Message);
  } finally {
    foreach ($stdStreamPath in @(@($command.stderr, $command.stdout) | ? { ((Test-Path $_ -PathType leaf -ErrorAction SilentlyContinue) -and ((Get-Item -Path $_ -ErrorAction SilentlyContinue).Length -le 0)) })) {
      Remove-Item -Path $stdStreamPath -ErrorAction SilentlyContinue;
    }
  }
}
