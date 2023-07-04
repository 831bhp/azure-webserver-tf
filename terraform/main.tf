terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.55.0"
    }
  }
}

locals {
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC/xkcU8ATJvV0JVgJP0e8OQkdOp7WCsHeRsx+xTiYVDquWkz3hAdysAp4/IKbzxTDIPoqS1hrHVRUwBAYLO6p0Q05LHl1mjTDnpps++zEWgKh5KwhZuhinq6Vhogn9ri/1lmcJGTw/JMSlTAPF3CGnRc9QJP6qGZRJrO3yZUo4iX/bG4eRseiTnFPzR53rcNPvTzeIuNptkTEBgdz+SZbK4jDSGSJLA53b8LrWoZJZ4D0Ki4ktr/NV2GVNgykOhOVemmjr0ko8XuoS7afju6RPobMPvkuGFChLvp07Ga0b+YgMvWeJuq5imgjNA3Wp17VnMRX5zPhjMl+rVVNuDXemcxbnlbmUaWQnlP61nHiouUoyVebZWXs18ZHD8UnN1a6gzgH99HocdihZH0yjALywVrvh9u55DavVcPEZansJXEx9qrESltHB31RaYaobA9BO0C0fmCEfwh1bLC7k0ybd+KyFmHr9YGPBGOoXDlNkDVDeF0OqO23xuAcNuQ/eBXc= pritam@buildvm"
}

# Setup Azure Provider and config access parameters through variables 
provider "azurerm" {
  # Configuration options
  features {}

  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}

# Resource Group
resource "azurerm_resource_group" "webserver_rg" {
  name     = "${var.prefix}-rg"
  location = var.location
}

