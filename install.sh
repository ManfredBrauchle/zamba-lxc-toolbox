#!/bin/bash

# This script will create and fire up a standard debian buster lxc container on your Proxmox VE.
# On a Proxmox cluster, the script will create the container on the local node, where it's executed.
# The container ID will be automatically assigned by increasing (+1) the highest number of
# existing LXC containers in your environment. If the assigned ID is already taken by a VM
# or no containers exist yet, the script falls back to the ID 100.

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

# IMPORTANT NOTE:
# Please adjust th settings in 'zamba.conf' to your needs before running the script

############### ZAMBA INSTALL SCRIPT ###############

if [[ "$2" == *".conf" ]]; then
  CONF=$2
else
  CONF=zamba.conf
fi

# Load configuration file
source $PWD/$CONF

OPTS=$(ls -d $PWD/src/*/ | grep -v __ | xargs basename -a)

if [ -z ${1+x} ]; then
  if [[ $opt in $OPTS ]]; then
    echo "Configuring '$opt' container..."
  else
    echo "Invalid option: '$opt', exiting..."
    exit 1
  fi
else
  select opt in $OPTS quit; do
    if [[ $opt in $OPTS ]]; then
      echo "Configuring '$opt' container..."
    elif [[ "$opt" == "quit" ]]; then
      echo "'quit' selected, exiting..."
      exit 0
    else
      echo "Invalid option, exiting..."
      exit 1
    fi
  done
fi

source $PWD/src/$opt/constants-service.conf

# CHeck is the newest template available, else download it.
DEB_LOC=$(pveam list $LXC_TEMPLATE_STORAGE | grep debian-10-standard | cut -d'_' -f2)
DEB_REP=$(pveam available --section system | grep debian-10-standard | cut -d'_' -f2)

if [[ $DEB_LOC == $DEB_REP ]];
then
  echo "Newest Version of Debian 10 Standard $DEP_REP exists.";
else
  echo "Will now download newest Debian 10 Standard $DEP_REP.";
  pveam download $LXC_TEMPLATE_STORAGE debian-10-standard_$DEB_REP\_amd64.tar.gz
fi

# Get next free LXC-number
LXC_LST=$( lxc-ls -1 | tail -1 )
LXC_CHK=$((LXC_LST+1));

if  [ $LXC_CHK -lt 100 ] || [ -f /etc/pve/qemu-server/$LXC_CHK.conf ]; then
  LXC_NBR=$(pvesh get /cluster/nextid);
else
  LXC_NBR=$LXC_CHK;
fi
echo "Will now create LXC Container $LXC_NBR!";

# Create the container
pct create $LXC_NBR -unprivileged $LXC_UNPRIVILEGED $LXC_TEMPLATE_STORAGE:vztmpl/debian-10-standard_$DEB_REP\_amd64.tar.gz -rootfs $LXC_ROOTFS_STORAGE:$LXC_ROOTFS_SIZE;
sleep 2;

# Check vlan configuration
if [[ $LXC_VLAN != "" ]];then
  VLAN=",tag=$LXC_VLAN"
else
 VLAN=""
fi
# Reconfigure conatiner
pct set $LXC_NBR -memory $LXC_MEM -swap $LXC_SWAP -hostname $LXC_HOSTNAME -onboot 1 -timezone $LXC_TIMEZONE -features nesting=$LXC_NESTING;
if [ $LXC_DHCP == true ]; then
 pct set $LXC_NBR -net0 name=eth0,bridge=$LXC_BRIDGE,ip=dhcp,type=veth$VLAN;
else
 pct set $LXC_NBR -net0 name=eth0,bridge=$LXC_BRIDGE,firewall=1,gw=$LXC_GW,ip=$LXC_IP,type=veth$VLAN -nameserver $LXC_DNS -searchdomain $LXC_DOMAIN;
fi
sleep 2

if [ $LXC_MP -gt 0 ]; then
  pct set $LXC_NBR -mp0 $LXC_SHAREFS_STORAGE:$LXC_SHAREFS_SIZE,mp=/$LXC_SHAREFS_MOUNTPOINT
fi
sleep 2;

PS3="Select the Server-Function: "

pct start $LXC_NBR;
sleep 5;
# Set the root password and key
echo -e "$LXC_PWD\n$LXC_PWD" | lxc-attach -n$LXC_NBR passwd;
lxc-attach -n$LXC_NBR mkdir -p /root/.ssh;
pct push $LXC_AUTHORIZED_KEY /root/.ssh/authorized_keys
pct push $LXC_NBR $PWD/src/sources.list /etc/apt/sources.list
pct push $LXC_NBR $PWD/$CONF /root/zamba.conf
pct push $LXC_NBR $PWD/src/constants.conf /root/constants.conf
pct push $LXC_NBR $PWD/src/lxc-base.sh /root/lxc-base.sh
pct push $LXC_NBR $PWD/src/$opt/install-service.sh /root/install-service.sh
pct push $LXC_NBR $PWD/src/$opt/constants-service.conf /root/constants-service.conf

echo "Installing basic container setup..."
pct push $LXC_NBR $PWD/src/lxc-base.sh /root/lxc-base.sh
echo "Install '$opt'!"
lxc-attach -n$LXC_NBR bash /root/install-service.sh

if [[ $opt == "zmb-ad" ]]; then
  pct stop $LXC_NBR
  pct set $LXC_NBR \-nameserver $(echo $LXC_IP | cut -d'/' -f 1)
  pct start $LXC_NBR
fi
