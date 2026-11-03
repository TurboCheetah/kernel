# cachyos-kernel build configuration

Configuration for building the [CachyOS](https://github.com/CachyOS/linux-cachyos)
kernel as a Gentoo distribution kernel (`sys-kernel/cachyos-kernel` from the
[CachyOS-kernels](https://github.com/Szowisz/CachyOS-kernels) overlay), trimmed
with kernel config fragments to reduce build time.

The configuration targets a single host: a Lenovo laptop with a Ryzen 7 4800H and
a GTX 1660 Ti (`x11-drivers/nvidia-drivers`), running as a headless Docker server.

## Results

Measured on 7.3.0-r3:

| | Stock | Trimmed |
| --- | --- | --- |
| Build time | 1.5–2 h | ~17 min |
| Built-in options | 3266 | 2226 |
| Modules | 6373 | ~570 |

## Installation

Run the installer as root. It backs up the existing files to
`/root/kernel-tune-backup-<timestamp>/` before installing the new ones.

```sh
doas ./install.sh
```

Then rebuild the kernel and the NVIDIA driver together:

```sh
emerge -1 sys-kernel/cachyos-kernel x11-drivers/nvidia-drivers
```

## Repository layout

| Path | Installed to | Purpose |
| --- | --- | --- |
| `etc/kernel/config.d/10-hardware-trim.config` | `/etc/kernel/config.d/` | Disables hardware support that is never used here: other GPUs, server NICs, InfiniBand, TV/DVB, staging drivers. |
| `etc/kernel/config.d/20-no-debug-info.config` | `/etc/kernel/config.d/` | Disables DWARF debug info, which the ebuild strips anyway. Also disables BTF and sched_ext. |
| `etc/kernel/config.d/30-server-localmod.config` | `/etc/kernel/config.d/` | Generated. Disables every module this host does not use. |
| `etc/kernel/config.d/40-overrides.config` | `/etc/kernel/config.d/` | Manual overrides: QXL replaces amdgpu as the TTM helper provider for NVIDIA; Intel QAT disabled. |
| `etc/portage/package.use/cachyos-kernel` | `/etc/portage/package.use/` | Sets `-autofdo -propeller`. No profile is available, so these flags only add build cost. |
| `etc/portage/env/kernel-jobs.conf` | `/etc/portage/env/` and `package.env` | Builds the kernel with `-j16`. |
| `localmod/` | Not installed | Generator for the `30-` fragment and its keep lists. |

`kernel-build.eclass` applies `/etc/kernel/config.d/*.config` in name order, after
the CachyOS base config and the ebuild's USE-flag adjustments.

## Module selection

The `30-` fragment keeps:

- every module loaded when the fragment was generated (from `/proc/modules`)
- modules listed in `localmod/keep-modules.txt`: modules loaded on demand, such as
  WireGuard, Docker network drivers, vhost, loop, zram, dm-crypt, and the exFAT,
  NTFS3, ISO 9660, UDF and SquashFS filesystems
- every symbol in the subtrees listed in `localmod/keep-subtrees.txt`: all of
  netfilter and `net/sched`
- symbols listed in `localmod/keep-configs.txt`: options localmodconfig cannot map
  to a loaded module, such as Lenovo WMI and the CUBIC and BBR TCP congestion
  control algorithms

All other modules are disabled, including USB serial and Ethernet adapters, game
controllers, most vendor HID drivers, amdgpu, NFS, CIFS, MD RAID and VFIO.
Built-in options are not changed, so boot-critical support (NVMe, AHCI, Btrfs,
ext4, USB HID, FUSE) is unaffected.

## Known issues

- `nvidia-drivers` requires `DRM_TTM_HELPER`, which can only be selected by an
  in-tree DRM driver. localmodconfig keeps amdgpu for this purpose, which is the
  largest driver in the tree. `40-overrides.config` enables the much smaller
  `DRM_QXL` instead. Because amdgpu, i915 and xe are all disabled, `nvidia-drm` is
  built without HDCP support; it checks
  `IS_ENABLED(CONFIG_DRM_DISPLAY_HDCP_HELPER)`.
- Reinstalling the same kernel version leaves modules from the previous build in
  `/lib/modules/<version>`. Remove any `.ko` files not listed in the package's
  `CONTENTS` file, then run `depmod`.

## Adding hardware support

If a device stops working, or new hardware is added:

1. Add the module name to `localmod/keep-modules.txt`, or the config symbol to
   `localmod/keep-configs.txt`.
2. Regenerate the fragment (see below).
3. Run `install.sh` and rebuild the kernel.

## Regenerating the module fragment

The fragment only disables modules. Modules added in newer kernels keep the
CachyOS default (built as modules) until the fragment is regenerated, so
regenerate it after a major kernel version update.

Run this while the host's normal workload (Docker, VPNs) is active, so that
`/proc/modules` reflects actual use.

```sh
EB=/var/db/repos/CachyOS-kernels/sys-kernel/cachyos-kernel/cachyos-kernel-<ver>.ebuild
W=/var/tmp/notmpfs/portage/sys-kernel/cachyos-kernel-<ver>/work

# The base config must be generated without the existing fragment.
doas mv /etc/kernel/config.d/30-server-localmod.config /root/
doas env PORTAGE_TMPDIR=/var/tmp/notmpfs ebuild $EB clean configure

mkdir -p /tmp/k/src && doas tar -C $W/cachyos-* -cf - . | tar -C /tmp/k/src -xf -
doas cat $W/modprep/.config > /tmp/k/base.config
./localmod/gen-fragment.sh /tmp/k/src /tmp/k/base.config etc/kernel/config.d/30-server-localmod.config

doas ./install.sh && doas env PORTAGE_TMPDIR=/var/tmp/notmpfs ebuild $EB clean
```
