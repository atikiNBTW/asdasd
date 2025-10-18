#!/bin/bash

set -ouex pipefail

flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
systemctl disable flatpak-add-fedora-repos.service

dnf5 -y copr enable bieszczaders/kernel-cachyos-lto
dnf5 -y copr enable bieszczaders/kernel-cachyos-addons
dnf5 -y swap zram-generator-defaults cachyos-settings

dnf5 -y install scx-manager git stow foot zsh neovim distrobox kernel-cachyos-lto kernel-cachyos-lto-devel-matched
dnf5 -y remove kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra

KERNEL_SUFFIX="cachyos-lto"
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"
/usr/bin/dracut -f -p --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"

dnf5 -y copr disable bieszczaders/kernel-cachyos-lto
dnf5 -y copr disable bieszczaders/kernel-cachyos-addons

systemctl disable NetworkManager-wait-online.service
systemctl disable ModemManager.service
# sed -i 's/GRUB_TIMEOUT.*/GRUB_TIMEOUT=2/' /etc/default/grub
# sed -i 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=15s/' /etc/systemd/user.conf
# sed -i 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=15s/' /etc/systemd/system.conf
