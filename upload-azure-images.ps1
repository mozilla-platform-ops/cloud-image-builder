# login:
Connect-AzAccount

# this succeeded. disks can be seen at: https://portal.azure.com/#blade/HubsExtension/BrowseResourceBlade/resourceType/Microsoft.Compute%2Fdisks
# or with:
# Get-AzDisk -ResourceGroupName 'gecko-t' -name 'windows10*'
# Get-AzDisk -ResourceGroupName 'gecko-1' -name 'windowsserver201*'
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

# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/upload-generalized-managed
# none of what's below works yet.
# figure out how to get the BlobUri required by Set-AzImageOsDisk
$targetLocation = 'East US';
$osType = 'Windows';
foreach ($vhdPath in @(Get-ChildItem -Path 'D:\azure-ci\*.vhd')) {
  $imageConfig = New-AzImageConfig -Location $targetLocation
  $imageOsDisk = Set-AzImageOsDisk `
   -Image $imageConfig `
   -OsType $osType `
   -OsState 'Generalized' ` # https://azure.microsoft.com/en-us/blog/vm-image-blog-post/
   -BlobUri $urlOfUploadedImageVhd `
   -DiskSizeGB 20
  
  New-AzImage `
   -ImageName $imageName `
   -ResourceGroupName $rgName `
   -Image $imageConfig
  
  New-AzVm `
    -ResourceGroupName $rgName `
    -Name "myVM" `
    -ImageName $imageName `
    -Location $location `
    -VirtualNetworkName "myVnet" `
    -SubnetName "mySubnet" `
    -SecurityGroupName "myNSG" `
    -PublicIpAddressName "myPIP" `
    -OpenPorts 3389
}