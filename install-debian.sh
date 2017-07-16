#!/bin/bash
# Based on Chrubuntu 34v87 script

if [ "$1" != "" ]; then
  echo -e "Please specify a rootfs.tar.gz after install location\nscript rootfs.tar.gz"
  exit 1
fi

BASE_IMAGE_FILE="$1"

# fw_type will always be developer for Mario.
# Alex and ZGB need the developer BIOS installed though.
fw_type="`crossystem mainfw_type`"
if [ ! "$fw_type" = "developer" ]
  then
    echo -e "\nYou're Chromebook is not running a developer BIOS!"
    echo -e "You need to run:\n"
    echo -e "sudo chromeos-firmwareupdate --mode=todev\n"
    echo -e "and then re-run this script."
    return
  else
    echo -e "\nOh good. You're running a developer BIOS...\n"
fi

# hwid lets us know if this is a Mario (Cr-48), Alex (Samsung Series 5), ZGB (Acer), etc
hwid="`crossystem hwid`"
chromebook_arch="`uname -m`"

powerd_status="`initctl status powerd`"
if [ ! "$powerd_status" = "powerd stop/waiting" ]
then
  echo -e "Stopping powerd to keep display from timing out..."
  initctl stop powerd
fi

powerm_status="`initctl status powerm`"
if [ ! "$powerm_status" = "powerm stop/waiting" ]
then
  echo -e "Stopping powerm to keep display from timing out..."
  initctl stop powerm
fi

setterm -blank 0

# Figure out what the target disk is

target_disk=/dev/mmcblk1

read -p "Press [Enter] to install Ubuntu on ${target_disk} or CTRL+C to quit"

ext_size="`blockdev --getsz ${target_disk}`"
aroot_size=$((ext_size - 65600 - 33))
parted --script ${target_disk} "mktable gpt"
cgpt create ${target_disk}
cgpt add -i 6 -b 64 -s 32768 -S 1 -P 5 -l KERN-A -t "kernel" ${target_disk}
cgpt add -i 7 -b 65600 -s $aroot_size -l ROOT-A -t "rootfs" ${target_disk}
sync
blockdev --rereadpt ${target_disk}
partprobe ${target_disk}
crossystem dev_boot_usb=1

target_rootfs="${target_disk}p7"
target_kern="${target_disk}p6"

echo -e "Target Kernel Partition: $target_kern \nTarget Root FS: ${target_rootfs}"

if [ -z "$IMAGE_FILE" ]; then
  IMAGE_FILE="$BASE_IMAGE_FILE"
fi

untar_file="$IMAGE_FILE"

# our mount target
DEB=/tmp/debian
if [ ! -d $DEB ]; then
  mkdir $DEB
fi

echo "Creating filesystem on ${target_rootfs}..."
mkfs.ext4 -j ${target_rootfs}
mount ${target_rootfs} $DEB

if [[ "$untar_file" =~ ".tgz" || "$untar_file" =~ ".gz" ]] ; then
  tar xvzCf $DEB "$untar_file"
elif [[ "$untar_file" =~ ".bz2" ]] ; then
  tar xvjCf $DEB "$untar_file"
elif [[ "$untar_file" =~ ".xz" ]] ; then
  tar xvJCf $DEB "$untar_file"
else
  echo "Hmm... not sure how to untar your file"
  exit 1
fi

# Set up fstab:
cat > $DEB/etc/fstab <<EOF
${target_rootfs} / ext4 noatime,errors=remount-ro 0 1
EOF
# Set up the apt sources and update:
cat > $DEB/etc/apt/sources.list <<EOF
deb http://mirror.utexas.edu/debian wheezy main non-free contrib
deb-src http://mirror.utexas.edu/debian wheezy main non-free contrib
EOF

chroot $DEB /debootstrap/debootstrap --second-stage

cp /boot/vmlinuz $DEB/boot/vmlinuz
# Let's get some firmware in place
mkdir -p $DEB/lib/modules
cp -r /lib/modules/* $DEB/lib/modules
# Copy the non-free firmware for the wifi device:
mkdir -p $DEB/lib/firmware/mrvl
cp /lib/firmware/mrvl/sd8797_uapsta.bin $DEB/lib/firmware/mrvl
cp /usr/lib/libgestures.so.0 $DEB/usr/lib/
cp /usr/lib/libevdev* $DEB/usr/lib/
cp /usr/lib/libbase*.so $DEB/usr/lib/

# Create the setup script in /tmp/setup-script on the ubuntu partition
cat > $DEB/tmp/setup-script <<EOF
# fix up /etc/shadow so root can log in
passwd -d root

echo "nameserver 8.8.8.8" > /etc/resolv.conf

# update-initramfs will need this
#mount -t devpts devpts /dev/pts
#mount -t proc proc /proc

# Update the package list:
apt-get update
# Install useful packages:
export LANG=C
apt-get install -y cgpt vboot-utils vboot-kernel-utils
apt-get install -y wicd-daemon wicd-cli wicd-curses console-setup
apt-get install -y xserver-xorg-video-fbdev sudo
apt-get install -y openbox xdm menu obconf obmenu feh pcmanfm
apt-get install -y pypanel conky git nm-applet alsa-utils
# Set the hostname:
echo "technochrome" > /etc/hostname

# clean up
#umount /dev/pts
#umount /proc

if [ ! -d /etc/X11/xorg.conf.d ] ; then mkdir /etc/X11/xorg.conf.d ; fi
if [ ! -f /etc/X11/xorg.conf.d/exynos5.conf ] ; then

cat > /etc/X11/xorg.conf.d/exynos5.conf <<EOZ
Section "Device"
        Identifier      "Mali FBDEV"
        Driver          "fbdev"
        Option          "fbdev"                 "/dev/fb0"
        Option          "Fimg2DExa"             "false"
        Option          "DRI2"                  "true"
        Option          "DRI2_PAGE_FLIP"        "false"
        Option          "DRI2_WAIT_VSYNC"       "true"
#       Option          "Fimg2DExaSolid"        "false"
#       Option          "Fimg2DExaCopy"         "false"
#       Option          "Fimg2DExaComposite"    "false"
        Option          "SWcursorLCD"           "false"
EndSection

Section "Screen"
        Identifier      "DefaultScreen"
        Device          "Mali FBDEV"
        DefaultDepth    24
EndSection
EOZ
fi
EOF

# run the setup script
chroot $DEB bash /tmp/setup-script

cp -r /usr/share/alsa/ucm/* $DEB/usr/share/alsa/ucm/
cp /usr/lib/xorg/modules/input/cmt_drv.so $DEB/usr/lib/xorg/modules/input/
cp /etc/X11/xorg.conf.d/50*.conf $DEB/etc/X11/xorg.conf.d/

# now set up the kernel
echo "console=tty1 printk.time=1 nosplash rootwait root=${target_rootfs} rw rootfstype=ext4 lsm.module_locking=0" > $DEB/boot/config
vbutil_kernel --pack $DEB/boot/vmlinuz.signed --keyblock /usr/share/vboot/devkeys/kernel.keyblock --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk --config $DEB/boot/config --vmlinuz $DEB/boot/vmlinuz --version 1 --arch arm
dd if=$DEB/boot/vmlinuz.signed of=${target_kern} bs=512

# Unmount ubuntu
umount $DEB

# finally make it bootable, but just once (-S 0: flagged as not successful, -T 1: one try)
cgpt add -S 1 -T 1 -P 12 -i 6 ${target_disk}

echo -e "\n*****************\n"
echo "Done -- reboot to enter Ubuntu."

initctl start powerd
initctl start powerm
