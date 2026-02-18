#!/usr/bin/env bash
# madOS archiso profile definition
# Immutable CachyOS with ZFS + ML4W/Hyprland

iso_name="madOS"
iso_label="madOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="richknowles <https://github.com/richknowles>"
iso_application="madOS — Immutable CachyOS with ZFS and ML4W Hyprland"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=(
    'bios.syslinux.mbr'
    'bios.syslinux.eltorito'
    'uefi-ia32.grub.esp'
    'uefi-x64.grub.esp'
)
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')

file_permissions=(
    ["/etc/shadow"]="0:0:400"
    ["/root"]="0:0:750"
    ["/root/install.sh"]="0:0:755"
    ["/root/zfs-setup.sh"]="0:0:755"
    ["/root/ml4w-setup.sh"]="0:0:755"
)
