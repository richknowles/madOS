#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# madOS Installer
# Immutable CachyOS with ZFS boot environments + ML4W/Hyprland
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Load defaults ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source /root/zfs-setup.sh
source /root/ml4w-setup.sh

# ── Configurable defaults (override in /root/config.conf if present) ──────────
DOTFILES_URL="https://github.com/richknowles/.dotfiles"
DOTFILES_BRANCH="main"
ZFS_POOL_NAME="zroot"
DEFAULT_HOSTNAME="madOS"
DEFAULT_USERNAME="user"
DEFAULT_LOCALE="en_US.UTF-8"
DEFAULT_TIMEZONE="America/New_York"
GITHUB_TOKEN=""

[[ -f /root/config.conf ]] && source /root/config.conf

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()     { echo -e "${CYAN}[madOS]${RESET} $*"; }
success() { echo -e "${GREEN}[  OK  ]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[ WARN ]${RESET} $*"; }
error()   { echo -e "${RED}[ERROR ]${RESET} $*"; exit 1; }

# ── Dialog helpers ────────────────────────────────────────────────────────────
HEIGHT=20; WIDTH=70
DIALOG="dialog --colors --backtitle 'madOS Installer — Immutable CachyOS + ZFS'"

d_info()    { eval "$DIALOG" --title "'$1'" --msgbox "'$2'" $HEIGHT $WIDTH; }
d_yesno()   { eval "$DIALOG" --title "'$1'" --yesno "'$2'" $HEIGHT $WIDTH; }
d_input()   { eval "$DIALOG" --title "'$1'" --inputbox "'$2'" $HEIGHT $WIDTH "'$3'" 2>&1 >/dev/tty; }
d_password(){ eval "$DIALOG" --title "'$1'" --passwordbox "'$2'" $HEIGHT $WIDTH 2>&1 >/dev/tty; }
d_menu()    { eval "$DIALOG" --title "'$1'" --menu "'$2'" $HEIGHT $WIDTH 10 $3 2>&1 >/dev/tty; }

# ── Welcome ───────────────────────────────────────────────────────────────────
welcome() {
    dialog --colors --backtitle "madOS Installer" \
        --title "Welcome to madOS" \
        --msgbox "\n\
\Zb\Z4madOS\Zn — Immutable CachyOS with ZFS + ML4W Hyprland\n\n\
This installer will:\n\
  • Partition your disk with a ZFS pool (${ZFS_POOL_NAME})\n\
  • Install CachyOS base system with ZFS boot environments\n\
  • Configure ZFSBootMenu for snapshot-based rollback\n\
  • Clone your dotfiles and run the ML4W Hyprland installer\n\n\
\ZbRollback workflow:\Zn\n\
  Before any update → take a ZFS snapshot\n\
  If something breaks → reboot, pick the snapshot in ZFSBootMenu\n\n\
Press OK to begin." \
        $HEIGHT $WIDTH
}

