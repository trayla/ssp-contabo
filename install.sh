#!/bin/bash

showHeader () {
  if [ "$1" == 1 ]; then
    echo -e "\033[0;36m"
    echo -e "######################################################################################"
    echo -e "### $2"
    echo -e "######################################################################################"
    echo -e "\033[0m"
  elif [ "$1" == 2 ]; then
    echo -e "\033[0;36m"
    echo -e "### $2"
    echo -e "\033[0m"
  elif [ "$1" == 3 ]; then
    echo -e "\033[0;35m $2 \033[0m"
  fi
}

if ! command -v curl &> /dev/null
then
  apt install -y curl
fi

if ! command -v jq &> /dev/null
then
  apt install -y jq
fi

# Install the Contabo API client
rm -Rf /tmp/cntb-client.tar.gz
rm -Rf /tmp/cntb-client
curl --silent https://github.com/contabo/cntb/releases/download/v1.2.0/cntb_v1.2.0_Linux_x86_64.tar.gz -L -o /tmp/cntb-client.tar.gz
mkdir -p /tmp/cntb-client
tar zxf /tmp/cntb-client.tar.gz -C /tmp/cntb-client

# Show all available instances
showHeader 1 "Show all available instances"
/tmp/cntb-client/cntb get instances -o json | jq -r '(.[] | [.imageId,.name,.osType]) | @tsv' | column -t
FILE_CONFIG=config.json
if [ ! -f "$FILE_CONFIG" ]; then
  echo "$FILE_CONFIG does not exist."
  exit 1
fi

# Process the Contabo login
clientId=`cat config.json | jq -r -c '.clientId'`
clientSecret=`cat config.json | jq -r -c '.clientSecret'`
apiUser=`cat config.json | jq -r -c '.apiUser'`
apiPassword=`cat config.json | jq -r -c '.apiPassword'`
/tmp/cntb-client/cntb config set-credentials \
  --oauth2-clientid="$clientId" \
  --oauth2-client-secret="$clientSecret" \
  --oauth2-user="$apiUser" \
  --oauth2-password="$apiPassword"

# Setup the passwords
showHeader 1 "Setup stored secrets (passwords and SSH keys)"
instancePassword=`cat config.json | jq -r -c '.instancePassword'`
echo "Removing all available secrets ..."
for secretId in `/tmp/cntb-client/cntb get secrets -o json | jq -r '(.[] | [.secretId]) | @tsv'`; do
  /tmp/cntb-client/cntb delete secret $secretId
  echo "Secret removed $secretId"
done
secretIdDefaultPassword=`/tmp/cntb-client/cntb create secret --name "default" --value "$instancePassword" --type "password"`
echo "Default password created: $secretIdDefaultPassword"
publicSshkey=`cat ~/.ssh/id_rsa.pub`
secretIdDefaultSshkey=`/tmp/cntb-client/cntb create secret --name "default" --value "$publicSshkey" --type "ssh"`
echo "Default SSH key created: $secretIdDefaultSshkey"
secretSshkeys=`/tmp/cntb-client/cntb get secrets -t ssh -o json | jq -r '(.[] | [.secretId]) | @tsv' | paste -s -d, -`
echo "List of available SSH keys: $secretSshkeys"

# Show all available images
showHeader 1 "Show all available images"
/tmp/cntb-client/cntb get images -o json | jq -r '(.[] | [.imageId,.name,.osType]) | @tsv' | column -t | grep ubuntu-20.04
imageId=`/tmp/cntb-client/cntb get images -o json | jq -r '(.[] | [.imageId,.name]) | @tsv' | grep ubuntu-20.04 | head -n 1| cut -f 1`
echo "Selected image: $imageId"

# Process the OS installation
showHeader 1 "Process the OS installation"
for instanceJson in `cat $FILE_CONFIG | jq -r -c '.hosts[]'`; do
  instanceId=`echo $instanceJson | jq -r '.instanceId'`
  hostname=`echo $instanceJson | jq -r '.hostname'`

  # Reinstall a virtual machine
  /tmp/cntb-client/cntb reinstall instance "$instanceId" --imageId "$imageId" --sshKeys "$secretSshkeys" --rootPassword "$secretIdDefaultPassword"
  echo "Reinstallation started for instance $instanceId"
done

echo "Waiting 5 minutes for the installation of all instances" && sleep 60
echo "Waiting 4 minutes for the installation of all instances" && sleep 60
echo "Waiting 3 minutes for the installation of all instances" && sleep 60
echo "Waiting 2 minutes for the installation of all instances" && sleep 60
echo "Waiting 1 minutes for the installation of all instances" && sleep 60

