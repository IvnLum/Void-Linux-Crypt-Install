#!/bin/bash
#
## ENV - VARIABLES
#

EFI_PARTITION=/dev/vda1
CRYPT_PARTITION=/dev/vda2
CRYPT=cv
MOUNT_POINT=/mnt
ROOT_SUB=@
SWAP_SUB=@swap
HOME_SUB=@home
SNAPSHOTS_SUB=@snapshots
BTRFS_OPTS="rw,noatime,compress=zstd,discard=async"
CUST_REPO="https://void.cijber.net/current"
XBPS_ARCH=$(uname -m)

#
## LUKS - BTRFS Setup
#

echo "=> Formatting as encrypted partition..."
cryptsetup luksFormat --type luks1 -y $CRYPT_PARTITION
echo "=> Open the encrypted volume (re-type passphrase)"
cryptsetup open $CRYPT_PARTITION $CRYPT
echo "=> Formatting as FAT EFI partition..."
mkfs.fat -F32 -n EFI $EFI_PARTITION
echo "=> Formatting as BTRFS Encrypted volume..."
mkfs.btrfs /dev/mapper/$CRYPT
echo "=> Mounting Encrypted BTRFS Volume..."
mount -o $BTRFS_OPTS /dev/mapper/$CRYPT $MOUNT_POINT
echo "=> Creating Encrypted BTRFS @ROOT @SWAP @HOME @SNAPSHOTS SUB-Volume..."
btrfs su cr $MOUNT_POINT/@
btrfs su cr $MOUNT_POINT/@swap
btrfs su cr $MOUNT_POINT/@home
btrfs su cr $MOUNT_POINT/@snapshots
echo "=> Successfully Created all SUB-Volumes..."
echo "=> Umounting Encrypted BTRFS Volume..."
umount $MOUNT_POINT
echo "=> Mounting Encrypted BTRFS @ROOT SUB-Volume..."
mount -o $BTRFS_OPTS,subvol=@ /dev/mapper/$CRYPT $MOUNT_POINT
echo "=> Creating tree hierarchy mount points {efi, swap, home, .snapshots} ..."
mkdir $MOUNT_POINT/{efi,swap,home,.snapshots}
echo "=> Mounting Encrypted BTRFS SUB-Volumes tree hierarchy..."
mount -o $BTRFS_OPTS,subvol=@swap /dev/mapper/$CRYPT $MOUNT_POINT/swap
mount -o $BTRFS_OPTS,subvol=@home /dev/mapper/$CRYPT $MOUNT_POINT/home
mount -o $BTRFS_OPTS,subvol=@snapshots /dev/mapper/$CRYPT $MOUNT_POINT/.snapshots
echo "=> Encrypted storage is now ready for installation!!!"
read -p "Continue..."

#
## SWAP / Partitions mount setup
#

echo "=> Allocating space for swapfile..."
truncate -s 0 $MOUNT_POINT/swap/swapfile
chattr +C $MOUNT_POINT/swap/swapfile
fallocate -l $(awk '/MemTotal/ {print $2"K"}' /proc/meminfo) $MOUNT_POINT/swap/swapfile
echo "=> Preparing swapfile..."
chmod 600 $MOUNT_POINT/swap/swapfile
mkswap $MOUNT_POINT/swap/swapfile
echo "=> Preparing TEMP SUB-Volumes for XBPS..."
mkdir -p $MOUNT_POINT/var/cache
btrfs su cr $MOUNT_POINT/var/cache/xbps
btrfs su cr $MOUNT_POINT/var/tmp
btrfs su cr $MOUNT_POINT/srv
echo "=> Mounting EFI Partition..."
mount -o rw,noatime $EFI_PARTITION $MOUNT_POINT/efi

#
## XBPS pre-install Database keys prepare
#