# ── Collect configuration ─────────────────────────────────────────────────────
collect_config() {
    # Disk selection
    local disk_list
    disk_list=$(lsblk -dpno NAME,SIZE,MODEL | grep -E "^/dev/(sd|nvme|vd)" \
        | awk '{printf "%s \"%s %s\" ", $1, $2, $3}')
    [[ -z "$disk_list" ]] && error "No block devices found."

    TARGET_DISK=$(dialog --colors --backtitle "madOS Installer" \
        --title "Select Target Disk" \
        --menu "\nWARNING: All data on the selected disk will be erased.\n\nAvailable disks:" \
        $HEIGHT $WIDTH 8 $disk_list 2>&1 >/dev/tty) || exit 1

    # Hostname
    HOSTNAME=$(dialog --colors --backtitle "madOS Installer" \
        --title "Hostname" --inputbox "\nEnter a hostname for this machine:" \
        $HEIGHT $WIDTH "$DEFAULT_HOSTNAME" 2>&1 >/dev/tty) || exit 1
    [[ -z "$HOSTNAME" ]] && HOSTNAME="$DEFAULT_HOSTNAME"

    # Username
    USERNAME=$(dialog --colors --backtitle "madOS Installer" \
        --title "Primary User" --inputbox "\nEnter your username:" \
        $HEIGHT $WIDTH "$DEFAULT_USERNAME" 2>&1 >/dev/tty) || exit 1
    [[ -z "$USERNAME" ]] && USERNAME="$DEFAULT_USERNAME"

    # User password
    local pass1 pass2
    while true; do
        pass1=$(dialog --colors --backtitle "madOS Installer" \
            --title "User Password" --passwordbox "\nPassword for ${USERNAME}:" \
            $HEIGHT $WIDTH 2>&1 >/dev/tty) || exit 1
        pass2=$(dialog --colors --backtitle "madOS Installer" \
            --title "User Password" --passwordbox "\nConfirm password:" \
            $HEIGHT $WIDTH 2>&1 >/dev/tty) || exit 1
        if [[ "$pass1" == "$pass2" ]]; then
            USER_PASSWORD="$pass1"; break
        fi
        dialog --msgbox "Passwords do not match. Try again." 8 40
    done

    # Root password
    while true; do
        pass1=$(dialog --colors --backtitle "madOS Installer" \
            --title "Root Password" --passwordbox "\nRoot password (leave blank to disable root login):" \
            $HEIGHT $WIDTH 2>&1 >/dev/tty) || exit 1
        pass2=$(dialog --colors --backtitle "madOS Installer" \
            --title "Root Password" --passwordbox "\nConfirm root password:" \
            $HEIGHT $WIDTH 2>&1 >/dev/tty) || exit 1
        if [[ "$pass1" == "$pass2" ]]; then
            ROOT_PASSWORD="$pass1"; break
        fi
        dialog --msgbox "Passwords do not match. Try again." 8 40
    done

    # Timezone
    TIMEZONE=$(dialog --colors --backtitle "madOS Installer" \
        --title "Timezone" --inputbox "\nEnter your timezone (e.g. America/New_York, Europe/London):" \
        $HEIGHT $WIDTH "$DEFAULT_TIMEZONE" 2>&1 >/dev/tty) || exit 1
    [[ -z "$TIMEZONE" ]] && TIMEZONE="$DEFAULT_TIMEZONE"

    # Dotfiles URL
    DOTFILES_URL=$(dialog --colors --backtitle "madOS Installer" \
        --title "Dotfiles Repository" \
        --inputbox "\nDotfiles repo URL:\n(pre-filled with your repo — change if needed)" \
        $HEIGHT $WIDTH "$DOTFILES_URL" 2>&1 >/dev/tty) || exit 1

    # GitHub token for private repos
    GITHUB_TOKEN=$(dialog --colors --backtitle "madOS Installer" \
        --title "GitHub Token (optional)" \
        --passwordbox "\nIf your dotfiles repo is \Zbprivate\Zn, enter a GitHub personal access token.\nLeave blank for public repos." \
        $HEIGHT $WIDTH 2>&1 >/dev/tty) || true

    # ZFS pool name
    ZFS_POOL_NAME=$(dialog --colors --backtitle "madOS Installer" \
        --title "ZFS Pool Name" \
        --inputbox "\nName for the ZFS root pool:" \
        $HEIGHT $WIDTH "$ZFS_POOL_NAME" 2>&1 >/dev/tty) || exit 1
    [[ -z "$ZFS_POOL_NAME" ]] && ZFS_POOL_NAME="zroot"
}

# ── Confirmation ──────────────────────────────────────────────────────────────
confirm_config() {
    dialog --colors --backtitle "madOS Installer" \
        --title "Confirm Installation" \
        --yesno "\nReview your configuration:\n\n\
  \ZbDisk:\Zn        ${TARGET_DISK}\n\
  \ZbPool:\Zn        ${ZFS_POOL_NAME}\n\
  \ZbHostname:\Zn    ${HOSTNAME}\n\
  \ZbUsername:\Zn    ${USERNAME}\n\
  \ZbTimezone:\Zn    ${TIMEZONE}\n\
  \ZbDotfiles:\Zn    ${DOTFILES_URL}\n\
  \ZbToken:\Zn       ${GITHUB_TOKEN:+(set)}\n\n\
\Zb\Z1WARNING: ${TARGET_DISK} will be completely erased!\Zn\n\n\
Proceed with installation?" \
        $HEIGHT $WIDTH || exit 1
}

# ── Install base system ───────────────────────────────────────────────────────
install_base() {
    log "Installing CachyOS base system..."
    pacstrap -K /mnt \
        base base-devel linux-cachyos linux-cachyos-headers linux-firmware \
        zfs-cachyos zfs-utils \
        networkmanager sudo git yay \
        grub efibootmgr dosfstools \
        zsh fish starship \
        neovim nano \
        hyprland hyprpaper hyprlock hypridle \
        xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
        waybar rofi-wayland dunst swww kitty \
        grim slurp wl-clipboard \
        pipewire pipewire-alsa pipewire-pulse wireplumber \
        sddm noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd \
        python python-pip curl wget rsync openssh \
        polkit polkit-kde-agent \
        2>&1 | tee /tmp/pacstrap.log \
        | dialog --colors --backtitle "madOS Installer" \
            --title "Installing Base System" \
            --progressbox "Installing packages (this may take a while)..." \
            $HEIGHT $WIDTH
}

