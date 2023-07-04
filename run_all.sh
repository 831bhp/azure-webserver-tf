#!/bin/bash

set -euE

export LOG_FILE="${LOG_FILE:-/var/log/azure-webserver-tf/logs}"
mkdir -p $(dirname "${LOG_FILE}")

function trap_handler {
    echo -e "\n***** ERROR! *****"
    echo "For detailed error logs, please see: $LOG_FILE"
    echo "******************"
}
trap trap_handler ERR


function usage {
    echo "\
    
    Usage:
        $0
           {
            --client-id <The Client ID which should be used for authentication>
            --client-secret <The client secret>
            --tenant-id <Your Azure account tenant ID>
            --subscription-id <Your Azure account subscription ID>
           }
    Command Args:
        --client-id {client-id} --client-secret {client-secret} --tenant-id {tenant-secret} --subscription-id {subscription-id}"
}

function die {
    echo >&2 "$@"
    usage
    exit 1
}

if [[ $# -eq 0 ]]; then
    die "ERROR: Please provide Azure subscription id, tenant id, client id and client secret"
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) die "Please check usage"
        ;;
        --client-id)
            [ -z "$2" ] && die "Error: Client ID not provided";
            client_id="$2"
            shift 2
        ;;
        --client-secret)
            [ -z "$2" ] && die "Error: Client secret not provided";
            client_secret="$2"
            shift 2
        ;;
        --tenant-id)
            [ -z "$2" ] && die "Error: Tenant ID not provided";
            tenant_id="$2"
            shift 2
        ;;
        --subscription-id)
            [ -z "$2" ] && die "Error: subscription ID not provided";
            sub_id="$2"
            shift 2
        ;;
        *) die "Invalid option provided $1";;
    esac
done

# Install terraform
if [[ -f "/etc/os-release" ]]; then
  if [[ ! `command -v terraform` ]];then
    echo -e "****** Installing Terraform on Ubuntu ******\n" | sudo tee -a ${LOG_FILE}
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg | sudo tee -a ${LOG_FILE}
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list | sudo tee -a ${LOG_FILE}
    sudo apt update && sudo apt install terraform | sudo tee -a ${LOG_FILE}
  fi
else
  die "OS is not Ubuntu, please run the script on Ubuntu"
fi

# Run terraform to provision resources on Azure
echo -e "\n****** Running terraform to provision Azure resources ******" | sudo tee -a ${LOG_FILE}
cd ./terraform

echo -e "\n****** Running terraform init ******" | sudo tee -a ${LOG_FILE}
sudo terraform init | sudo tee -a ${LOG_FILE}

echo -e "\n****** Running terraform plan ******" | sudo tee -a ${LOG_FILE}
sudo terraform plan -out main.tfplan -var client_id="$client_id" -var client_secret="$client_secret" -var tenant_id="$tenant_id" -var subscription_id="$sub_id" | sudo tee -a ${LOG_FILE}
echo "Do you want to proceed? (y/n):"
read proceed
if [[ $proceed == "n" ]]; then exit 0; fi

echo -e "\n****** Running terraform apply ******" | sudo tee -a ${LOG_FILE}
sudo terraform apply main.tfplan | sudo tee -a ${LOG_FILE}
