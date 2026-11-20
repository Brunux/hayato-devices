# `arm64-mainline` Kernel Family

Composable mainline Linux configuration for new arm64 targets without duplicating
a 250 KB full `.config` per board.

## Layout

- `version` — Pinned mainline LTS version fetched from `cdn.kernel.org`.
- `base.config` — Hayato OS baseline (`HZ_1000`, MGLRU, `schedutil`, `zram` + `lz4`/`zstd`,
  `kyber`, THP `madvise`, `systemd` cgroup/PSI options, core filesystems, Wayland DRM/HID).
- `fragments/*.config` — Reusable SoC and platform slices (`chromebook-ec`, `rockchip-rk3588`,
  `qcom-laptop`, `rpi5`).
- `patches/series` — Optional upstream backports applied in order.

## How `scripts/build-kernel.sh` merges config

When `kernels/<kernel>/config.<arch>` does not exist, `build-kernel.sh` starts from
the kernel's `defconfig` and merges `base.config`, any fragment listed in the board's
`kernel-fragments` file (one fragment name per line), and an optional board-local
`devices/<board>/kernel.config` via `scripts/kconfig/merge_config.sh`, followed by
`make olddefconfig`.
