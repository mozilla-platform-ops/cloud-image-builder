
$location = (((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri 'http://169.254.169.254/metadata/instance?api-version=2019-06-04').Content | ConvertFrom-Json).compute.location);
$pool = (@(((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri 'http://169.254.169.254/metadata/instance?api-version=2019-06-04').Content | ConvertFrom-Json).compute.tagsList | ? { $_.name -eq 'workerType' })[0].value);
Write-Output -InputObject ('set-regional-fqdn :: determined location: {0}, pool: {1}, from instance metadata' -f $location, $pool);
if (Test-Path -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\NV Domain') {
  $actualFqdn = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'NV Domain').'NV Domain';
} elseif (Test-Path -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Domain') {
  $actualFqdn = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'Domain').Domain;
} else {
  $actualFqdn = $env:USERDOMAIN;
}
$expectedFqdn = ('{0}.{1}.mozilla.com' -f $pool, $location);
if (-not ($actualFqdn -ieq $expectedFqdn)) {
  [Environment]::SetEnvironmentVariable('USERDOMAIN', $expectedFqdn, 'Machine');
  $env:USERDOMAIN = $expectedFqdn;
  Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'Domain' -Value $expectedFqdn;
  Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'NV Domain' -Value $expectedFqdn;
  Write-Output -InputObject ('set-regional-fqdn :: fqdn changed from: {0} to: {1}.' -f $actualFqdn, $expectedFqdn);
} else {
  Write-Output -InputObject ('set-regional-fqdn :: actual fqdn: {0} matches expected fqdn: {1}.' -f $actualFqdn, $expectedFqdn);
}
