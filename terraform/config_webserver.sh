#!/bin/bash

# Install & configure Saltstack in local mode
# Install git and checkout this code from Github
# Run Salt highstate to install & configure Apache2

set -e

dir=$(pwd)

curl -L https://bootstrap.saltstack.com -o bootstrap_salt.sh
sudo sh bootstrap_salt.sh

sudo cp /etc/salt/minion /etc/salt/minion.bak
#sed -i 's/#file_client: local/file_client: local/g' /etc/salt/minion

sudo apt update && sudo apt install git

cd /opt && sudo git clone -b dev https://github.com/831bhp/azure-webserver-tf.git
sudo cp /opt/azure-webserver-tf/salt/files/minion /etc/salt/minion
sudo systemctl stop salt-minion
sudo salt-call --local test.ping
sudo salt-call --local state.highstate
