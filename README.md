# madOS &nbsp; [![Build madOS ISO](https://github.com/richknowles/madOS/actions/workflows/build.yml/badge.svg)](https://github.com/richknowles/madOS/actions/workflows/build.yml)

**Immutable CachyOS with ZFS boot environments and ML4W Hyprland.**

madOS is a custom CachyOS live ISO that installs an immutable-style Arch Linux system using ZFS as the root filesystem. Rollback to any previous system state in seconds — right from the bootloader. ML4W + Hyprland + your personal dotfiles are wired in from the start.

---

## What's inside

| Layer | Technology |
|---|---|
| Base distro | [CachyOS](https://cachyos.org) (optimized Arch Linux) |
| Filesystem | [OpenZFS](https://openzfs.org) with dataset-per-concern layout |
| Bootloader | [ZFSBootMenu](https://zfsbootmenu.org) — snapshot-aware boot menu |
| Desktop | [Hyprland](https://hyprland.org) via [ML4W](https://github.com/mylinuxforwork/dotfiles) |
| Dotfiles | [richknowles/.dotfiles](https://github.com/richknowles/.dotfiles) |
| Installer | Custom bash TUI (dialog-based), launches automatically at boot |

---

## Immutability model

madOS uses **ZFS boot environments** for rollback — the same concept as Fedora Silverblue/Kinoite, but on ZFS instead of ostree.

```
zroot/
├── ROOT/
│   └── arch          ← system root — snapshotted before every update
├── data/
│   └── home          ← user home — survives root rollbacks
└── var/
    ├── log           ← logs
    └── cache         ← pacman cache (excluded from snapshots)
```

**Workflow:**
```bash
# Before updating the system:
sudo zfs snapshot zroot/ROOT/arch@pre-update-$(date +%Y%m%d)

# Apply updates normally:
sudo pacman -Syu

# If something breaks — reboot and select the snapshot in ZFSBootMenu.
# No special tooling required.
```

---

## Installation

### 1. Get the ISO

Download the latest ISO from [GitHub Actions artifacts](https://github.com/richknowles/madOS/actions/workflows/build.yml)
or from [Releases](https://github.com/richknowles/madOS/releases) (tagged builds only).

### 2. Flash to USB

```bash
dd if=madOS-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

### 3. Boot and install

Boot from the USB. The TUI installer launches automatically on `tty1` and prompts for:

- **Target disk** — shown as a list, all data will be erased
- **Hostname** and **username**
- **Timezone**
- **Dotfiles repo URL** — pre-filled as `https://github.com/richknowles/.dotfiles`
- **GitHub token** — optional, leave blank for public repos

The installer then:
1. Partitions the disk (GPT: EFI + ZFS)
2. Creates the ZFS pool and datasets
3. Installs CachyOS base system via `pacstrap`
4. Configures ZFSBootMenu as the bootloader
5. Clones your dotfiles and runs `install.sh` + `scripts/install-packages.sh`
6. Installs ML4W Hyprland from AUR
7. Takes a baseline ZFS snapshot
8. Reboots

### 4. First boot

ZFSBootMenu appears — press Enter to boot. Log in, and ML4W Welcome launches to finish Hyprland configuration.

---

## Building the ISO locally

Requires an Arch Linux system with `archiso` installed.

```bash
git clone https://github.com/richknowles/madOS
cd madOS

# Optional: override defaults
cp config/defaults.conf archiso/airootfs/root/config.conf
# Edit archiso/airootfs/root/config.conf as needed

# Build (requires root)
sudo mkarchiso -v -w /tmp/mados-work -o /tmp/mados-out archiso/

# Flash
dd if=/tmp/mados-out/madOS-*.iso of=/dev/sdX bs=4M status=progress
```

---

## CI/CD

GitHub Actions builds the ISO automatically:
- On every push to `main` (excluding docs changes)
- Weekly on Sundays at 06:00 UTC
- On manual trigger via the Actions UI

ISO artifacts are retained for 14 days. Tag a commit (`git tag v1.0 && git push --tags`) to create a permanent GitHub Release.

---

## Repository structure

```
madOS/
├── archiso/
│   ├── profiledef.sh              # archiso profile definition
│   ├── packages.x86_64            # packages included in live ISO
│   ├── pacman.conf                # pacman config with CachyOS repos
│   └── airootfs/
│       ├── etc/
│       │   ├── motd               # live environment welcome message
│       │   └── systemd/system/
│       │       └── madOS-installer.service
│       └── root/
│           ├── install.sh         # main TUI installer
│           ├── zfs-setup.sh       # ZFS partitioning + pool/dataset creation
│           └── ml4w-setup.sh      # dotfiles clone + ML4W setup
├── config/
│   └── defaults.conf              # installer defaults (dotfiles URL, etc.)
└── .github/workflows/
    └── build.yml                  # GitHub Actions ISO build pipeline
```
