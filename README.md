# `lazyos-devices`

Hardware definitions and Linux kernel recipes for [LazyOS](https://github.com/Brunux/LazyOS).

## Structure

- `kernels/debian-arm64/` — Debian `forky` packaged `linux-image-arm64` kernel (`KERNEL_SOURCE_TYPE="debian-pkg"`); skips kernel compilation and stays updated via `apt upgrade` + `/etc/kernel/postinst.d/zz-lazyos-boot`.
- `kernels/arm64-mainline/` — Pinned Linux mainline LTS recipe with modular `base.config` and
  reusable SoC `fragments/*.config` for new ARM64 boards.
- `kernels/mediatek-mt81/` — Kernel `7.2.7` and MediaTek MT8192/MT8186/MT8183 patches (used by `google-asurada` and `google-kukui`).
- `devices/_template/` — Copy-ready starter template for adding a new board.
- `devices/google-asurada/` — Google Hayato Chromebook (MediaTek MT8192, `depthcharge`).
- `devices/google-kukui/` — Google Kukui / Krane / Kodama / Kakadu / Katsu / Jacuzzi Chromebooks (MediaTek MT8183, `depthcharge`).
- `devices/arm64-uefi/` — ARM64 Generic UEFI target (`uefi` boot, `debian-arm64` `linux-image-arm64`).
- `devices/arm64-extlinux/` — ARM64 Generic U-Boot / SBC target (`extlinux` boot, `debian-arm64` `linux-image-arm64`).
- `scripts/build-kernel.sh` — Builds and stages a source kernel (`BUILD_DEB=yes` optional), or exits `0` when using a `debian-pkg` kernel.
- `scripts/validate-devices.sh` — Schema, Kconfig fragment syntax, patch series, and shell check.

## Usage

```sh
# Validate all devices and kernel recipes
./scripts/validate-devices.sh

# Build kernel for a source-built board (default: google-asurada)
DEVICE=google-asurada ./scripts/build-kernel.sh

# Debian-packaged targets (arm64-uefi, arm64-extlinux) skip source compilation
DEVICE=arm64-uefi ./scripts/build-kernel.sh
```
