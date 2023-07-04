# Create a webserver on Ubuntu VMSS behind the Azure load balancer  

# High level architecture  
This repository uses Terraform to provision the Linux VMSS on the Azure cloud. The Apache2 is then provisioned using Saltstack as SCM.    
Using VMSS extension feature the shell script config_webserver.sh is run on the VMs to install and configure Saltstack, Salt is installed with single node configuration (salt-call)  

Reason for using Salt:  
Salt can be used to do the SCM of the Apache2 server, the packages can be easily updated using salt formulae. 
   

# Steps to install  
## Prerequisites  
1. Azure subscription (Currently only Azure is supported)  
2. Azure object Identity already created with following details:  
   - Client id  
   - Client secret  
   - Tenant ID  
   - Subscription ID  
3. Linux VM (Ubuntu 18.04), it will be provisioned automatically.  

1. Clone the repo:  
   ```
   git clone https://github.com/831bhp/azure-webserver-tf.git  
   cd azure-webserver-tf
   ```  
2. Run the master script, that will run everything and provide the IP address of the provisioned VM at the end  
   ```
   bash sudo ./run_all.sh --client-id "e16dxxx-xxxx-xxxx-8441-3211047xxxxx"\
                        --client-secret "igX8Q~xxxxxxxxxxxxxxxxxxxxmWnVrDjrd4TcfG"\
                        --tenant-id "5938xxxx-xxxx-xxxx-x45x-xxx7254f9dxx"\
                         --subscription-id "xxxxxxx6-x1bx-x2bx-xxxf-f6xxxxxx18xx"
   .
   .
   .
   
   load_balancer_public_ip_address = "http://20.219.252.227/"
   resource_group_name = "webserver-rg"
   ```

3. If everything works fine, you will see following on the webpage:  
<img width="1228" alt="Screenshot 2023-07-04 at 11 09 18 PM" src="https://github.com/831bhp/azure-webserver-tf/assets/99785311/378ab43b-366f-4bbb-8e98-de06cc2da596">
