# `debian-arm64` — Debian Packaged Mainline Kernel

Uses Debian `forky`'s stock `linux-image-arm64` metapackage (`KERNEL_SOURCE_TYPE="debian-pkg"`),
avoiding source compilation for generic ARM64 boards while shipping full upstream drivers, DTBs,
and `apt upgrade` security updates.

- `devices/scripts/build-kernel.sh` skips fetching/compiling Linux when `kernels/<flavor>/package` exists.
- `core/scripts/build-rootfs.sh` installs `linux-image-arm64` from the board's `packages.list`.
- `core/scripts/install-kernel.sh` resolves the installed kernel release dynamically from
  `$ROOTFS/lib/modules/*`, syncs DTBs from `/usr/lib/linux-image-$KERNEL_RELEASE/` to
  `/boot/dtbs/`, injects `modules-initfs`, and regenerates initramfs.
- `/etc/kernel/postinst.d/zz-lazyos-boot` keeps `/boot/dtbs/` and `/boot/efi` or
  `/boot/extlinux/extlinux.conf` updated automatically whenever `apt upgrade` installs a new kernel.