# ── Configure chroot ──────────────────────────────────────────────────────────
configure_system() {
    log "Configuring system in chroot..."

    arch-chroot /mnt bash -euo pipefail <<CHROOT
# Locale
sed -i 's/#${DEFAULT_LOCALE} UTF-8/${DEFAULT_LOCALE} UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=${DEFAULT_LOCALE}" > /etc/locale.conf

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# Timezone
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

# Users
useradd -m -G wheel,audio,video,storage,optical -s /bin/zsh "${USERNAME}"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
$(if [[ -n "$ROOT_PASSWORD" ]]; then echo "echo 'root:${ROOT_PASSWORD}' | chpasswd"; fi)
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Enable services
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable bluetooth 2>/dev/null || true

# ZFS services
systemctl enable zfs-import-cache
systemctl enable zfs-import.target
systemctl enable zfs-mount
systemctl enable zfs.target
systemctl enable zfs-zed

# mkinitcpio with ZFS hook
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard zfs filesystems)/' /etc/mkinitcpio.conf
mkinitcpio -P
CHROOT
}

# ── User dotfiles + ML4W ──────────────────────────────────────────────────────
setup_dotfiles_chroot() {
    log "Setting up dotfiles and ML4W in chroot..."
    ml4w_setup_chroot \
        "$USERNAME" "$DOTFILES_URL" "$DOTFILES_BRANCH" "$GITHUB_TOKEN"
}

# ── ZFSBootMenu ───────────────────────────────────────────────────────────────
install_zfsbootmenu() {
    log "Installing ZFSBootMenu..."
    local efi_part="${EFI_PARTITION}"

    arch-chroot /mnt bash -euo pipefail <<CHROOT
# Install ZFSBootMenu via yay (run as user to avoid makepkg root issues)
sudo -u ${USERNAME} bash -c "yay -S --noconfirm zfsbootmenu"

# Create ZFSBootMenu EFI stub
mkdir -p /boot/efi/EFI/ZFSBootMenu
generate-zbm

# Add EFI boot entry
efibootmgr --create --disk ${TARGET_DISK} --part 1 \
    --label "ZFSBootMenu" \
    --loader "\\EFI\\ZFSBootMenu\\vmlinuz-bootmenu.EFI" \
    --unicode "ro quiet loglevel=0 zbm.prefer=${ZFS_POOL_NAME} zbm.import_policy=hostid"
CHROOT
}

# ── GRUB fallback (if ZFSBootMenu AUR fails) ──────────────────────────────────
install_grub_fallback() {
    warn "ZFSBootMenu install failed — falling back to GRUB with ZFS support."
    arch-chroot /mnt bash -euo pipefail <<CHROOT
grub-install --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=GRUB \
    --recheck
# Enable ZFS support in GRUB
echo 'GRUB_CMDLINE_LINUX="zfs.zfs_arc_max=8589934592"' >> /etc/default/grub
echo 'GRUB_PRELOAD_MODULES="zfs part_gpt"' >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT
}

# ── Summary ───────────────────────────────────────────────────────────────────
show_summary() {
    dialog --colors --backtitle "madOS Installer" \
        --title "Installation Complete!" \
        --msgbox "\n\
\Zb\Z2madOS has been installed successfully!\Zn\n\n\
\ZbNext steps:\Zn\n\
  1. Remove the live USB and reboot\n\
  2. ZFSBootMenu will appear — press Enter to boot madOS\n\
  3. Log in as \Zb${USERNAME}\Zn\n\
  4. The ML4W Hyprland setup will launch automatically\n\n\
\ZbImmutability workflow:\Zn\n\
  # Before any system update:\n\
  sudo zfs snapshot ${ZFS_POOL_NAME}/ROOT/arch@pre-update-\$(date +%Y%m%d)\n\n\
  # Roll back at any time via ZFSBootMenu at boot,\n\
  # or run: sudo zfs rollback ${ZFS_POOL_NAME}/ROOT/arch@<snapshot>\n\n\
Press OK to reboot." \
        $HEIGHT $WIDTH

    umount -R /mnt 2>/dev/null || true
    zpool export "$ZFS_POOL_NAME" 2>/dev/null || true
    reboot
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    clear
    welcome
    collect_config
    confirm_config

    # Start network time sync
    timedatectl set-ntp true

    # ZFS setup (partitioning + pool creation)
    zfs_setup "$TARGET_DISK" "$ZFS_POOL_NAME"

    # Base system
    install_base

    # System configuration in chroot
    configure_system

    # Dotfiles + ML4W
    setup_dotfiles_chroot

    # Bootloader
    if ! install_zfsbootmenu; then
        install_grub_fallback
    fi

    show_summary
}

main "$@"