# Create VPN 
resource "azurerm_virtual_network" "webserver_vpn" {
  name                = "${var.prefix}-vpn"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.webserver_rg.location
  resource_group_name = azurerm_resource_group.webserver_rg.name
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.webserver_rg.name
  virtual_network_name = azurerm_virtual_network.webserver_vpn.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Create NSG to allow inbound port 8080 & 22 to the VMSS VMs
resource "azurerm_network_security_group" "webserver_nsg" {
  name                = "${var.prefix}-nsg"
  location            = azurerm_resource_group.webserver_rg.location
  resource_group_name = azurerm_resource_group.webserver_rg.name

  security_rule {
    name                       = "allowInbound-8080"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80" #TODO: Change this to 8080
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allowInbound-22"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

# Bind/associate the NSG to internal subnet
resource "azurerm_subnet_network_security_group_association" "webserver_nsg-associate" {
  subnet_id                 = azurerm_subnet.internal.id
  network_security_group_id = azurerm_network_security_group.webserver_nsg.id
}

# Create Public IP
resource "azurerm_public_ip" "webserver_public_ip" {
  name                = "${var.prefix}-public-ip"
  location            = azurerm_resource_group.webserver_rg.location
  resource_group_name = azurerm_resource_group.webserver_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create Load balancer
resource "azurerm_lb" "webserver_app_balancer" {
  name                = "webserver-app-balancer"
  location            = azurerm_resource_group.webserver_rg.location
  resource_group_name = azurerm_resource_group.webserver_rg.name
  sku = "Standard"
  sku_tier = "Regional"
  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.webserver_public_ip.id
  }

  depends_on=[
    azurerm_public_ip.webserver_public_ip
  ]
}

# Define backend pool
resource "azurerm_lb_backend_address_pool" "webserver_vmsspool" {
  loadbalancer_id = azurerm_lb.webserver_app_balancer.id
  name            = "webserver_vmsspool"
  depends_on=[
    azurerm_lb.webserver_app_balancer
  ]
}

# define Health Probe
resource "azurerm_lb_probe" "ProbeA" {
  loadbalancer_id     = azurerm_lb.webserver_app_balancer.id
  name                = "probeA"
  port                = 80 #TODO: Change this to 8080
  protocol            = "Http"
  request_path        = "/Health"
  depends_on=[
    azurerm_lb.webserver_app_balancer
  ]
}

# Defin Load Balancing Rule
resource "azurerm_lb_rule" "RuleA" {
  loadbalancer_id                = azurerm_lb.webserver_app_balancer.id
  name                           = "RuleA"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80 #TODO: Change this to 8080
  frontend_ip_configuration_name = "frontend-ip"
  backend_address_pool_ids = [ azurerm_lb_backend_address_pool.webserver_vmsspool.id ]
  depends_on=[
    azurerm_lb.webserver_app_balancer
  ]
}

resource "azurerm_linux_virtual_machine_scale_set" "webserver_scaleset" {
  name                = "webserver-scaleset"
  resource_group_name = azurerm_resource_group.webserver_rg.name
  location            = azurerm_resource_group.webserver_rg.location
  sku                 = var.vm_size
  instances           = 2
  admin_username      = var.user

  admin_ssh_key {
    username   = var.user
    public_key = local.public_key
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = var.ubuntu_sku
    version   = var.ubuntu_version

  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "webserver-nic"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.internal.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.webserver_vmsspool.id]
    }
  }
  depends_on=[
      azurerm_lb_backend_address_pool.webserver_vmsspool
  ]
}


# Create SA & upload config_webserver.sh script
resource "azurerm_storage_account" "webserver_sa" {
  name                     = "webserversa310583"
  resource_group_name      = azurerm_resource_group.webserver_rg.name
  location                 = azurerm_resource_group.webserver_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "webserver_data" {
  name                  = "webserverdata"
  storage_account_name  = "webserversa310583"
  container_access_type = "blob"
  depends_on=[
    azurerm_storage_account.webserver_sa
  ]
}

# Upload config_webserver.sh script as a blob to the Azure storage account
resource "azurerm_storage_blob" "webserver_install" {
  name                   = "config_webserver.sh"
  storage_account_name   = "webserversa310583"
  storage_container_name = "webserverdata"
  type                   = "Block"
  source                 = "config_webserver.sh"
  depends_on             = [azurerm_storage_container.webserver_data]
}

# Apply the custom script extension on the vmss
resource "azurerm_virtual_machine_scale_set_extension" "webserver_extension" {
  name                 = "webserver-extension"
  virtual_machine_scale_set_id   = azurerm_linux_virtual_machine_scale_set.webserver_scaleset.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  depends_on = [
    azurerm_linux_virtual_machine_scale_set.webserver_scaleset,
    azurerm_storage_blob.webserver_install
  ]
  settings = <<SETTINGS
    {
        "fileUris": ["https://${azurerm_storage_account.webserver_sa.name}.blob.core.windows.net/webserverdata/config_webserver.sh"],
        "commandToExecute": "sh config_webserver.sh"
    }
SETTINGS
}

# Create a jumpVM to troubleshoot the VMSS extention issue
resource "azurerm_public_ip" "jumpvm_public_ip" {
  name                = "jumpvm-public-ip"
  location            = azurerm_resource_group.webserver_rg.location
  resource_group_name = azurerm_resource_group.webserver_rg.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
}
resource "azurerm_network_interface" "jumpvm_nic" {
  name                = "jumpvm-nic"
  location            = azurerm_resource_group.webserver_rg.location
  resource_group_name = azurerm_resource_group.webserver_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jumpvm_public_ip.id
  }
  depends_on = [azurerm_public_ip.jumpvm_public_ip]
}

resource "azurerm_linux_virtual_machine" "jumpVM" {
  name                = "jumpVM"
  resource_group_name = azurerm_resource_group.webserver_rg.name
  location            = azurerm_resource_group.webserver_rg.location
  size                = var.vm_size
  admin_username      = var.user
  network_interface_ids = [
    azurerm_network_interface.jumpvm_nic.id
  ]

  admin_ssh_key {
    username   = var.user
    public_key = local.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = var.ubuntu_sku
    version   = var.ubuntu_version
  }
  depends_on = [azurerm_network_interface.jumpvm_nic]
}

