#!/bin/bash

# CONFIG
VM_DOMAIN="ubuntu24.04-NFS" # Put the name of your VM here. This is for the VM running check
NBD_DEV="/dev/nbd0"
NFS_MOUNT="/var/www/html/os/kubuntu" # Change this to your NFS mount point if needed
RAM_DIR="/var/www/html/os/kubuntu-ram" # Change this to your RAM boot mount point if needed 
IMAGE_PATH="/var/lib/libvirt/images/example.qcow2" # Change this to your VM disk image!!

function check_and_create_dirs() {
    echo "--- CHECKING DIRECTORIES ---"
    
    # Check NFS_MOUNT
    if [ ! -d "$NFS_MOUNT" ]; then
        echo "Directory $NFS_MOUNT does not exist. Creating it..."
        sudo mkdir -p "$NFS_MOUNT"
    else
        echo "Directory $NFS_MOUNT exists."
    fi

    # Check RAM_DIR
    if [ ! -d "$RAM_DIR" ]; then
        echo "Directory $RAM_DIR does not exist. Creating it..."
        sudo mkdir -p "$RAM_DIR"
    else
        echo "Directory $RAM_DIR exists."
    fi
    echo "------------------------------"
}

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
    
    sudo qemu-nbd --connect=$NBD_DEV --persistent -f qcow2 ${IMAGE_PATH} 
    sleep 2
    sudo mount ${NBD_DEV}p1 $NFS_MOUNT
    sleep 2
    
    # Identify the latest kernel and initrd (sort by version, take the last one)
    LATEST_VMLINUZ=$(ls -1 ${NFS_MOUNT}/boot/vmlinuz* | sort -V | tail -n 1)
    LATEST_INITRD=$(ls -1 ${NFS_MOUNT}/boot/initrd.img* | sort -V | tail -n 1)

    # Copy and rename them
    echo "Copying $LATEST_VMLINUZ to ${NFS_MOUNT}/vmlinuz..."
    sudo cp "$LATEST_VMLINUZ" "${NFS_MOUNT}/vmlinuz"

    echo "Copying $LATEST_INITRD to ${NFS_MOUNT}/initrd.img..."
    sudo cp "$LATEST_INITRD" "${NFS_MOUNT}/initrd.img"

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

function force_unmount() {
    echo "--- FORCE UNMOUNTING... ---"
    sudo umount -l $NFS_MOUNT
    sudo qemu-nbd --disconnect $NBD_DEV
}

# Simple Menu
PS3='Please enter your choice: '
options=("Enable Production (Serve Clients)" "Enable Maintenance (Edit VM)" "Force Unmount (Jaws of Life)" "Quit")
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
        "Force Unmount (Jaws of Life)")
            force_unmount
            break
            ;;
        "Quit")
            break
            ;;
        *) echo "invalid option $REPLY";;
    esac
done
