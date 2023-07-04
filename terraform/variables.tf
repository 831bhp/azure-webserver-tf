variable "prefix" {
  description = "The prefix which should be used for all resources in this example"
  default = "mediawiki"
}

variable "location" {
  description = "The Azure Region in which all resources in this example should be created."
  default = "centralindia"
}

variable "vm_size" {
  description = "VM size"
  default = "Standard_B2s"
}

variable "ubuntu_version" {
  default = "18.04-LTS"
}

variable "storage_account_type" {
  default = "Standard_LRS"
}

variable "user" {
  default = "adminuser"
}

variable "tenant_id" {

}

variable "subscription_id" {

}

variable "client_id" {

}

variable "client_secret" {

}
