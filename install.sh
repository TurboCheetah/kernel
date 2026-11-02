#!/bin/sh
# Install the kernel build tuning into /etc. Run as root (doas ./install.sh).
# Originals are backed up to /root/kernel-tune-backup-<timestamp>/.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
bk=/root/kernel-tune-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$bk"
cp -a /etc/portage/package.use/cachyos-kernel /etc/portage/package.env "$bk"/
[ -d /etc/kernel/config.d ] && cp -a /etc/kernel/config.d "$bk"/ || true

install -d -m 755 /etc/kernel/config.d
install -m 644 "$here"/etc/kernel/config.d/*.config /etc/kernel/config.d/
install -m 644 "$here"/etc/portage/package.use/cachyos-kernel /etc/portage/package.use/cachyos-kernel
install -m 644 "$here"/etc/portage/env/kernel-jobs.conf /etc/portage/env/kernel-jobs.conf

# Append kernel-jobs.conf to the kernel lines in package.env (idempotent).
sed -i -E '/^sys-kernel\/(cachyos|gentoo)-kernel[[:space:]]/{/kernel-jobs\.conf/!s/$/ kernel-jobs.conf/}' /etc/portage/package.env

echo "Installed. Backup: $bk"
grep -E '^sys-kernel/' /etc/portage/package.env
