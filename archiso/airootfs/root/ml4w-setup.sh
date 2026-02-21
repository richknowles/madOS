#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ml4w-setup.sh — Clone dotfiles and run ML4W/Hyprland setup
# Sourced by install.sh; ml4w_setup_chroot() runs inside arch-chroot
# ─────────────────────────────────────────────────────────────────────────────

# ── Build the clone URL (inject token for private repos) ─────────────────────
_build_clone_url() {
    local url="$1"
    local token="$2"

    if [[ -n "$token" ]] && [[ "$url" == https://github.com/* ]]; then
        # Inject token: https://TOKEN@github.com/user/repo
        echo "${url/https:\/\/github.com/https:\/\/${token}@github.com}"
    else
        echo "$url"
    fi
}

# ── Main ML4W setup (runs inside arch-chroot via install.sh) ─────────────────
ml4w_setup_chroot() {
    local username="$1"
    local dotfiles_url="$2"
    local dotfiles_branch="${3:-main}"
    local github_token="${4:-}"

    local user_home="/home/${username}"
    local dotfiles_dir="${user_home}/.dotfiles"
    local clone_url
    clone_url="$(_build_clone_url "$dotfiles_url" "$github_token")"

    arch-chroot /mnt sudo -u "$username" bash -euo pipefail <<INNERCHROOT
set -euo pipefail

DOTFILES_DIR="${dotfiles_dir}"
CLONE_URL="${clone_url}"
BRANCH="${dotfiles_branch}"

echo "[ML4W] Cloning dotfiles from ${dotfiles_url} ..."
git clone --depth=1 --branch "\$BRANCH" "\$CLONE_URL" "\$DOTFILES_DIR"

# ── Run dotfiles install.sh (symlinks) ────────────────────────────────────────
if [[ -f "\${DOTFILES_DIR}/install.sh" ]]; then
    echo "[ML4W] Running install.sh (symlinking configs)..."
    cd "\${DOTFILES_DIR}"
    bash install.sh --all
fi

# ── Run package installer from dotfiles ───────────────────────────────────────
if [[ -f "\${DOTFILES_DIR}/scripts/install-packages.sh" ]]; then
    echo "[ML4W] Installing packages from dotfiles (pacman/AUR/flatpak)..."
    # Ensure yay is available for AUR packages
    if ! command -v yay &>/dev/null; then
        echo "[ML4W] Installing yay from AUR..."
        cd /tmp
        git clone https://aur.archlinux.org/yay.git yay-build
        cd yay-build
        makepkg -si --noconfirm
        cd ~
        rm -rf /tmp/yay-build
    fi

    # Enable Flatpak + Flathub
    if command -v flatpak &>/dev/null; then
        flatpak remote-add --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo || true
    fi

    cd "\${DOTFILES_DIR}"
    bash scripts/install-packages.sh
fi

# ── Install ML4W dotfiles manager from AUR ────────────────────────────────────
echo "[ML4W] Installing ML4W dotfiles manager..."
yay -S --noconfirm --needed ml4w-hyprland 2>/dev/null \
    || yay -S --noconfirm --needed ml4w-dotfiles 2>/dev/null \
    || echo "[ML4W] WARNING: ml4w AUR package not found — check package name at aur.archlinux.org"

# ── ArcStarry cursor theme (AUR — used by cursor.conf: setcursor ArcStarry-cursors 24) ──
echo "[ML4W] Installing ArcStarry cursor theme from AUR..."
yay -S --noconfirm --needed arcstarry-cursors 2>/dev/null \
    || yay -S --noconfirm --needed xcursor-arcstarry 2>/dev/null \
    || yay -S --noconfirm --needed arcstarry 2>/dev/null \
    || echo "[ML4W] NOTE: ArcStarry cursor not found under known AUR names." \
       "Hyprctl will set it on first login if the theme is installed elsewhere."

# ── First-boot ML4W launcher via systemd user unit ────────────────────────────
# If ml4w-welcome exists, launch it on first Hyprland session
if command -v ml4w-welcome &>/dev/null || command -v ml4w &>/dev/null; then
    mkdir -p ~/.config/autostart
    cat > ~/.config/autostart/ml4w-welcome.desktop <<EOF
[Desktop Entry]
Type=Application
Name=ML4W Welcome
Exec=ml4w-welcome
X-GNOME-Autostart-enabled=true
EOF
fi

echo "[ML4W] Dotfiles and ML4W setup complete for user ${username}."
INNERCHROOT

    success "ML4W + dotfiles configured for ${username}."
}

# ── Post-install first snapshot ───────────────────────────────────────────────
# Call this after ml4w_setup_chroot to snapshot the fresh configured state
ml4w_snapshot_baseline() {
    local pool="$1"
    zfs_initial_snapshot "$pool" "baseline-ml4w"
}
