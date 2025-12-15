# FOG-LiveBoot-Instructions
A guide on how to set up a FOG server for booting a live Linux environment over PXE boot. 

# Intro

This guide details how to set up a FOG server with an extra spice thrown in. IE:

- The ability to capture and restore images of computers (this is what FOG does by default)
- Boot a live Linux environment (this guide details how to install Kubuntu, but any ext4 Linux install should work) over the network using one of three modes:
    - Boot Kubuntu golden image, load just whats needed into RAM, serve files over NFS (Faster boot, less RAM usage, slower performance)
    - Boot Kubuntu golden image, load the whole image into RAM (Slower boot, more RAM usage, best performance)
    - Boot a Kubuntu installer ISO, and serve its files over NTP.*

*- In the future I hope to get the installer program integrated into the golden image. I’ve made attempts but they haven’t worked so far. 

The “Golden Image” uses a QEMU Virtual Machine that allows you to have complete control of what the bootable environment is like. Whatever is on your hard drive of the VM is mirrored to your netboot clients.

# Setup

## Prerequisites

You will need…

- **A router**
- **A computer/VM** with at least gigabit networking to install your FOG server onto
- **A decent amount of hard drive space**. I recommend at least 80 GB.
- **8+ GB RAM**
- **A decent processor**. The server shouldn’t use too many resources, however compressing your live environment into a squashfs for the RAM environment will uses as many CPU cores as it can, so the better your processor is, the faster this will go.

## Knowing your network

Do you have a DHCP/PXE boot server already? If you don’t know what that is, you probably don’t need to worry about this. If you do, **this will conflict with it.**  This project uses `dnsmasq` for managing PXE boot. FOG has a built in PXE boot server, and you can use that at your own risk if you would like, however I have not tested it. If your router has settings for changing DHCP options 66 and 67, you can also use that. This guide assumes you want the boot server to handle all the nitty gritty with DHCP boot. 

Obviously, in order for this to work, your network needs to allow talking to other devices on the LAN. 

It is **highly recommended** to set up a static IP address on your server so that it has a consistent local IP. 

## Setting up the server

### Installing FOG

First, set up your target server. **This guide assumes a Debian/Ubuntu-based distro.** A desktop version of Linux is recommeneded for ease of use working with the virtual machines, but if you are comfortable with QEMU, you could theoritcally opt for a headless install. 

Once your machine is set up, we can begin installing stuff. Open up a terminal and follow these commands. (I recommend using SSH so copy-pasting commands will be easier)

```bash
# Update package lists then upgrade packages
sudo apt update && sudo apt upgrade -y

# Download FOG server to home directory
cd ~
git clone https://github.com/FOGProject/fogproject.git
cd fogproject/bin
# Install it
sudo ./installfog.sh
```

The FOG setup wizard will open. Most settings you can leave at default, except for this: 

- Installation Type: Normal (N)
- DHCP Router Address: <Your Router’s IP>
- Would you like DHCP to handle DNS?: Y
    - Next it will ask “What is the DNS address to be used on the DHCP server?” Either put your router’s IP or your favorite DNS server (Most people use Googles server at `8.8.8.8`)
- Would you like to use the FOG server for DHCP service? N
- Would you like to enable secure HTTPS… N (Unless you want to set it up, which is out of the scope of this guide)

From here, FOG will install. Follow the steps on the screen to update the database, and then return to a prompt. 

### PXE Booting with dnsmasq

Skip this step if you plan on having FOG or your router handle PXE boot. 

```bash
# Install dnsmasq
sudo apt install -y dnsmasq

# Edit dnsmasq config
sudo nano /etc/dnsmasq.d/ltsp.conf
```

You will be dropped into a text editor. Paste this in, then replace all instances of <FOG_SERVER_IP> with your machines static IP. 

