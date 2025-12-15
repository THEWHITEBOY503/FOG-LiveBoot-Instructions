#!/bin/bash

# CONFIG
VM_DOMAIN="ubuntu24.04-NFS" # Put the name of your VM here. This is for the VM running check
NBD_DEV="/dev/nbd0"
NFS_MOUNT="/var/www/html/os/kubuntu" # Change this to your NFS mount point if needed
RAM_DIR="/var/www/html/os/kubuntu-ram" # Change this to your RAM boot mount point if needed 

function set_production() {
    echo "--- SWITCHING TO PRODUCTION MODE ---"
    # 1. Ensure VM is off
    if sudo virsh list --name --state-running | grep -q "^$VM_DOMAIN$"; then
        echo "Error: VM is still running. Shut it down first."
        exit 1
    fi

    # 2. Connect NBD and Mount NFS
    echo "Connecting VM disk for NFS..."
    sudo modprobe nbd max_part=16
    # Added --persistent to prevent timeouts and -f qcow2 to be explicit
    sudo qemu-nbd --connect=$NBD_DEV --persistent -f qcow2 /var/lib/libvirt/images/ubuntu24.04-NFS.qcow2 # Change to your VMs hard drive image path
    sleep 2
    sudo mount ${NBD_DEV}p1 $NFS_MOUNT
    
    # 3. Refresh Exports
    sudo exportfs -r
    
    echo "Done. NFS and RAM services are BOTH ACTIVE."
}

function set_maintenance() {
    echo "--- SWITCHING TO MAINTENANCE MODE ---"
    # 1. Unmount NFS
    sudo umount $NFS_MOUNT 2>/dev/null
    
    # 2. Disconnect Disk
    sudo qemu-nbd --disconnect $NBD_DEV 2>/dev/null
    
    echo "Done. NFS is offline. RAM boot is still online."
    echo "You may now start your VM to make changes."
}

# Simple Menu
PS3='Please enter your choice: '
options=("Enable Production (Serve Clients)" "Enable Maintenance (Edit VM)" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "Enable Production (Serve Clients)")
            set_production
            break
            ;;
        "Enable Maintenance (Edit VM)")
            set_maintenance
            break
            ;;
        "Quit")
            break
            ;;
        *) echo "invalid option $REPLY";;
    esac
done
