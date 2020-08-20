if ((Test-Path -Path 'C:\unattend.xml' -ErrorAction SilentlyContinue) -and (-not (Test-Path -Path 'C:\oobe-unattend.xml' -ErrorAction SilentlyContinue))) {
  [xml] $unattend = Get-Content -Path 'C:\unattend.xml';
  $nsmgr = New-Object System.Xml.XmlNamespaceManager($unattend.NameTable);
  $nsmgr.AddNamespace('ns', 'urn:schemas-microsoft-com:unattend');
  $unattend.SelectSingleNode("//ns:settings[@pass='oobeSystem']/ns:component[@name='Microsoft-Windows-Deployment']", $nsmgr).RemoveChild($unattend.SelectSingleNode("//ns:settings[@pass='oobeSystem']/ns:component[@name='Microsoft-Windows-Deployment']/ns:Reseal", $nsmgr)) | Out-Null;
  $unattend.Save('C:\oobe-unattend.xml') | Out-Null;
} elseif ((Test-Path -Path 'C:\oobe-unattend.xml' -ErrorAction SilentlyContinue) -and (-not (Test-Path -Path 'C:\unattend.xml' -ErrorAction SilentlyContinue))) {
  Rename-Item -Path 'C:\oobe-unattend.xml' -NewName 'C:\unattend.xml' -Force;
}