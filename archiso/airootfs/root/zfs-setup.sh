#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# zfs-setup.sh — ZFS partition + pool + dataset creation for madOS
# Sourced by install.sh
# ─────────────────────────────────────────────────────────────────────────────

# Globals set by this module (consumed by install.sh)
EFI_PARTITION=""
ZFS_PARTITION=""

zfs_setup() {
    local disk="$1"
    local pool="$2"

    log "Partitioning ${disk}..."
    _partition_disk "$disk"

    log "Creating ZFS pool '${pool}'..."
    _create_pool "$disk" "$pool"

    log "Creating ZFS datasets..."
    _create_datasets "$pool"

    log "Mounting ZFS datasets..."
    _mount_datasets "$pool"
}

# ── Partitioning ──────────────────────────────────────────────────────────────
_partition_disk() {
    local disk="$1"

    # Wipe existing signatures
    wipefs -af "$disk"
    sgdisk --zap-all "$disk"

    # GPT layout:
    #   1 — EFI System Partition  (512 MiB, FAT32)
    #   2 — ZFS partition         (remaining space)
    sgdisk \
        -n 1:0:+512M -t 1:EF00 -c 1:"EFI System" \
        -n 2:0:0     -t 2:BF00 -c 2:"ZFS"         \
        "$disk"

    # Inform kernel of partition table change
    partprobe "$disk"
    sleep 2

    # Resolve partition names (handles both /dev/sdX1 and /dev/nvme0n1p1)
    if [[ "$disk" == *nvme* ]] || [[ "$disk" == *mmcblk* ]]; then
        EFI_PARTITION="${disk}p1"
        ZFS_PARTITION="${disk}p2"
    else
        EFI_PARTITION="${disk}1"
        ZFS_PARTITION="${disk}2"
    fi

    # Format EFI partition
    mkfs.fat -F32 -n EFI "$EFI_PARTITION"

    success "Partitioned ${disk}: EFI=${EFI_PARTITION}, ZFS=${ZFS_PARTITION}"
}

# ── ZFS pool creation ─────────────────────────────────────────────────────────
_create_pool() {
    local disk="$1"
    local pool="$2"

    # Modprobe ZFS
    modprobe zfs || true

    zpool create -f \
        -o ashift=12                   \
        -o autotrim=on                 \
        -O acltype=posixacl            \
        -O compression=zstd            \
        -O dnodesize=auto              \
        -O normalization=formD         \
        -O relatime=on                 \
        -O xattr=sa                    \
        -O mountpoint=none             \
        -R /mnt                        \
        "$pool" "$ZFS_PARTITION"

    success "ZFS pool '${pool}' created."
}

# ── Dataset layout ────────────────────────────────────────────────────────────
# Immutable-style layout:
#   zroot/ROOT/arch   — system root (boot environment)
#   zroot/data/home   — user home (survives root rollbacks)
#   zroot/var/log     — logs (excluded from snapshots by default)
#   zroot/var/cache   — package cache (excluded from snapshots)
_create_datasets() {
    local pool="$1"

    # Root dataset containers
    zfs create -o mountpoint=none                    "${pool}/ROOT"
    zfs create -o mountpoint=none                    "${pool}/data"
    zfs create -o mountpoint=none                    "${pool}/var"

    # Boot environment — this is what ZFSBootMenu manages
    zfs create \
        -o mountpoint=/ \
        -o canmount=noauto \
        "${pool}/ROOT/arch"

    # User home — separate so rollbacks don't wipe home
    zfs create \
        -o mountpoint=/home \
        "${pool}/data/home"

    # Logs — com.sun:auto-snapshot=false excludes from scheduled snapshots
    zfs create \
        -o mountpoint=/var/log \
        -o com.sun:auto-snapshot=false \
        "${pool}/var/log"

    # Pacman package cache — no need to snapshot package cache
    zfs create \
        -o mountpoint=/var/cache/pacman \
        -o com.sun:auto-snapshot=false \
        "${pool}/var/cache"

    # Mark the boot environment
    zpool set bootfs="${pool}/ROOT/arch" "$pool"

    success "ZFS datasets created under '${pool}'."
}

# ── Mount ─────────────────────────────────────────────────────────────────────
_mount_datasets() {
    local pool="$1"

    zfs mount "${pool}/ROOT/arch"

    # Create EFI mount point and mount
    mkdir -p /mnt/boot/efi
    mount "$EFI_PARTITION" /mnt/boot/efi

    # Create dirs for other datasets (auto-mounted)
    mkdir -p /mnt/home /mnt/var/log /mnt/var/cache/pacman

    success "All datasets mounted at /mnt."
}

# ── Snapshot helper (used by installer post-install for first snapshot) ────────
zfs_initial_snapshot() {
    local pool="$1"
    local label="${2:-fresh-install}"
    local snap="${pool}/ROOT/arch@${label}"

    zfs snapshot "$snap"
    success "Initial snapshot created: ${snap}"
    echo "  Roll back at any time: sudo zfs rollback ${snap}"
}