# Restart all available instances
showHeader 1 "Restart all available instances"
/tmp/cntb-client/cntb get instances -o json | jq -r '(.[] | [.imageId,.name,.osType]) | @tsv' | column -t
for instanceJson in `cat $FILE_CONFIG | jq -r -c '.hosts[]'`; do
  instanceId=`echo $instanceJson | jq -r '.instanceId'`

  # Reinstall a virtual machine
  /tmp/cntb-client/cntb restart instance "$instanceId"
  echo "Restart requested for instance $instanceId"
done

echo "Waiting 3 minutes for the reboot of all instances" && sleep 60
echo "Waiting 2 minutes for the reboot of all instances" && sleep 60
echo "Waiting 1 minutes for the reboot of all instances" && sleep 60

# Process a basic configuration of each instance
showHeader 1 "Process a basic configuration of each instance"
for instanceJson in `cat $FILE_CONFIG | jq -r -c '.hosts[]'`; do
  instanceId=`echo $instanceJson | jq -r '.instanceId'`
  hostname=`echo $instanceJson | jq -r '.hostname'`

  showHeader 2 "Processing instance $instanceId, $hostname"
  instanceIpaddrExt=`/tmp/cntb-client/cntb get instance $instanceId -o json | jq -r '.[].ipConfig.v4.ip'`
  echo "External IP address: $instanceIpaddrExt"
  instanceIpaddrInt=`echo $instanceJson | jq -r '.internalIp'`
  echo "Internal IP address: $instanceIpaddrInt"

  # Update the display name
  echo "Update the Contabo display name: $hostname"
  /tmp/cntb-client/cntb update instance $instanceId --displayName "$hostname"

  # Ensure the instance is a known SSH host
  touch /root/.ssh/known_hosts
  ssh-keygen -f "/root/.ssh/known_hosts" -R $instanceIpaddrExt
  sshKey=`ssh-keyscan $instanceIpaddrExt 2> /dev/null` && echo $sshKey >> /root/.ssh/known_hosts

  # Reboot the instance
  ssh admin@$instanceIpaddrExt "sudo apt update && sudo apt upgrade -y && sudo apt install -y net-tools"

  # Disable specific cloud init updates
  echo "Disable specific cloud init updates"
  ssh admin@$instanceIpaddrExt "sudo sed -i '/ - set_hostname/d' /etc/cloud/cloud.cfg"
  ssh admin@$instanceIpaddrExt "sudo sed -i '/ - update_hostname/d' /etc/cloud/cloud.cfg"
  ssh admin@$instanceIpaddrExt "sudo sed -i '/ - update_etc_hosts/d' /etc/cloud/cloud.cfg"

  # Add entries to the /etc/hosts in each instance
  echo "Add entries to the /etc/hosts"
  for instanceJson1 in `cat $FILE_CONFIG | jq -r -c '.hosts[]'`; do
    instanceId1=`echo $instanceJson1 | jq -r '.instanceId'`
    hostname1=`echo $instanceJson1 | jq -r '.hostname'`
    instanceIpaddrInt1=`echo $instanceJson1 | jq -r '.internalIp'`
    ssh admin@$instanceIpaddrExt "echo '$instanceIpaddrInt1 $hostname1' | sudo tee -a /etc/hosts"
  done

  # Set the hostname
  echo "Set the hostname to $hostname"
  ssh admin@$instanceIpaddrExt "sudo hostnamectl set-hostname $hostname"

  # Generate a SSH key pair
  ssh admin@$instanceIpaddrExt "ssh-keygen -b 4096 -t rsa -f ~/.ssh/id_rsa -q -N ''"
  if [ "$hostname" == "console" ]; then
    consoleIpExt=$instanceIpaddrExt
    consoleIpInt=$instanceIpaddrInt
    consoleSshPubkey=`ssh admin@$instanceIpaddrExt "cat ~/.ssh/id_rsa.pub"`
    echo "Console SSH key:"
    echo "$consoleSshPubkey"
  fi

  # Reboot the instance
  echo "Reboot the instance"
  ssh admin@$instanceIpaddrExt "sudo reboot"
done

echo "Waiting 3 minutes for the reboot of all instances" && sleep 60
echo "Waiting 2 minutes for the reboot of all instances" && sleep 60
echo "Waiting 1 minutes for the reboot of all instances" && sleep 60

# Configure console access to each instance
showHeader 1 "Configure console access to each instance"
for instanceJson in `cat $FILE_CONFIG | jq -r -c '.hosts[]'`; do
  instanceId=`echo $instanceJson | jq -r '.instanceId'`
  echo ""
  echo "###### Processing instance $instanceId"
  hostname=`echo $instanceJson | jq -r '.hostname'`
  echo "Hostname: $hostname"
  instanceIpaddrExt=`/tmp/cntb-client/cntb get instance $instanceId -o json | jq -r '.[].ipConfig.v4.ip'`
  echo "External IP address: $instanceIpaddrExt"
  instanceIpaddrInt=`echo $instanceJson | jq -r '.internalIp'`
  echo "Internal IP address: $instanceIpaddrInt"

  echo "Add public key of console to the authroized keys"
  ssh admin@$instanceIpaddrExt "echo $consoleSshPubkey >> ~/.ssh/authorized_keys"

  echo "Add IP address of the current instance to known hosts at console"
  ssh admin@$consoleIpExt "ssh-keyscan -H $instanceIpaddrInt >> ~/.ssh/known_hosts"

  echo "Add hostname of the current instance to known hosts at console"
  ssh admin@$consoleIpExt "ssh-keyscan -H $hostname >> ~/.ssh/known_hosts"