```bash
# Don't function as a DNS server:
port=0

# Log lots of extra information about DHCP transactions.
log-dhcp

# Set the root directory for files available via TFTP.
tftp-root=/tftpboot

# The boot filename, Server name, Server Ip Address
dhcp-boot=undionly.kpxe,,<FOG_SERVER_IP>

# Disable re-use of the DHCP servername and filename fields as extra
# option space. That's to avoid confusing some old or broken DHCP clients.
dhcp-no-override

# Inspect the vendor class string and match the text to set the tag
dhcp-vendorclass=BIOS,PXEClient:Arch:00000
dhcp-vendorclass=UEFI32,PXEClient:Arch:00006
dhcp-vendorclass=UEFI,PXEClient:Arch:00007
dhcp-vendorclass=UEFI64,PXEClient:Arch:00009

# Set the boot file name based on the matching tag from the vendor class (above)
dhcp-boot=net:UEFI32,i386-efi/ipxe.efi,,<FOG_SERVER_IP>
dhcp-boot=net:UEFI,ipxe.efi,,<FOG_SERVER_IP>
dhcp-boot=net:UEFI64,ipxe.efi,,<FOG_SERVER_IP>

# PXE menu. The first part is the text displayed to the user.
# The second is the timeout, in seconds.
pxe-prompt="Booting FOG Client", 1

# The known types are x86PC, PC98, IA64_EFI, Alpha, Arc_x86,
# Intel_Lean_Client, IA32_EFI, BC_EFI, Xscale_EFI and X86-64_EFI
# This option is first and will be the default if there is no input from the user.
pxe-service=X86PC, "Boot to FOG", undionly.kpxe
pxe-service=X86-64_EFI, "Boot to FOG UEFI", ipxe.efi
pxe-service=BC_EFI, "Boot to FOG UEFI PXE-BC", ipxe.efi

# This range(s) is for the public interface, where dnsmasq functions
# as a proxy DHCP server providing boot information but no IP leases.
dhcp-range=<FOG_SERVER_IP>,proxy
```

Save and Exit (Ctrl-X in nano).

```bash
# Bring the service online and tell systemctl to start it at boot
sudo systemctl restart dnsmasq
sudo systemctl enable dnsmasq
```

### Prepping the “Golden” virtual machine

First you must install QEMU and virt-manager, which facilitates virtual machines. 

In order for this to work, your machine **needs to have hardware virtualization enabled.** This is usually called *Intel VT-x* on Intel machines, and *AMD-V* on AMD machines. In VMWare ESXi, the setting you need to enable is “Expose hardware assisted virtualization” under the CPU tab of your VM’s settings. 

Installing QEMU:
```bash
# Install virtual machine stuff
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager qemu-utils

# Add your user to the virtual machines groups
sudo adduser $USER libvirt
sudo adduser $USER kvm
```

Log out and back in / restart for changes to take affect. Launch `virt-manager` and create a new VM. Disk size doesn't really matter, I made mine 50 GB. From there, install your Linux environment of choice. This guide details installing Kubuntu, so I would download the Kubuntu installer ISO, mount it as my VM’s CD drive, then install Kubuntu like normal. 

The only thing of note here is to try and keep your install onto one partition. **Avoid LVMs, encryption, and anything that isnt just a standard ext4 partition.** 

Once your have your Linux environment ready to go, open up a terminal. If applicable, install openssh-server and SSH into your golden VM from your source machine so copy-pasting commands becomes easier. 

Be aware that everything installed in your golden VM will be mirrored to what people see in their netboot environment. So, if you install openssh-server, it will be installed on all client. 

In your golden VM:

```bash
# Update package list and install overlayroot 
sudo apt update
sudo apt install overlayroot

# Check what partitions we have. 
lsblk
# FIND THE BIG PARTITION AND MAKE NOTE OF ITS NUMBER!!! If its /dev/sda1, your number is 1.

# Remove autologin if any (it will break it)
sudo sed -i '/\[Autologin\]/,/^\[/d' /etc/sddm.conf
# Also check for overrides and nuke them:
sudo rm -f /etc/sddm.conf.d/*autologin*

sudo nano /etc/initramfs-tools/conf.d/driver-policy
```

Add this line (create the file if empty):

```bash
MODULES=most
```

Save and exit.

```bash
sudo update-initramfs -u
```

Shut down your VM.

### server-control script

`server-control.sh` is a script used for bringing the server online/offline, and compressing RAM disk images. You can download it on your computer by running:
```bash
wget https://raw.githubusercontent.com/THEWHITEBOY503/FOG-LiveBoot-Instructions/refs/heads/main/server-control.sh
```
Grant it executable permission: 

```bash
chmod +x server-control.sh
```

Tweak the config values before your first run. Open `server-control.sh` with your favorite text editor (eg. `nano server-control.sh`) and adjust these lines at the top:
```bash
VM_DOMAIN="YOUR_VM_NAME" # Whatever the name of the VM is in virt-manager, if applicable. This is for the running check.
NBD_DEV="/dev/nbd0"  # Leave this unless you have something occupying it already
NFS_MOUNT="/var/www/html/os/kubuntu" # Default value is fine, or if you want you can change the 'kubuntu' part of the path
RAM_DIR="/var/www/html/os/kubuntu-ram" # Default value is fine, or if you want you can change the 'kubuntu-ram' part of the path
IMAGE_PATH="/var/lib/libvirt/images/example.qcow2" # CHANGE this to the path of your golden VM's hard drive image.
PARTITION="1" # From your lsblk in your golden VM. Change this number if needed.
```
Make sure it runs:

