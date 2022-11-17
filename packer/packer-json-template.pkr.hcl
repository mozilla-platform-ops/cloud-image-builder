
variable "Project" {
  type    = string
  default = "${env("Project")}"
}

variable "base_image" {
  type    = string
  default = "${env("base_image")}"
}

variable "bootstrapscript" {
  type    = string
  default = "${env("bootstrapscript")}"
}

variable "client_id" {
  type    = string
  default = "${env("client_id")}"
}

variable "client_secret" {
  type    = string
  default = "${env("client_secret")}"
}

variable "deploymentId" {
  type    = string
  default = "${env("deploymentId")}"
}

variable "disk_additional_size" {
  type    = string
  default = "${env("disk_additional_size")}"
}

variable "image_offer" {
  type    = string
  default = "${env("image_offer")}"
}

variable "image_publisher" {
  type    = string
  default = "${env("image_publisher")}"
}

variable "image_sku" {
  type    = string
  default = "${env("image_sku")}"
}

variable "location" {
  type    = string
  default = "${env("location")}"
}

variable "managed-by" {
  type    = string
  default = "${env("managed_by")}"
}

variable "managed_image_name" {
  type    = string
  default = "${env("managed_image_name")}"
}

variable "managed_image_resource_group_name" {
  type    = string
  default = "${env("managed_image_resource_group_name")}"
}

variable "managed_image_storage_account_type" {
  type    = string
  default = "${env("managed_image_storage_account_type")}"
}

variable "sourceBranch" {
  type    = string
  default = "${env("sourceBranch")}"
}

variable "sourceOrganisation" {
  type    = string
  default = "${env("sourceOrganisation")}"
}

variable "sourceRepository" {
  type    = string
  default = "${env("sourceRepository")}"
}

variable "subscription_id" {
  type    = string
  default = "${env("subscription_id")}"
}

variable "temp_resource_group_name" {
  type    = string
  default = "${env("temp_resource_group_name")}"
}

variable "tenant_id" {
  type    = string
  default = "${env("tenant_id")}"
}

variable "vm_size" {
  type    = string
  default = "${env("vm_size")}"
}

variable "worker_pool_id" {
  type    = string
  default = "${env("worker_pool_id")}"
}

source "azure-arm" "windowsimage" {
  async_resourcegroup_delete = true
  azure_tags = {
    Project            = "${var.Project}"
    base_image         = "${var.base_image}"
    deploymentId       = "${var.deploymentId}"
    sourceBranch       = "${var.sourceBranch}"
    sourceOrganisation = "${var.sourceOrganisation}"
    sourceRepository   = "${var.sourceRepository}"
    worker_pool_id     = "${var.worker_pool_id}"
  }
  client_id                              = "${var.client_id}"
  client_secret                          = "${var.client_secret}"
  communicator                           = "winrm"
  image_offer                            = "${var.image_offer}"
  image_publisher                        = "${var.image_publisher}"
  image_sku                              = "${var.image_sku}"
  location                               = "${var.location}"
  managed_image_name                     = "${var.managed_image_name}"
  managed_image_resource_group_name      = "${var.managed_image_resource_group_name}"
  managed_image_storage_account_type     = "${var.managed_image_storage_account_type}"
  os_type                                = "Windows"
  private_virtual_network_with_public_ip = "true"
  subscription_id                        = "${var.subscription_id}"
  temp_resource_group_name               = "${var.temp_resource_group_name}"
  tenant_id                              = "${var.tenant_id}"
  virtual_network_name                   = ""
  virtual_network_resource_group_name    = ""
  virtual_network_subnet_name            = ""
  vm_size                                = "${var.vm_size}"
  winrm_insecure                         = "true"
  winrm_timeout                          = "3m"
  winrm_use_ssl                          = "true"
  winrm_username                         = "packer"
}

build {
  sources = ["source.azure-arm.windowsimage"]

  provisioner "powershell" {
    inline = ["$ErrorActionPreference='SilentlyContinue'", "Set-ExecutionPolicy unrestricted -force"]
  }

  provisioner "powershell" {
    elevated_password = ""
    elevated_user     = "SYSTEM"
    inline            = ["Invoke-Expression ((New-Object -TypeName net.webclient).DownloadString('${var.bootstrapscript}'))"]
  }

  provisioner "windows-restart" {
  }

  provisioner "powershell" {
    elevated_password = ""
    elevated_user     = "SYSTEM"
    inline            = ["Invoke-Expression ((New-Object -TypeName net.webclient).DownloadString('${var.bootstrapscript}'))"]
  }

  provisioner "windows-restart" {
  }

  provisioner "powershell" {
    elevated_password = ""
    elevated_user     = "SYSTEM"
    inline            = ["Invoke-Expression ((New-Object -TypeName net.webclient).DownloadString('${var.bootstrapscript}'))"]
  }

  provisioner "windows-restart" {
  }

  provisioner "powershell" {
    elevated_password = ""
    elevated_user     = "SYSTEM"
    inline            = ["Invoke-Expression ((New-Object -TypeName net.webclient).DownloadString('${var.bootstrapscript}'))"]
  }

  provisioner "windows-restart" {
  }

  provisioner "powershell" {
    elevated_password = ""
    elevated_user     = "SYSTEM"
    inline            = ["Invoke-Expression ((New-Object -TypeName net.webclient).DownloadString('${var.bootstrapscript}'))"]
  }

  provisioner "powershell" {
    inline = ["$stage =  ((Get-ItemProperty -path HKLM:\\SOFTWARE\\Mozilla\\ronin_puppet).bootstrap_stage)", "If ($stage -ne 'complete') { exit 2}", "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Mozilla\\ronin_puppet' -name hand_off_ready -type  string -value yes", "Write-Output ' -> Waiting for GA Service (RdAgent) to start ...'", "while ((Get-Service RdAgent).Status -ne 'Running') { Start-Sleep -s 5 }", "Write-Output ' -> Waiting for GA Service (WindowsAzureTelemetryService) to start ...'", "while ((Get-Service WindowsAzureTelemetryService) -and ((Get-Service WindowsAzureTelemetryService).Status -ne 'Running')) { Start-Sleep -s 5 }", "Write-Output ' -> Waiting for GA Service (WindowsAzureGuestAgent) to start ...'", "while ((Get-Service WindowsAzureGuestAgent).Status -ne 'Running') { Start-Sleep -s 5 }", "Write-Output ' -> Sysprepping VM ...'", "if ( Test-Path $Env:SystemRoot\\system32\\Sysprep\\unattend.xml ) {Remove-Item $Env:SystemRoot\\system32\\Sysprep\\unattend.xml -Force}", "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit", "while ($true) {start-sleep -s 10 ;$imageState = (Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State).ImageState; Write-Output $imageState; if ($imageState -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { break }}", "Write-Output ' -> Sysprep complete ...'"]
  }

}
