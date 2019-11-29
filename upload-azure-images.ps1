foreach ($vhdPath in @(Get-ChildItem -Path 'D:\azure-ci\*.vhd')) {
  $resourceGroupName = $(if ($vhdPath.Name.Contains('server')) { 'gecko-1' } else { 'gecko-t' });
  $diskName = [io.path]::GetFileNameWithoutExtension($vhdPath.Name).Replace('-fixed.vhd', '');
  $targetLocation = 'East US';
  $storageSkuName = 'StandardSSD_LRS'; #Standard_LRS, Premium_LRS, StandardSSD_LRS, UltraSSD_LRS
  $osType = 'Windows'; # Windows, Linux
  $vhdSizeBytes = (Get-Item -Path $vhdPath.FullName).Length;
  $diskconfig = New-AzDiskConfig -SkuName $storageSkuName -OsType $osType -UploadSizeInBytes $vhdSizeBytes -Location $targetLocation -CreateOption 'Upload';
  New-AzDisk -ResourceGroupName $resourceGroupName -DiskName $diskName -Disk $diskconfig;
  $diskSas = Grant-AzDiskAccess -ResourceGroupName $resourceGroupName -DiskName $diskName -DurationInSecond 86400 -Access 'Write';
  $disk = Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $diskName;
  & AzCopy.exe @('copy', $vhdPath.FullName, $diskSas.AccessSAS, '--blob-type', 'PageBlob')
  Revoke-AzDiskAccess -ResourceGroupName $resourceGroupName -DiskName $diskName;
}