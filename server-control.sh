#!/bin/bash

# CONFIG
VM_DOMAIN="YOUR_VM_NAME" # Whatever the name of the VM is in virt-manager, if applicable. This is for the running check.
NBD_DEV="/dev/nbd0"  # Leave this unless you have something occupying it already
NFS_MOUNT="/var/www/html/os/kubuntu" # Default value is fine, or if you want you can change the 'kubuntu' part of the path
RAM_DIR="/var/www/html/os/kubuntu-ram" # Default value is fine, or if you want you can change the 'kubuntu-ram' part of the path
IMAGE_PATH="/var/lib/libvirt/images/example.qcow2" # CHANGE this to the path of your golden VM's hard drive image.

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

    # Check for casper
    if [ ! -d "$RAM_DIR/casper" ]; then
        echo "Directory $RAM_DIR/casper does not exist. Creating it..."
        sudo mkdir -p "$RAM_DIR/casper"
    else
        echo "Directory $RAM_DIR/casper exists."
    fi

    echo "------------------------------"
}

function mount_VM() {
    # Connect NBD and Mount NFS
    echo "Connecting VM disk for NFS..."
    sudo modprobe nbd max_part=16

    sudo qemu-nbd --connect=$NBD_DEV --persistent -f qcow2 "${IMAGE_PATH}"
    sleep 2
    sudo mount "${NBD_DEV}p1" "$NFS_MOUNT"
    sleep 2
}

function compress_ram_image() {
    echo "--- Starting RAM Image Builder ---"
    
    # Check if already mounted before trying to mount
    if ! mountpoint -q "$NFS_MOUNT"; then
        mount_VM
    fi

    # Copy Boot Files (Kernel needs to match the squashfs)
    echo "Copying Kernel and Initrd..."
    
    if [ -f "$NFS_MOUNT/boot/vmlinuz" ]; then
        sudo cp -L "$NFS_MOUNT/boot/vmlinuz" "$RAM_DIR/vmlinuz"
        sudo cp -L "$NFS_MOUNT/boot/initrd.img" "$RAM_DIR/initrd.img"
    else
        # Handle wildcard copies safely
        sudo cp "$NFS_MOUNT"/boot/vmlinuz* "$RAM_DIR/vmlinuz"
        sudo cp "$NFS_MOUNT"/boot/initrd.img* "$RAM_DIR/initrd.img"
    fi
    
    # Fix permissions so HTTP can read them
    sudo chmod 644 "$RAM_DIR/vmlinuz" "$RAM_DIR/initrd.img"

    # Compressing time
    echo "Compressing filesystem... (This will take time)"

    # Create the casper directory if missing
    sudo mkdir -p "$RAM_DIR/casper"

    # Remove old file (Target the CASPER folder)
    sudo rm -f "$RAM_DIR/casper/filesystem.squashfs"

    # Compress into the /casper/ folder
    sudo mksquashfs "$NFS_MOUNT" "$RAM_DIR/casper/filesystem.squashfs" -comp gzip -wildcards -e 'swapfile' 'var/cache/apt/archives/*' 'tmp/*'

    # Fix Permissions
    sudo chmod 644 "$RAM_DIR/casper/filesystem.squashfs"

    echo "--- DONE: RAM Image is ready at $RAM_DIR ---"
}

function set_production() {
    echo "--- SWITCHING TO PRODUCTION MODE ---"
    
    # 1. Ensure VM is off
    if sudo virsh list --name --state-running | grep -q "^$VM_DOMAIN$"; then
        echo "Error: VM is still running. Shut it down first."
        exit 1
    fi

    # 2. Ensure clean slate
    if mountpoint -q "$NFS_MOUNT"; then
        sudo umount "$NFS_MOUNT"
    fi
    sudo qemu-nbd --disconnect /dev/nbd0 
    
    check_and_create_dirs

    # Mount disk, or rebuild RAM image and then mount
    # Prompt the user
    read -r -p "Would you like to compress a RAM disk image? (Y/n) " response
    response=${response,,}
    
    if [[ "$response" == "y" || "$response" == "yes" ]]; then
        compress_ram_image
    else
        # FIX: Corrected function name (case sensitive: mount_vm -> mount_VM)
        mount_VM
    fi

    # Identify the latest kernel and initrd (sort by version, take the last one)
    LATEST_VMLINUZ=$(ls -1 "${NFS_MOUNT}/boot/vmlinuz"* | sort -V | tail -n 1)
    LATEST_INITRD=$(ls -1 "${NFS_MOUNT}/boot/initrd.img"* | sort -V | tail -n 1)

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
    sudo umount "$NFS_MOUNT" 
    # 2. Disconnect Disk
    sudo qemu-nbd --disconnect "$NBD_DEV" 

    echo "Done. NFS is offline. RAM boot is still online."
    echo "You may now start your VM to make changes."
}

function force_unmount() {
    echo "--- FORCE UNMOUNTING... ---"
    sudo umount -l "$NFS_MOUNT"
    sudo qemu-nbd --disconnect "$NBD_DEV"
}

# Simple Menu
echo 'FOG live boot manager script -- By Conner Smith ; Version 1.1'
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
