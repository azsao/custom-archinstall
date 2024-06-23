#!/usr/bin/env -S bash -e
# shellcheck disable=SC2001

# clear tty
clear

# Cosmetics (colours for text).
BOLD='\e[1m'
BRED='\e[91m'
BBLUE='\e[34m'  
BGREEN='\e[92m'
BYELLOW='\e[93m'
RESET='\e[0m'

# Pretty print (function).
info_print () {
    echo -e "${BOLD}${BGREEN}[ ${BYELLOW}•${BGREEN} ] $1${RESET}"
}

# Pretty print for input (function).
input_print () {
    echo -ne "${BOLD}${BYELLOW}[ ${BGREEN}•${BYELLOW} ] $1${RESET}"
}

# Alert user of bad input (function).
error_print () {
    echo -e "${BOLD}${BRED}[ ${BBLUE}•${BRED} ] $1${RESET}"
}

questionaire () {
lsblk
input_print "Please enter your dual-boot partition EFI: "
read -r -s winpart
input_print "Please enter your root partition: "
read -r -s rootpart
input_print "Please enter your swap partition: "
read -r -s swappart
input_print "Please enter your EFI partition: "
read -r -s efipart

input_print "Please enter your desired username: "
read -r -s username
input_print "Please enter your desired password: "
read -r -s userpass
input_print "Please enter your desired root password: "
read -r -s rootpass


input_print "Please enter your desired hostname: "
read -r -s hostname
}

partition () {
  mkfs.ext4 /dev/$rootpart
  mkswap /dev/$swappart
  swapon /dev/$swappart
  mkfs.fat -F 32 /dev/$efipart
  mount /dev/$rootpart /mnt
  mount --mkdir /dev/$efipart /mnt/boot
}

timedate () {
timedatectl set-timezone America/New_York
}

mirrors () {
  cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak 
  pacman -Sy
  pacman -S pacman-contrib
  rankmirrors -n 10 /etc/pacman.d/mirrorlist.bak > /etc/pacman.d/mirrorlist
}

pacstrap () {
  pacstrap -i /mnt base base_devel linux linux-headers linux-firmware mesa xf86-video-amdgpu amd-ucode vulkan-radeon sudo nano vim git neofetch networkmanager dhcpcd pipewire bluez wpa_supplicant
}

fstab () {
  genfstab -U /mnt >> /mnt/etc/fstab
}

sysconfig () {

  # root password
echo "root:$rootpass" | arch-chroot /mnt chpasswd

  # user & pass 
arch-chroot /mnt useradd -m "$username"
echo "$username:$userpass" | arch-chroot /mnt chpasswd
arch-chroot /mnt usermod -aG wheel,storage,power "$username"

# granting permissions
echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel
}

locale () {
  locale_file="/etc/locale.gen"
  sed -i '/^# *en_US.UTF-8 UTF-8/s/^# *//' "$locale_file"
  if grep -q "^en_US.UTF-8 UTF-8" "$locale_file"; then
  info_print "Successfully uncommented en_US.UTF-8 UTF-8 in $locale_file."
else
  error_print "Failed to uncomment en_US.UTF-8 UTF-8. Please check the file manually."
fi

  arch-chroot /mnt /bin/bash -e <<EOF
  locale-gen
  echo LANG=en_US.UTF-8 > /etc/locale.conf
  export LANG=en_US.UTF-8
  EOF
}

hostname () {
  echo "$hostname" > /mnt/etc/hostname

cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF
}

zoneinfo () {

  ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

}

grub () {
  grub_file="/etc/default/grub"

# installing GRUB
  arch-chroot /mnt /bin/bash -e <<EOF
  mkdir /boot/grub
  mount /dev/$winpart /boot/grub/
  pacman -S grub efibootmgr dosfstools mtools
  pacman -S os-prober
EOF

# configuring grub
sed -i '/^# *GRUB_DISABLE_OS_PROBER=false/s/^# *//' "$grub_file"
if grep -q "^GRUB_DISABLE_OS_PROBER=false" "$grub_file"; then
  info_print "Successfully uncommented GRUB_DISABLE_OS_PROBER=false in $grub_file."
else
  error_print "Failed to uncomment GRUB_DISABLE_OS_PROBER=false. Please check the file manually."
fi

# setting up GRUB
arch-chroot /mnt /bin/bash -e <<EOF
grub-install --target=x86_64-efi --efi-directory=/boot/grub --bootloader-id=grub_uefi --recheck
grub-mkconfig -o /boot/grub/grub.cfg
EOF
}

enable_service () {
  arch-chroot /mnt /bin/bash -e <<EOF
  systemctl enable dhcpcd.service
  systemctl enable NetworkManager.service
EOF
}


until questionaire; do : ; done
until partition; do : ; done
until timedate; do : ; done
until mirrors; do : ; done
until pacstrap; do : ; done
until fstab; do : ; done
until sysconfig; do : ; done

umount -lR /mnt

info_print "Installation has been completed, please reboot and remove the USB" 