echo "=> Storing XBPS DB Keys into target..."
mkdir -p $MOUNT_POINT/var/db/xbps/keys
cp /var/db/xbps/keys/* $MOUNT_POINT/var/db/xbps/keys
read -p "Continue to install base packages before chroot target..."

#
## Void base target install
#

echo "=> Installing packages into target..."
XBPS_ARCH=$(uname -m) xbps-install -S -y -R $CUST_REPO -r $MOUNT_POINT base-system linux-mainline btrfs-progs cryptsetup neovim linux-firmware xmirror
for dir in dev proc sys run; do mount --rbind /$dir $MOUNT_POINT/$dir; mount --make-rslave $MOUNT_POINT/$dir; done
cp /etc/resolv.conf $MOUNT_POINT/etc
echo "=> Base system prepared"

#
## Copy this script trimmed (script for chroot)
#

echo "=> Trimming script inside chroot..."
echo "=> Copying trimmed script..."

echo -e '#!/bin/bash\n\n'"$(sed -n -e '/.*ENV/,$p' cryptinst.sh | sed '1,/^$/d' | head -11)" > $MOUNT_POINT/tmp/cryptinst_chroot.sh
echo -e "$(sed -n -e '/.*<i>/,$p' cryptinst.sh | sed '1,/^$/d')" >> $MOUNT_POINT/tmp/cryptinst_chroot.sh
chmod +x $MOUNT_POINT/tmp/cryptinst_chroot.sh
read -p "Continue to enter chroot..."
echo "=> Chroot..."
chroot $MOUNT_POINT /bin/bash -c "./tmp/cryptinst_chroot.sh"
rm $MOUNT_POINT/tmp/cryptinst_chroot.sh
umount -l $MOUNT_POINT
cryptsetup luksClose $CRYPT
read -p "System Installed, Press Enter to Exit..."
exit
#reboot

#
## <i> Trimmed chroot script
#

echo "=> Now inside target base-system!!!"
echo "=> Now customize system..."
read -p "Press Enter to Continue..."

echo "@ HWCLOCK, TIMEZONE & KEYMAP @"
read -p "Press Enter to Uncomment target HWCLK, TIMEZONE & KEYMAP"
vim /etc/rc.conf
ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime

#
## Uncomment libc-locales, set hostname, customize hosts file
#

echo "@ libC Locales @"
read -p "Press Enter to Uncomment target libc-Locales"
vim /etc/default/libc-locales
xbps-reconfigure -f glibc-locales
echo "@ Hostname @"
read -p "Press Enter to set Hostname"
vim /etc/hostname
echo "@ Hosts File @"
read -p "Press Enter to update Hosts file"
vim /etc/hosts
echo "=> Setting Bash as default shell"
chsh /bin/bash root
echo "@ ROOT password @"
read -p "Press Enter to set ROOT password"
passwd root
echo "@ Select MIRROR @"
read -p "Press Enter to set MIRROR"
xmirror

#
## EDIT visudo members accesses (uncomment wheel group)
#

read -p "Press Enter to grant %wheel group sudo access"

EDITOR=neovim visudo
xbps-install -Sy
xbps-install -y void-repo-debug void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree
xbps-install -Sy

echo "=> Setting partitions mountpoints (FSTAB)..."

echo "tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0" > /etc/fstab
echo "UUID=$(blkid -s UUID -o value /dev/mapper/$CRYPT) / btrfs $BTRFS_OPTS,subvol=$ROOT_SUB 0 1" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value /dev/mapper/$CRYPT) /swap btrfs defaults,subvol=$SWAP_SUB 0 2" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value /dev/mapper/$CRYPT) /home btrfs $BTRFS_OPTS,subvol=$HOME_SUB 0 2" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value /dev/mapper/$CRYPT) /.snapshots btrfs $BTRFS_OPTS,subvol=$SNAPSHOTS_SUB 0 2" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value $EFI_PARTITION) /efi vfat defaults,noatime 0 2" >> /etc/fstab
echo "/swap/swapfile none swap sw 0 0" >> /etc/fstab

echo "=> Installing GRUB package..."
xbps-install -y grub-x86_64-efi
echo -e 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5' > /etc/default/grub
echo 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 rd.auto=1 rd.luks.allow-discards"' >> /etc/default/grub
echo -e 'GRUB_DISABLE_OS_PROBER=false\nGRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub
echo "@ GRUB cfg file CHECK @"
read -p "Press Enter to check GRUB CFG"
vim /etc/default/grub
echo "=> Installing GRUB into efi..."
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id="Linux"

echo "=> Generating second slot keyfile for auto boot..."
dd bs=515 count=4 if=/dev/urandom of=/boot/keyfile.bin
cryptsetup -v luksAddKey $CRYPT_PARTITION /boot/keyfile.bin
chmod 000 /boot/keyfile.bin
chmod -R g-rwx,o-rwx /boot
echo "cryptroot UUID=$(blkid -s UUID -o value $CRYPT_PARTITION) /boot/keyfile.bin luks" >> /etc/crypttab
echo 'install_items+=" /boot/keyfile.bin /etc/crypttab "' >  /etc/dracut.conf.d/10-crypt.conf

echo "=> Installing specified packages..."
xbps-install -y NetworkManager bluez xorg sddm wayland weston weston-xwayland xorg-server-xwayland
xbps-install -y xfce4 plasma-desktop kscreen sddm plasma-nm plasma-pa konsole kitty pcmanfm-qt gvfs gvfs-mtp fuse3 gstreamer1-pipewire firefox
xbps-install -y pipewire alsa-pipewire libjack-pipewire libspa-bluetooth rtkit slurp xdg-desktop-portal xdg-desktop-portal-kde xdg-desktop-portal-wlr

groupadd pipewire
groupadd pulse
groupadd pulse-access

echo "=> Linking DHCP Daemon..."
ln -s /etc/sv/NetworkManager /var/service
ln -s /etc/sv/dhcpcd* /var/service

echo "=> Linking WPA_SUPPLICANT Daemon..."
ln -s /etc/sv/wpa_supplicant /var/service

echo "=> Linking Common Daemons..."
ln -s /etc/sv/{dbus,elogind,polkitd,bluetoothd,sddm} /var/service

echo "=> Linking pipewire defaults..."
mkdir -p /etc/pipewire/pipewire.conf.d /etc/alsa/conf.d

ln -s /usr/share/examples/wireplumber/10-wireplumber.conf /etc/pipewire/pipewire.conf.d/
ln -s /usr/share/alsa/alsa.conf.d/{50-pipewire.conf,99-pipewire-default.conf} /etc/alsa/conf.d
echo "/usr/lib/pipewire-0.3/jack" > /etc/ld.so.conf.d/pipewire-jack.conf

echo "=> Add user..."
read -p "Press Enter to add user accounts"
vim /tmp/usertmp
while read u; do useradd -m "$u"; done < /tmp/usertmp
echo "=> User accounts added..."
while read u; do usermod -aG wheel,tty,dialout,audio,video,bluetooth,pipewire,pulse,pulse-access "$u"; done < /tmp/usertmp
echo "=> User accounts added to every set group"

read -p "Press Enter to set 1st user password"
passwd $(head -n 1 /tmp/usertmp)

echo "=> Generating initramfs..."
xbps-reconfigure -fa
echo "=> Done!!!"
exit

#
## <e> End chroot script
#
