# `lazyos-devices`

Hardware definitions and Linux kernel recipes for [LazyOS](https://github.com/Brunux/LazyOS).

## Structure

- `kernels/arm64-mainline/` — Pinned Linux mainline LTS recipe with modular `base.config` and
  reusable SoC `fragments/*.config` for new ARM64 boards.
- `kernels/mediatek-mt81/` — Kernel `7.2.7` and MediaTek MT8192/MT8186/MT8183 patches.
- `devices/_template/` — Copy-ready starter template for adding a new board.
- `devices/google-asurada/` — Google Hayato Chromebook (MediaTek MT8192, `depthcharge`).
- `scripts/build-kernel.sh` — Builds and stages a device's kernel (`BUILD_DEB=yes` optional).
- `scripts/validate-devices.sh` — Schema, Kconfig fragment syntax, patch series, and shell check.

## Usage

```sh
# Validate all devices and kernel recipes
./scripts/validate-devices.sh

# Build kernel for a board (default: google-asurada)
DEVICE=google-asurada ./scripts/build-kernel.sh
```
