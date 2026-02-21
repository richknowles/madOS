#!/usr/bin/env bash
# test-iso.sh — Boot a madOS ISO in QEMU without burning to USB
#
# Usage:
#   ./test-iso.sh                        # auto-find latest ISO in /tmp/out
#   ./test-iso.sh /path/to/madOS.iso     # explicit path
#   ./test-iso.sh --ram 8G               # override RAM (default 4G)
#   ./test-iso.sh --disk 30G             # override virtual disk size (default 20G)
#
# Requirements:  qemu-system-x86_64  ovmf (UEFI firmware)
#   Arch:   sudo pacman -S qemu-system-x86_64 edk2-ovmf
#   Debian: sudo apt install qemu-system-x86 ovmf
#
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
RAM="4G"
DISK_SIZE="20G"
ISO=""
DISK_IMG="/tmp/madOS-test-disk.qcow2"
OVMF_PATHS=(
    /usr/share/edk2/x64/OVMF.fd
    /usr/share/edk2-ovmf/OVMF.fd
    /usr/share/OVMF/OVMF.fd
    /usr/share/ovmf/OVMF.fd
)

# ── Argument parsing ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ram)   RAM="$2";       shift 2 ;;
        --disk)  DISK_SIZE="$2"; shift 2 ;;
        *.iso)   ISO="$1";       shift   ;;
        *)       echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# ── Find ISO ──────────────────────────────────────────────────────────────────
if [[ -z "$ISO" ]]; then
    ISO=$(find /tmp/out -name "*.iso" 2>/dev/null | sort | tail -1)
    if [[ -z "$ISO" ]]; then
        echo "ERROR: No ISO found in /tmp/out. Pass path as argument or build first."
        exit 1
    fi
fi
echo "ISO:  $ISO"

# ── Find OVMF (UEFI firmware) ─────────────────────────────────────────────────
OVMF=""
for p in "${OVMF_PATHS[@]}"; do
    [[ -f "$p" ]] && { OVMF="$p"; break; }
done
if [[ -z "$OVMF" ]]; then
    echo "ERROR: OVMF firmware not found. Install edk2-ovmf (Arch) or ovmf (Debian)."
    exit 1
fi
echo "OVMF: $OVMF"

# ── Create or reuse virtual disk ──────────────────────────────────────────────
if [[ ! -f "$DISK_IMG" ]]; then
    echo "Creating ${DISK_SIZE} virtual disk at ${DISK_IMG}..."
    qemu-img create -f qcow2 "$DISK_IMG" "$DISK_SIZE"
else
    echo "Reusing existing disk: $DISK_IMG (delete to reset)"
fi

# ── Launch QEMU ───────────────────────────────────────────────────────────────
echo ""
echo "Booting madOS in QEMU (${RAM} RAM, ${DISK_SIZE} disk)..."
echo "Close the window or press Ctrl+C to stop."
echo ""

qemu-system-x86_64 \
    -enable-kvm \
    -machine type=q35,accel=kvm \
    -cpu host \
    -m "$RAM" \
    -smp "$(nproc)" \
    -bios "$OVMF" \
    -drive file="$DISK_IMG",if=virtio,format=qcow2 \
    -cdrom "$ISO" \
    -boot order=d,menu=on \
    -vga virtio \
    -display gtk,gl=on \
    -audiodev none,id=noaudio \
    -net nic,model=virtio \
    -net user \
    -serial mon:stdio
