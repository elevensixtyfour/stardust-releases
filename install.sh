#!/usr/bin/env bash
# Stardust installer for Linux — Arch / EndeavourOS / Manjaro, Ubuntu / Debian / Mint, Fedora, openSUSE.
#
#   curl -fsSL https://raw.githubusercontent.com/elevensixtyfour/stardust-releases/main/install.sh | bash
#
# Installs the latest Stardust AppImage for your user (no root needed except for
# system libraries), adds it to your app menu, and lets Stardust update itself.
# Uninstall:  curl -fsSL https://raw.githubusercontent.com/elevensixtyfour/stardust-releases/main/install.sh | bash -s -- --uninstall
set -euo pipefail

REPO="elevensixtyfour/stardust-releases"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$DATA/stardust"
APP="$APP_DIR/Stardust.AppImage"
BIN="$HOME/.local/bin/stardust"
DESKTOP="$DATA/applications/stardust.desktop"
ICON="$DATA/icons/hicolor/512x512/apps/stardust.png"

say()  { printf '\033[1;31m•\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

if [ "${1:-}" = "--uninstall" ]; then
    rm -f "$APP" "$BIN" "$DESKTOP" "$ICON"
    rmdir "$APP_DIR" 2>/dev/null || true
    has update-desktop-database && update-desktop-database "$DATA/applications" >/dev/null 2>&1 || true
    say "Stardust removed. Your settings and login are still in ~/.config/stardust (delete that folder to remove them too)."
    exit 0
fi

[ "$(id -u)" -ne 0 ] || fail "run this as your normal user, not with sudo — it installs into your home folder and asks for your password only for system libraries."
[ "$(uname -m)" = "x86_64" ] || fail "Stardust for Linux is available for x86_64 (64-bit Intel/AMD) only; this machine is $(uname -m)."
has curl || fail "curl is required."

# --- System libraries: FUSE 2 (to run AppImages) plus Electron's usual runtime libs
say "Installing system libraries (you may be asked for your password)…"
if has pacman; then
    sudo pacman -S --needed --noconfirm fuse2 gtk3 nss alsa-lib libxss libnotify \
        || fail "pacman couldn't install the libraries. Update your system first (sudo pacman -Syu), then run this again."
elif has apt-get; then
    fuse=libfuse2; apt-cache show libfuse2t64 >/dev/null 2>&1 && fuse=libfuse2t64
    sudo apt-get install -y "$fuse"
elif has dnf; then
    sudo dnf install -y fuse-libs gtk3 nss alsa-lib libXScrnSaver libnotify
elif has zypper; then
    sudo zypper --non-interactive install libfuse2 gtk3 mozilla-nss libnotify4
else
    say "Unknown package manager — make sure FUSE 2 (libfuse.so.2), GTK 3 and NSS are installed."
fi

# --- Latest desktop release (newest first; Android releases have no AppImage)
say "Finding the latest Stardust release…"
url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=30" \
    | grep -o '"browser_download_url": *"[^"]*linux-x86_64\.AppImage"' | head -n1 \
    | sed -E 's/.*"(https[^"]+)"$/\1/')"
[ -n "$url" ] || fail "couldn't find a Linux release on github.com/$REPO."
version="$(printf '%s' "$url" | sed -E 's/.*Stardust-v([0-9.]+)-linux.*/\1/')"

say "Downloading Stardust $version…"
mkdir -p "$APP_DIR" "$(dirname "$BIN")" "$(dirname "$DESKTOP")" "$(dirname "$ICON")"
tmp="$(mktemp "$APP_DIR/.download.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
curl -fL --progress-bar "$url" -o "$tmp"
chmod 755 "$tmp"
mv -f "$tmp" "$APP"
trap - EXIT
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/.github/assets/stardust-icon.png" -o "$ICON" || true

# --- Launcher: handles machines without FUSE and kernels that block Chromium's sandbox
cat > "$BIN" <<'LAUNCHER'
#!/bin/sh
APP="${XDG_DATA_HOME:-$HOME/.local/share}/stardust/Stardust.AppImage"
FLAGS=""
# No FUSE 2: run without mounting the AppImage (starts a little slower)
if ! { ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; } && [ ! -e /usr/lib/libfuse.so.2 ]; then
    export APPIMAGE_EXTRACT_AND_RUN=1
fi
# Kernels/AppArmor that block unprivileged user namespaces (linux-hardened, Ubuntu 24.04+)
if [ "$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null)" = "0" ] || \
   [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)" = "1" ]; then
    FLAGS="--no-sandbox"
fi
exec "$APP" $FLAGS "$@"
LAUNCHER
chmod 755 "$BIN"

cat > "$DESKTOP" <<DESKTOPFILE
[Desktop Entry]
Type=Application
Name=Stardust
GenericName=Music player
Comment=Nothing-styled Deezer client
Exec=$BIN %U
Icon=$ICON
Terminal=false
Categories=AudioVideo;Audio;Player;
Keywords=music;deezer;flac;player;
StartupWMClass=stardust
DESKTOPFILE
has update-desktop-database && update-desktop-database "$DATA/applications" >/dev/null 2>&1 || true

say "Stardust $version is installed. Open it from your app menu, or run: stardust"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) say "(To use the 'stardust' command, add ~/.local/bin to your PATH.)";; esac
say "Updates: Settings → Updates inside Stardust. Uninstall: re-run with --uninstall."
