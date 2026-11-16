# AGENTS.md — `lazyos-devices`

## Scope
Hardware board definitions (`devices/<codename>/`) and Linux kernel families (`kernels/<flavor>/`).
Kept independent of OS userland assembly (`lazyos-core`) and desktop UI (`lazyos-desktop`) so an
LLM or contributor can add or update a board inside a small, self-contained repository.

## Kernel Families (`kernels/`)
- **`arm64-mainline`**: Preferred target for **all new ARM64 boards**.
  - Never copy a 250 KB full `.config` per new board.
  - Put shared LazyOS OS requirements in `kernels/arm64-mainline/base.config` (`HZ_1000`, `PREEMPT`,
    `LRU_GEN_ENABLED`, `SCHEDUTIL`, `ZRAM`+`LZ4`/`ZSTD`, `KYBER`, `THP=madvise`, `systemd` cgroups/PSI).
  - Put SoC/vendor drivers in reusable `kernels/arm64-mainline/fragments/<soc>.config`.
  - List fragment names (without `.config`) in `devices/<board>/kernel-fragments` and optional
    board-specific toggles in `devices/<board>/kernel.config`.
  - `scripts/build-kernel.sh` merges `defconfig` + `base.config` + fragments via
    `scripts/kconfig/merge_config.sh`, then runs `olddefconfig` and checks for config drift.
- **`mediatek-mt81`**: Legacy/custom config (`7.2.7` + 8 out-of-tree patches) for `google-asurada`.

## How to Add a New Mainline Board (6 Steps)
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