done

# Process instance specfic configuration
showHeader 1 "Process instance specfic configuration"
for instanceJson in `cat $FILE_CONFIG | jq -r -c '.hosts[]'`; do
  instanceId=`echo $instanceJson | jq -r '.instanceId'`
  hostname=`echo $instanceJson | jq -r '.hostname'`

  showHeader 2 "Processing instance $instanceId, $hostname"

  instanceIpaddrExt=`/tmp/cntb-client/cntb get instance $instanceId -o json | jq -r '.[].ipConfig.v4.ip'`
  echo "External IP address: $instanceIpaddrExt"
  instanceIpaddrInt=`echo $instanceJson | jq -r '.internalIp'`
  echo "Internal IP address: $instanceIpaddrInt"
done

# Enable the firewall on each instance
showHeader 1 "Enable the firewall on each instance"
for instanceJson in `cat $FILE_CONFIG | jq -r -c '.hosts[]'`; do
  instanceId=`echo $instanceJson | jq -r '.instanceId'`
  hostname=`echo $instanceJson | jq -r '.hostname'`
  role=`echo $instanceJson | jq -r '.role'`

  showHeader 2 "Process the instance $instanceId, $hostname"

  instanceIpaddrExt=`/tmp/cntb-client/cntb get instance $instanceId -o json | jq -r '.[].ipConfig.v4.ip'`
  echo "External IP address: $instanceIpaddrExt"
  instanceIpaddrInt=`echo $instanceJson | jq -r '.internalIp'`
  echo "Internal IP address: $instanceIpaddrInt"

  ssh admin@$instanceIpaddrExt "sudo ufw default deny incoming"
  ssh admin@$instanceIpaddrExt "sudo ufw default allow outgoing"
  ssh admin@$instanceIpaddrExt "sudo ufw allow 22"
  ssh admin@$instanceIpaddrExt "sudo ufw allow in on eth1 to any"

  if [ "$role" == "kubeworker" ]; then
    ssh admin@$instanceIpaddrExt "sudo ufw allow in on eth0 to any port 80"
    ssh admin@$instanceIpaddrExt "sudo ufw allow in on eth0 to any port 443"
  fi

  ssh admin@$instanceIpaddrExt "sudo ufw --force enable"
done

# Process instance specific configurations
showHeader 1 "Process instance specific configurations"
for instanceJson in `cat $FILE_CONFIG | jq -r -c '.hosts[]'`; do
  instanceId=`echo $instanceJson | jq -r '.instanceId'`
  hostname=`echo $instanceJson | jq -r '.hostname'`
  role=`echo $instanceJson | jq -r '.role'`

  showHeader 2 "Process the instance $instanceId, $hostname"

  instanceIpaddrExt=`/tmp/cntb-client/cntb get instance $instanceId -o json | jq -r '.[].ipConfig.v4.ip'`
  echo "External IP address: $instanceIpaddrExt"
  instanceIpaddrInt=`echo $instanceJson | jq -r '.internalIp'`
  echo "Internal IP address: $instanceIpaddrInt"

  if [ "$hostname" == "console" ]; then
    ssh admin@$instanceIpaddrExt "sudo mkdir -p /opt/mgmt/top && sudo chown -R admin:admin /opt/mgmt"
    ssh admin@$instanceIpaddrExt "git clone https://github.com/trayla/top.git /opt/mgmt/top"
    ssh admin@$instanceIpaddrExt "cp /opt/mgmt/top/values-default.yaml /opt/mgmt/values-top.yaml"
  elif [ "$hostname" == "mongodb" ]; then
    ssh admin@$instanceIpaddrExt "wget -qO - https://www.mongodb.org/static/pgp/server-5.0.asc | sudo apt-key add -"
    ssh admin@$instanceIpaddrExt "echo \"deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/5.0 multiverse\" | sudo tee /etc/apt/sources.list.d/mongodb-org-5.0.list"
    ssh admin@$instanceIpaddrExt "sudo apt-get update"
    ssh admin@$instanceIpaddrExt "sudo apt-get install -y mongodb-org"
    ssh admin@$instanceIpaddrExt "sudo systemctl enable mongod"
    ssh admin@$instanceIpaddrExt "sudo systemctl start mongod"
  fi
done
