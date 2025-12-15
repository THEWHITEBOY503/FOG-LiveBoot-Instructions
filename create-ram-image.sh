#!/bin/bash
# CONFIG
VM_IMAGE="/var/lib/libvirt/images/kubuntu.qcow2"  # Check your path!
MOUNT_POINT="/mnt" # Should work unless you have something else there. If you plan to, make this somewhere else.
OUTPUT_DIR="/var/www/html/os/kubuntu-ram" # Check this path as well

echo "--- Starting RAM Image Builder ---"

# 1. Ensure clean slate
sudo umount $MOUNT_POINT 2>/dev/null
sudo qemu-nbd --disconnect /dev/nbd0 2>/dev/null
sudo mkdir -p $OUTPUT_DIR

# 2. Mount the VM Disk
echo "Mounting VM Source..."
sudo modprobe nbd max_part=16
sudo qemu-nbd --connect=/dev/nbd0 $VM_IMAGE
sleep 2
# adjust partition number (p2) if needed based on your earlier lsblk
sudo mount /dev/nbd0p1 $MOUNT_POINT 

# 3. Copy Boot Files (Kernel needs to match the squashfs)
echo "Copying Kernel and Initrd..."
# Using the same logic as your publish script to handle symlinks
if [ -f "$MOUNT_POINT/boot/vmlinuz" ]; then
    sudo cp -L $MOUNT_POINT/boot/vmlinuz $OUTPUT_DIR/vmlinuz
    sudo cp -L $MOUNT_POINT/boot/initrd.img $OUTPUT_DIR/initrd.img
else
    sudo cp $MOUNT_POINT/boot/vmlinuz* $OUTPUT_DIR/vmlinuz
    sudo cp $MOUNT_POINT/boot/initrd.img* $OUTPUT_DIR/initrd.img
fi
# Fix permissions so HTTP can read them
sudo chmod 644 $OUTPUT_DIR/vmlinuz $OUTPUT_DIR/initrd.img

# 4. THE BIG SQUEEZE (Compression)
# 4. THE BIG SQUEEZE (Compression)
echo "Compressing filesystem... (This will take time)"

# Create the casper directory if missing
sudo mkdir -p $OUTPUT_DIR/casper

# Remove old file (Target the CASPER folder)
sudo rm -f $OUTPUT_DIR/casper/filesystem.squashfs

# Compress into the /casper/ folder
sudo mksquashfs $MOUNT_POINT $OUTPUT_DIR/casper/filesystem.squashfs -comp gzip -wildcards -e 'swapfile' 'var/cache/apt/archives/*' 'tmp/*'

# 5. Fix Permissions
sudo chmod 644 $OUTPUT_DIR/casper/filesystem.squashfs
# 6. Cleanup
sudo umount $MOUNT_POINT
sudo qemu-nbd --disconnect /dev/nbd0

echo "--- DONE: RAM Image is ready at $OUTPUT_DIR ---"
