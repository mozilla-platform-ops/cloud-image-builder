
# install the azure ad powershell tools
if (@(Get-PSRepository -Name 'PSGallery')[0].InstallationPolicy -ne 'Trusted') {
  Set-PSRepository -Name 'PSGallery' -InstallationPolicy 'Trusted';
}
foreach ($rm in @(
  @{ 'module' = 'AzureAD'; 'version' = '2.0.2.76' }
)) {
  $module = (Get-Module -Name $rm.module -ErrorAction SilentlyContinue);
  if ($module) {
    if ($module.Version -lt $rm.version) {
      Update-Module -Name $rm.module -RequiredVersion $rm.version;
    }
  } else {
    Install-Module -Name $rm.module -RequiredVersion $rm.version -AllowClobber;
  }
  Import-Module -Name $rm.module -RequiredVersion $rm.version -ErrorAction SilentlyContinue;
}


# authenticate with azure (uncommented option will prompt for creds, commented option can be used in non-interactive scripts)
Connect-AzureAD -Credential Get-Credential;
#Connect-AzureAD -Credential (New-Object Management.Automation.PSCredential('username', (ConvertTo-SecureString -String 'password' -AsPlainText -Force)))

# get the group ids for the relops and Taskcluster ad groups
$azureAdminGroupIds = @((Get-AzureADGroup -Filter "DisplayName eq 'relops' or DisplayName eq 'Taskcluster'") | % { $_.ObjectId });

# get the user ids for the relops and Taskcluster ad group members
$azureAdminIds = @();
foreach ($azureAdminGroupId in $azureAdminGroupIds) {
  foreach ($groupMemberId in @((Get-AzureADGroupMember -ObjectId $azureAdminGroupId -All:$true) | % { $_.ObjectId })) {
    if ($azureAdminIds -notcontains $groupMemberId) {
      $azureAdminIds += $groupMemberId;
    }
  }
}


foreach ($azureApplicationName in @('fxci-test-azure', 'fxci-level1-azure', 'fxci-level3-azure')) {
  # get or create application
  $azureApplication = (Get-AzureADApplication -Filter "DisplayName eq '$azureApplicationName'");
  if (-not $azureApplication) {
    $azureApplication = (New-AzureADApplication -DisplayName $azureApplicationName);
  }
  # add each member of the relops and Taskcluster ad groups as an application owner
  $ownerIds = @((Get-AzureADApplicationOwner -ObjectId $azureApplication.ObjectId -All:$true) | % { $_.ObjectId })
  foreach ($azureAdminId in $azureAdminIds) {
    if ($ownerIds -notcontains $azureAdminId) {
      Add-AzureADApplicationOwner -ObjectId $azureApplication.ObjectId -RefObjectId $azureAdminId;
    }
  }
}
