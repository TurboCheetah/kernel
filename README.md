# This is my personal kernel, please modify it to fit your use case

Currently: [CachyOS](https://github.com/CachyOS/linux-cachyos) as a Gentoo
distribution kernel (`sys-kernel/cachyos-kernel` from the
[CachyOS-kernels](https://github.com/Szowisz/CachyOS-kernels) overlay), trimmed
with config fragments so it builds fast. Host: Ryzen 7 4800H Lenovo laptop with a
GTX 1660 Ti (nvidia-drivers), run as a headless docker server.

Builds went from ~1.5–2 h to ~17 min (7.3.0-r3): 3266→2226 built-in options,
6373→~570 modules.

Install with `doas ./install.sh`, which backs up the originals to
`/root/kernel-tune-backup-<timestamp>/`, then rebuild the kernel **and**
nvidia-drivers together:

```sh
emerge -1 sys-kernel/cachyos-kernel x11-drivers/nvidia-drivers
```

## Files

| File | Installed to | Purpose |
| --- | --- | --- |
| `etc/kernel/config.d/10-hardware-trim.config` | `/etc/kernel/config.d/` | Hand-picked: other GPUs, server NICs, InfiniBand, TV/DVB, staging, … |
| `etc/kernel/config.d/20-no-debug-info.config` | `/etc/kernel/config.d/` | No DWARF (the ebuild strips it anyway). Also drops BTF and sched_ext. |
| `etc/kernel/config.d/30-server-localmod.config` | `/etc/kernel/config.d/` | **Generated.** Disables every module this host doesn't use. |
| `etc/kernel/config.d/40-overrides.config` | `/etc/kernel/config.d/` | Hand fixes: qxl instead of amdgpu as nvidia's TTM-helper provider; no Intel QAT. |
| `etc/portage/package.use/cachyos-kernel` | `/etc/portage/package.use/` | `-autofdo -propeller` (no profile, so they only add cost). |
| `etc/portage/env/kernel-jobs.conf` | `/etc/portage/env/` + `package.env` | `-j16` for kernel builds. |
| `localmod/` | — | Generator for the 30- fragment and its keep lists. |

kernel-build.eclass merges `/etc/kernel/config.d/*.config` last, in name order,
on top of the CachyOS config and the ebuild's USE-flag tweaks.

## What's kept by the 30- fragment

- every module loaded when it was generated (`/proc/modules`)
- `localmod/keep-modules.txt`: on-demand things like wireguard, docker network
  drivers, vhost, loop/zram/dm-crypt, exfat/ntfs3/iso/udf/squashfs
- `localmod/keep-subtrees.txt`: all of netfilter and net/sched
- `localmod/keep-configs.txt`: symbols localmodconfig can't map (Lenovo WMI), tcp cubic/bbr

Everything else that was a module is gone: USB serial/ethernet dongles, game
controllers, most HID vendor drivers, amdgpu, NFS/CIFS, md-raid, VFIO, etc.
Built-ins are untouched, so boot (NVMe, AHCI, btrfs, ext4, USB HID, fuse) is unaffected.

## Gotchas

- **nvidia-drivers** needs `DRM_TTM_HELPER`, which only an in-tree DRM driver can
  select. localmodconfig keeps amdgpu for that (the biggest driver in the tree), so
  `40-overrides` swaps in tiny `DRM_QXL`. With amdgpu/i915/xe gone, nvidia-drm
  builds without HDCP (it checks `IS_ENABLED(CONFIG_DRM_DISPLAY_HDCP_HELPER)`).
- Reinstalling the **same** kernel version leaves the previous build's modules in
  `/lib/modules/<ver>`. Remove `.ko` files not in the package's `CONTENTS`, then `depmod`.

## Something stopped working / new hardware

Add the module name to `localmod/keep-modules.txt` (or a symbol to
`keep-configs.txt`), regenerate, reinstall, rebuild.

## Regenerating (e.g. after a big kernel version jump)

The fragment only ever *disables* modules, so new modules in future kernels stay
at the CachyOS default (built). Regenerating just trims those again.

```sh
EB=/var/db/repos/CachyOS-kernels/sys-kernel/cachyos-kernel/cachyos-kernel-<ver>.ebuild
W=/var/tmp/notmpfs/portage/sys-kernel/cachyos-kernel-<ver>/work
doas mv /etc/kernel/config.d/30-server-localmod.config /root/   # base config must not include it
doas env PORTAGE_TMPDIR=/var/tmp/notmpfs ebuild $EB clean configure
mkdir -p /tmp/k/src && doas tar -C $W/cachyos-* -cf - . | tar -C /tmp/k/src -xf -
doas cat $W/modprep/.config > /tmp/k/base.config
./localmod/gen-fragment.sh /tmp/k/src /tmp/k/base.config etc/kernel/config.d/30-server-localmod.config
doas ./install.sh && doas env PORTAGE_TMPDIR=/var/tmp/notmpfs ebuild $EB clean
```

Run it while the system's normal workload (docker, VPNs) is up, so `/proc/modules` is representative.
