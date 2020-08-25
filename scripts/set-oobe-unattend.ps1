if ((Test-Path -Path 'C:\unattend.xml' -ErrorAction SilentlyContinue) -and (-not (Test-Path -Path 'C:\oobe-unattend.xml' -ErrorAction SilentlyContinue))) {
  try {
    [xml] $unattend = Get-Content -Path 'C:\unattend.xml';
    $nsmgr = New-Object System.Xml.XmlNamespaceManager($unattend.NameTable);
    $nsmgr.AddNamespace('ns', 'urn:schemas-microsoft-com:unattend');
    $unattend.SelectSingleNode("//ns:settings[@pass='oobeSystem']/ns:component[@name='Microsoft-Windows-Deployment']", $nsmgr).RemoveChild($unattend.SelectSingleNode("//ns:settings[@pass='oobeSystem']/ns:component[@name='Microsoft-Windows-Deployment']/ns:Reseal", $nsmgr)) | Out-Null;
    $unattend.Save('C:\oobe-unattend.xml') | Out-Null;
    if (Test-Path -Path 'C:\oobe-unattend.xml' -ErrorAction SilentlyContinue) {
      Write-Output -InputObject 'C:\oobe-unattend.xml created from C:\unattend.xml with oobe reseal to audit removed';
    } else {
      Write-Error -Message 'failed to create C:\oobe-unattend.xml from C:\unattend.xml with oobe reseal to audit removed';
    }
  } catch {
    Write-Error -Exception $_.Exception -Message 'failed to create C:\oobe-unattend.xml from C:\unattend.xml with oobe reseal to audit removed';
  }
} elseif ((Test-Path -Path 'C:\oobe-unattend.xml' -ErrorAction SilentlyContinue) -and (-not (Test-Path -Path 'C:\unattend.xml' -ErrorAction SilentlyContinue))) {
  try {
    Rename-Item -Path 'C:\oobe-unattend.xml' -NewName 'C:\unattend.xml' -Force;
    if ((Test-Path -Path 'C:\unattend.xml' -ErrorAction SilentlyContinue) -and (-not (Test-Path -Path 'C:\oobe-unattend.xml' -ErrorAction SilentlyContinue))) {
      Write-Output -InputObject 'C:\oobe-unattend.xml renamed as C:\unattend.xml';
    } else {
      Write-Error -Message 'failed to rename C:\oobe-unattend.xml as C:\unattend.xml';
    }
  } catch {
    Write-Error -Exception $_.Exception -Message 'failed to rename C:\oobe-unattend.xml as C:\unattend.xml';
  }
}