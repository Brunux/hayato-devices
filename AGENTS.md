# AGENTS.md — `lazyos-devices`

## Scope
Hardware board definitions (`devices/<codename>/`) and Linux kernel families (`kernels/<flavor>/`).
Kept independent of OS userland assembly (`lazyos-core`) and desktop UI (`lazyos-desktop`) so an
LLM or contributor can add or update a board inside a small, self-contained repository.

## Kernel Families (`kernels/`)
- **`debian-arm64`**: Uses Debian `forky`'s stock `linux-image-arm64` package (`kernels/debian-arm64/package` -> `KERNEL_SOURCE_TYPE="debian-pkg"`). Used by generic `arm64-uefi` and `arm64-extlinux` targets: skips kernel compilation (`build-kernel.sh` exits `0`), resolves `KERNEL_RELEASE` from installed `/lib/modules/*`, syncs DTBs from `/usr/lib/linux-image-*` to `/boot/dtbs/`, and stays updated on live devices via `apt upgrade` + `/etc/kernel/postinst.d/zz-lazyos-boot`.
- **`arm64-mainline`**: Preferred source-built target for custom mainline ARM64 boards needing bespoke config fragments or out-of-tree patches.
  - Never copy a 250 KB full `.config` per new board.
  - Put shared LazyOS OS requirements in `kernels/arm64-mainline/base.config` (`HZ_1000`, `PREEMPT`,
    `LRU_GEN_ENABLED`, `SCHEDUTIL`, `ZRAM`+`LZ4`/`ZSTD`, `KYBER`, `THP=madvise`, `systemd` cgroups/PSI).
  - Put SoC/vendor drivers in reusable `kernels/arm64-mainline/fragments/<soc>.config`.
  - List fragment names (without `.config`) in `devices/<board>/kernel-fragments` and optional
    board-specific toggles in `devices/<board>/kernel.config`.
  - `scripts/build-kernel.sh` merges `defconfig` + `base.config` + fragments via
    `scripts/kconfig/merge_config.sh`, then runs `olddefconfig` and checks for config drift.
- **`mediatek-mt81`**: Custom source config (`7.2.7` + 8 out-of-tree patches including `mt8183-fix-bluetooth.patch` + strict `HZ=1000` / `MGLRU` / `schedutil` assertions in `check-device.sh`) shared by `google-asurada` (MT8192) and `google-kukui` (MT8183) ChromeOS families.
  - Because Debian `firmware-atheros` packages `qca/nvm_00440302_i2s_eu.bin` without `qca/nvm_00440302_i2s.bin` and `alsa-ucm-conf` ships `conf.d/mt8183_da7219_r` without the 15-char truncated `conf.d/mt8183_da7219_m` entry (`mt8183_da7219_max98357`), `devices/google-kukui/files/` supplies both relative symlinks rather than pushing board quirks into `lazyos-core` or `lazyos-desktop`.

## How to Add a New Mainline Board (6 Steps)
See [`PORTING-PMOS-NURA.md`](PORTING-PMOS-NURA.md) for the complete postmarketOS / Nura Linux porting checklist (`pmaports`, `depthcharge-tools` `boards.ini`, Debian `forky` firmware/UCM2 pitfalls, and `lazyos installer` compatibility).

1. Copy `devices/_template/` to `devices/<codename>/` (match `deviceinfo_codename`).
2. Fill `deviceinfo`:
   - `deviceinfo_arch="aarch64"` (or `x86_64`)
   - `deviceinfo_boot_type="extlinux"` | `"uefi"` | `"depthcharge"`
   - `deviceinfo_dtb="<vendor>/<board>*.dtb"` (leave empty for ACPI-only UEFI machines)
   - For Depthcharge Chromebooks also set `deviceinfo_cgpt_kpart_start`,
     `deviceinfo_cgpt_kpart_size`, `deviceinfo_depthcharge_arch`, `deviceinfo_depthcharge_board`,
     `deviceinfo_depthcharge_compression`.
3. Keep `devices/<codename>/kernel` set to `arm64-mainline` and list required SoC fragments in
   `devices/<codename>/kernel-fragments` (or add a minimal fragment under
   `kernels/arm64-mainline/fragments/`).
4. Add early boot modules to `modules-initfs`, cmdline flags to `kernel-cmdline.conf`, and firmware /
   boot packages to `packages.list`.
5. Place any board-only udev rules, systemd services, keyd maps, ALSA UCM configs, or resume hooks
   under `devices/<codename>/files/` matching target `/` paths. Do **not** push hardware workarounds
   into `lazyos-desktop` or `lazyos-core`.
6. Write hardware verification checks in `devices/<codename>/check-device.sh` (`chmod +x`), using
   the helper API (`section`, `ok`, `warn`, `fail`, `skip`, `info`, `have`, `asroot`, `check_svc`)
   installed as `/usr/libexec/lazyos/check/20-device.sh`.

## Rules
- Every patch listed in `kernels/<flavor>/patches/series` must exist on disk and apply cleanly.
- All files under `devices/<board>/files/usr/local/{bin,sbin}` and `check-device.sh` must be `0755`.
- Run `./scripts/validate-devices.sh` before committing; `.github/workflows/devices.yml` enforces it.
- Keep commits and docs in English. Never embed hardcoded home paths inside `devices/<board>/files/`.