```bash
./server-control
```

If it runs, Ctrl-C and exit. You do not need to publish/unpublish at this time. 

## NFS Setup

Once your server has been set up:

In your server:

```bash
# Create the mount point for files to be served out of (you don't have to name it Kubuntu, but keep the path in mind)
**sudo mkdir -p /var/www/html/os/kubuntu**
```

Go ahead and publish the server using server-control.sh.

```bash
# Give permissions to the files needed to NFS boot
sudo chmod 644 /var/www/html/os/kubuntu/vmlinuz
sudo chmod 644 /var/www/html/os/kubuntu/initrd.img
```

Open /etc/exports in your favorite text editor. (eg. `sudo nano /etc/exports`)

Add this line to the bottom, replacing kubuntu with your mount point if needed:

```bash
/var/www/html/os/kubuntu *(ro,sync,no_wdelay,insecure_locks,no_root_squash,insecure,no_subtree_check,fsid=2)
```

Refresh and reload.

```bash
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```
[Add your FOG menu option.](https://github.com/THEWHITEBOY503/FOG-LiveBoot-Instructions/blob/main/README.md#nfs-boot-fog-options)
At this point, NFS booting should be ready to go. Make sure your path is published, and netboot a device from your FOG server to test!

## RAM Boot setup

RAM Booting is a bit more complicated than NFS. The entire disk image is compressed into a squashfs. If you enable RAM boot in your setup, it is important not to install too much software/files to your golden VM, so that RAM usage isn’t too high.

Enter maintenance mode, then start your VM. In your VM terminal:

```bash
sudo apt update
sudo apt install casper discover
echo "NETBOOT=y" | sudo tee /etc/initramfs-tools/conf.d/netboot
sudo update-initramfs -u
```

Shut down the VM. 

In your server:

```bash
sudo mkdir /var/www/html/os/kubuntu-ram # Pick a directory for your RAM boot files.
sudo mkdir -p /var/www/html/os/kubuntu-ram/casper 
sudo nano /etc/exports
```

Add this line to the bottom, adding the path you created above:

```bash
/var/www/html/os/kubuntu-ram *(ro,sync,no_wdelay,insecure_locks,no_root_squash,insecure,no_subtree_check,fsid=3)
```

Sync the exports:

```bash
sudo exportfs -ra
```

Run `server-control.sh` and publish, then answer Y to if you want to build a RAM disk.
Add your [RAM boot FOG menu entry](https://github.com/THEWHITEBOY503/FOG-LiveBoot-Instructions/blob/main/README.md#ram-boot-fog-options) and test.

## Adding FOG menu options

Refer back to this section to add the different boot entries.

Open the boot menu by opening the FOG management interface (http://<YOUR-SERVER-IP>/fog/management/), then navigating to FOG Configuration (Wrench icon)→ iPXE New Menu Entry. To modify existing entries, select iPXE Menu Item Settings instead. 

Fill this out: 

Menu Item : The name that shows up in the fog management menu

Description : What shows up in the FOG boot menu

Parameters : See below

### NFS Boot FOG Options:

```bash
kernel http://<YOUR_SERVER_IP>/os/kubuntu/vmlinuz
initrd http://<YOUR_SERVER_IP>/os/kubuntu/initrd.img
imgargs vmlinuz initrd=initrd.img root=/dev/nfs nfsroot=<YOUR_SERVER_IP>:/var/www/html/os/kubuntu ro overlayroot=tmpfs ip=dhcp
boot || goto MENU
```

### RAM Boot FOG Options:

```bash
kernel http://<YOUR_SERVER_IP>/os/kubuntu-ram/vmlinuz
initrd http://<YOUR_SERVER_IP>/os/kubuntu-ram/initrd.img
imgargs vmlinuz initrd=initrd.img ip=dhcp boot=casper netboot=nfs nfsroot=<YOUR_SERVER_IP>:/var/www/html/os/kubuntu-ram toram ignore_uuid hostname=<GOLDEN_VM's_HOSTNAME> username=<YOUR_GOLDEN_USERNAME>
boot || goto MENU
```

# Credits

This guide was written by Conner Smith. The system detailed by this guide was set up and tested prior to the writing of this guide. This guide was written on December 14th, 2025. [Kubuntu](https://kubuntu.org) 24.04 LTS was used for testing, and [FOG server](https://fogproject.org) version 1.5.10.1733. 

## Transparency on AI use

This guide, the idea behind it, and all of its moving parts, testing, script tweaks, troubleshooting, etc. was done by a human. However, Artificial Intelligence LLMs (Google Gemini Pro 3 Thinking) were consulted in a search engine-fashion for a lot of the unknown information, as well as script writing.
