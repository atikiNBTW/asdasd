#!/bin/bash

set -o errexit -o nounset -o pipefail -o xtrace

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXTRA_PACKAGES_FILE="${EXTRA_PACKAGES_FILE:-$SCRIPT_DIR/extra-packages.txt}"

PACKAGES=()
TO_REMOVE=()

add_pkg() {
  for p in "$@"; do
    PACKAGES+=("$p")
  done
}

add_remove() {
  for p in "$@"; do
    TO_REMOVE+=("$p")
  done
}

add_pkgs() { add_pkg "$@"; }
add_removes() { add_remove "$@"; }

if [[ -f "$EXTRA_PACKAGES_FILE" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    add_pkg "$line"
  done < "$EXTRA_PACKAGES_FILE"
fi

# --- system tweaks ---
systemctl disable NetworkManager-wait-online.service || true
systemctl disable ModemManager.service || true

# --- dnf and repo setup ---
printf '%s\n' 'max_parallel_downloads=10' | tee -a /etc/dnf/dnf.conf > /dev/null
dnf5 install -y dnf-plugins-core

flatpak remote-delete fedora --force || true
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak repair

dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf config-manager setopt fedora-cisco-openh264.enabled=1

dnf5 -y copr enable bieszczaders/kernel-cachyos-lto
dnf5 -y copr enable bieszczaders/kernel-cachyos-addons
dnf5 -y swap zram-generator-defaults cachyos-settings

# --- package groups ---
add_remove ffmpeg-free
add_pkg ffmpeg
add_pkg "@multimedia"
add_pkg "@sound-and-video"
add_pkg intel-media-driver

add_removes mesa-va-drivers mesa-vdpau-drivers mesa-va-drivers.i686 mesa-vdpau-drivers.i686
add_pkgs mesa-va-drivers-freeworld mesa-vdpau-drivers-freeworld mesa-va-drivers-freeworld.i686 mesa-vdpau-drivers-freeworld.i686
add_pkgs ffmpeg-libs libva libva-utils
add_pkgs openh264 gstreamer1-plugin-openh264 mozilla-openh264
add_pkg rpmfusion-free-release-tainted
add_pkgs libdvdcss libavcodec-freeworld heif-pixbuf-loader libheif-freeworld libheif-tools

add_pkg "@virtualization"

# --- kernel workaround and install ---
touch /run/ostree-booted

dnf install -y kernel-cachyos-lto kernel-cachyos-lto-devel-matched
dnf5 -y remove kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra

KERNEL_SUFFIX="cachyos-lto"
QUALIFIED_KERNEL="$(rpm -q kernel-cachyos-lto --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n')"
/usr/bin/dracut -f -p --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
rm -f /run/ostree-booted

# --- custom binaries ---
curl -fsSL "https://github.com/umlx5h/gtrash/releases/latest/download/gtrash_$(uname -s)_$(uname -m).tar.gz" | tar xz
chmod a+x ./gtrash
install -m 0755 ./gtrash /usr/bin/gtrash
rm -f ./gtrash

curl -fsSL https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz | tar xz
chmod a+x ./eza
install -m 0755 ./eza /usr/bin/eza
rm -f ./eza

# --- apply package changes ---
if ((${#PACKAGES[@]} > 0)); then
  dnf -y install "${PACKAGES[@]}" -x pipewire-codec-aptx --allowerasing --skip-unavailable
fi

if ((${#TO_REMOVE[@]} > 0)); then
  dnf -y remove "${TO_REMOVE[@]}"
fi

dnf -y update --allowerasing -x vlc-plugins-base

# --- cleanup ---
dnf5 -y copr disable bieszczaders/kernel-cachyos-lto
dnf5 -y copr disable bieszczaders/kernel-cachyos-addons

rm -f /etc/yum.repos.d/negativo17-fedora-multimedia.repo
rm -f /etc/yum.repos.d/_copr_ublue-os-akmods.repo
rm -f /etc/yum.repos.d/tailscale.repo
