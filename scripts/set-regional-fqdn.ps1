
function Get-Fqdn {
  if (Test-Path -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\NV Domain') {
    return (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'NV Domain').'NV Domain';
  } elseif (Test-Path -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Domain') {
    return (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'Domain').Domain;
  } else {
    return $env:USERDOMAIN;
  }
}

function Set-Fqdn {
  param (
    [string] $fqdn
  )
  [Environment]::SetEnvironmentVariable('USERDOMAIN', $fqdn, 'Machine');
  $env:USERDOMAIN = $fqdn;
  Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'Domain' -Value $fqdn;
  Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'NV Domain' -Value $fqdn;
}

$location = (((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri 'http://169.254.169.254/metadata/instance?api-version=2019-06-04').Content | ConvertFrom-Json).compute.location);
$pool = (@(((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri 'http://169.254.169.254/metadata/instance?api-version=2019-06-04').Content | ConvertFrom-Json).compute.tagsList | ? { $_.name -eq 'workerType' })[0].value);
Write-Output -InputObject ('set-regional-fqdn :: determined location: {0}, pool: {1}, from instance metadata' -f $location, $pool);
$actualFqdn = (Get-Fqdn);
$expectedFqdn = ('{0}.{1}.mozilla.com' -f $pool, $location);
if ($actualFqdn -ne $expectedFqdn) {
  Set-Fqdn -fqdn $expectedFqdn;
  if ((Get-Fqdn) -eq $expectedFqdn) {
    Write-Output -InputObject ('set-regional-fqdn :: fqdn changed from: {0} to: {1}.' -f $actualFqdn, $expectedFqdn);
    # cause sysprep to reboot and move to next unattend command
    exit 1
  } else {
    Write-Output -InputObject ('set-regional-fqdn :: failed to change fqdn from: {0} to: {1}.' -f $actualFqdn, $expectedFqdn);
    # cause sysprep to reboot and rerun
    exit 2
  }
} else {
  Write-Output -InputObject ('set-regional-fqdn :: actual fqdn: {0} matches expected fqdn: {1}.' -f $actualFqdn, $expectedFqdn);
  # cause sysprep to skip reboot and move to next unattend command
  exit 0
}
