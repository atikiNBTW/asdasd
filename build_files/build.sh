#!/bin/bash

set -ouex pipefail

PACKAGES=()
TO_REMOVE=()

add_remove() {
  for p in "$@"; do
    TO_REMOVE+=("$p")
  done
}
add_pkg() {
  for p in "$@"; do
    PACKAGES+=("$p")
  done
}
add_pkgs() { add_pkg "$@"; }
add_removes() { add_remove "$@"; }

# tweak things
systemctl disable NetworkManager-wait-online.service
systemctl disable ModemManager.service

# Optimize DNF package manager for faster downloads and efficient updates
echo "max_parallel_downloads=10" | tee -a /etc/dnf/dnf.conf > /dev/null
dnf5 install -y dnf-plugins-core

# Replace Fedora Flatpak Repo with Flathub for better package management and apps stability
flatpak remote-delete fedora --force || true
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak repair

# Enable RPM Fusion repositories to access additional software packages and codecs
dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Install multimedia codecs to enhance multimedia capabilities
add_remove ffmpeg-free
add_pkg ffmpeg

dnf install -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin -x gstreamer1-plugins-bad-freeworld -x pipewire-codec-aptx -y --allowerasing

app_pkg "@sound-and-video"
add_pkg intel-media-driver

# Install Hardware Accelerated Codecs for AMD GPUs. This improves video playback and encoding performance on systems with AMD graphics.
add_removes mesa-va-drivers mesa-vdpau-drivers mesa-va-drivers.i686 mesa-vdpau-drivers.i686
add_pkgs mesa-va-drivers-freeworld mesa-vdpau-drivers-freeworld mesa-va-drivers-freeworld.i686 mesa-vdpau-drivers-freeworld.i686
add_pkgs ffmpeg-libs libva libva-utils
add_pkgs openh264 gstreamer1-plugin-openh264 mozilla-openh264
dnf config-manager setopt fedora-cisco-openh264.enabled=1
add_pkg rpmfusion-free-release-tainted
add_pkgs libdvdcss libavcodec-freeworld heif-pixbuf-loader libheif-freeworld libheif-tools

# Install virtualization tools to enable virtual machines and containerization
add_pkg "@virtualization"

# sed -i 's/GRUB_TIMEOUT.*/GRUB_TIMEOUT=2/' /etc/default/grub
# sed -i 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=15s/' /etc/systemd/user.conf
# sed -i 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=15s/' /etc/systemd/system.conf

export DRACUT_NO_XATTR=1

# coprs
dnf5 -y copr enable bieszczaders/kernel-cachyos-lto
dnf5 -y copr enable bieszczaders/kernel-cachyos-addons
dnf5 -y swap zram-generator-defaults cachyos-settings

add_pkgs scx-manager zoxide git stow foot zsh neovim distrobox btop lsd vnstat fd wl-clipboard-rs

## cachyos kernel

# workaround for dracut not working
touch /run/ostree-booted

dnf install -y kernel-cachyos-lto kernel-cachyos-lto-devel-matched
dnf5 -y remove kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra

rm /run/ostree-booted

# gtrash
curl -L "https://github.com/umlx5h/gtrash/releases/latest/download/gtrash_$(uname -s)_$(uname -m).tar.gz" | tar xz
chmod a+x ./gtrash
sudo mv ./gtrash /usr/bin/gtrash

# eza
curl -L https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz | tar xz
chmod a+x ./eza
sudo mv ./eza /usr/bin/eza

# generate initramfs for the new kernel
KERNEL_SUFFIX="cachyos-lto"
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"
/usr/bin/dracut -f -p --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"

dnf -y install "${PACKAGES[@]}" -x pipewire-codec-aptx --allowerasing
dnf -y remove "${TO_REMOVE[@]}"
dnf update --allowerasing

dnf5 -y copr disable bieszczaders/kernel-cachyos-lto
dnf5 -y copr disable bieszczaders/kernel-cachyos-addons
