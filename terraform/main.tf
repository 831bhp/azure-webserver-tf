terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.55.0"
    }
  }
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

# Create NSG to allow inbound port 8080 & 22
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
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # security_rule {
  #   name                       = "allowInbound-80"
  #   priority                   = 101
  #   direction                  = "Inbound"
  #   access                     = "Allow"
  #   protocol                   = "Tcp"
  #   source_port_range          = "*"
  #   destination_port_range     = "80"
  #   source_address_prefix      = "*"
  #   destination_address_prefix = "*"
  # }
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
  allocation_method   = "Dynamic"
}

# Create NIC
resource "azurerm_network_interface" "webserver_nic" {
  name                = "${var.prefix}-nic"
  resource_group_name = azurerm_resource_group.webserver_rg.name
  location            = azurerm_resource_group.webserver_rg.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.webserver_public_ip.id
  }
  depends_on = [
    azurerm_public_ip.webserver_public_ip
  ]
}

# Create Load balancer
resource "azurerm_lb" "webserver_app_balancer" {
  name                = "webserver-app-balancer"
  location            = azurerm_resource_group.webserver_rg.location
  resource_group_name = azurerm_resource_group.webserver_rg.name
  sku="Standard"
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
  resource_group_name = azurerm_resource_group.webserver_rg.name
  loadbalancer_id     = azurerm_lb.webserver_app_balancer.id
  name                = "probeA"
  port                = 8080
  protocol            = "Http"
  request_path        = "/Health"
  depends_on=[
    azurerm_lb.webserver_app_balancer
  ]
}

# Defin Load Balancing Rule
resource "azurerm_lb_rule" "RuleA" {
  resource_group_name            = azurerm_resource_group.webserver_rg.name
  loadbalancer_id                = azurerm_lb.webserver_app_balancer.id
  name                           = "RuleA"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend-ip"
  backend_address_pool_ids = [ azurerm_lb_backend_address_pool.webserver_vmsspool.id ]
  depends_on=[
    azurerm_lb.webserver_app_balancer
  ]
}

# Create VMSS
resource "azurerm_virtual_machine_scale_set" "webserver_scaleset" {
  name                = "webserver-scaleset"
  location            = azurerm_resource_group.webserver_rg.location
  resource_group_name = azurerm_resource_group.webserver_rg.name

  # automatic rolling upgrade
  automatic_os_upgrade = true
  upgrade_policy_mode  = "Rolling"

  rolling_upgrade_policy {
    max_batch_instance_percent              = 20
    max_unhealthy_instance_percent          = 20
    max_unhealthy_upgraded_instance_percent = 5
    pause_time_between_batches              = "PT0S"
  }

  # required when using rolling upgrade policy
  health_probe_id = azurerm_lb_probe.ProbeA.id

  sku {
    name     = var.vm_size
    tier     = "Standard"
    capacity = 2
  }

  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = var.client_id
    version   = "latest"
  }

  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_profile_data_disk {
    lun           = 0
    caching       = "ReadWrite"
    create_option = "Empty"
    disk_size_gb  = 10
  }

  os_profile {
    computer_name_prefix = "apache_webserver"
    admin_username       = var.user
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/${var.user}/.ssh/authorized_keys"
      key_data = file("~/.ssh/id_rsa.pub")
    }
  }

  network_profile {
    name    = "networkprofile"
    primary = true

    ip_configuration {
      name                                   = "IPConfiguration"
      primary                                = true
      subnet_id                              = azurerm_subnet.internal.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.webserver_vmsspool.id]
    }
  }
  depends_on=[
      azurerm_lb_backend_address_pool.webserver_vmsspool
  ]
}

# Create SA & upload config_webserver.sh script
resource "azurerm_storage_account" "webserver_sa" {
  name                     = "webserver-sa"
  resource_group_name      = azurerm_resource_group.webserver_rg.name
  location                 = azurerm_resource_group.webserver_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_blob_public_access = true
}

resource "azurerm_storage_container" "webserver_data" {
  name                  = "webserver-data"
  storage_account_name  = "webserver-sa"
  container_access_type = "blob"
  depends_on=[
    azurerm_storage_account.webserver_sa
  ]
}

# Upload config_webserver.sh script as a blob to the Azure storage account
resource "azurerm_storage_blob" "webserver_install" {
  name                   = "webserver-install"
  storage_account_name   = "webserver-sa"
  storage_container_name = "webserver_data"
  type                   = "Block"
  source                 = "config_webserver.sh"
  depends_on             = [azurerm_storage_container.webserver_data]
}

# Apply the custom script extension on the vmss
resource "azurerm_virtual_machine_scale_set_extension" "webserver_extension" {
  name                 = "webserver-extension"
  virtual_machine_scale_set_id   = azurerm_windows_virtual_machine_scale_set.webserver_scaleset.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"
  depends_on = [
    azurerm_storage_blob.webserver_install
  ]
  settings = <<SETTINGS
    {
        "fileUris": ["https://${azurerm_storage_account.appstore.name}.blob.core.windows.net/webserver_data/config_webserver.sh"],
          "commandToExecute": "sh config_webserver.sh"
    }
SETTINGS
}
