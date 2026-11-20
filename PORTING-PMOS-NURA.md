# Porting Devices from postmarketOS & Nura Linux to Hayato

This guide captures verified findings and conventions from porting `google-asurada` (MT8192)
and `google-kukui` (MT8183) from postmarketOS (`pmaports`) and Nura Linux (`nura/pmaports`,
`ondev2`, and `pmbootstrap`) into `hayato-devices`. Use it as the checklist when adding new
ARM64 boards or Chromebooks.

---

## 1. Upstream Sources to Inspect First

For a target board `<vendor>-<codename>` in `pmaports` (postmarketOS / Nura):

1. `device/community/device-<vendor>-<codename>/` (or `device/testing/`):
   - `deviceinfo` -> architecture, DTB glob, image sizes, and Depthcharge / bootloader parameters.
   - `APKBUILD` -> package dependencies (`firmware-*`, `alsa-ucm-conf*`, `keyd`), initramfs hooks,
     udev rules, systemd units, and post-install notes.
   - `modules-initfs` -> early-boot kernel modules (panels, bridges, touchscreens, Type-C/EC,
     remoteproc, USB storage).
2. Shared SoC package `device/community/soc-<vendor>-<soc>/` and `postmarketos-cros-common` (for
   Chromebooks).
3. Kernel recipe `main/linux-postmarketos-<family>/` or distro kernel packaging:
   - `config.<arch>` + out-of-tree `*.patch` series required for hardware regressions.
4. `depthcharge-tools` board metadata (installed at `/usr/lib/python3/dist-packages/depthcharge_tools/boards.ini`):
   - Confirms `codename`, `dt-compatible`, `hwid-match`, and `image-max-size` caps per board.

> **Upstream Nura `ondev2` vs `pmbootstrap` Finding**
> When inspecting Nura's `ondev2` (`src/install_steps.c`), `od2_install_step_create_partition_table_cgpt()`
> was still unimplemented (`return -1`), while Nura wiki ChromeOS crosh slot-overwrite instructions
> reference `Nura_boot` / `Nura_root` labels. For full standalone GPT partitioning on Depthcharge
> Chromebooks, `pmbootstrap` (`pmb/install/partition.py`, `pmb/install/format.py`) and Hayato
> (`core/scripts/lib-cgpt.sh`, `hayato installer`) both use the standard 3-partition layout
> (`pmOS_kernel`, `pmOS_boot`, `pmOS_root`) with `-S 1 -T 5 -P 10`.

---

## 2. Creating `devices/<codename>/`

Start from `devices/_template/` and preserve the exact schema expected by
`devices/scripts/validate-devices.sh`, `core/scripts/lib.sh`, and `hayato installer`.

| File | Purpose in Hayato |
|---|---|
| `deviceinfo` | Hardware and bootloader metadata (double quotes only; parsed by both Bash and Rust) |
| `kernel` | Kernel flavor name under `kernels/` (`mediatek-mt81`, `arm64-mainline`, or `debian-arm64`) |
| `kernel-fragments` | Optional lines naming `kernels/<flavor>/fragments/<name>.config` |
| `kernel.config` | Optional board-only Kconfig delta merged after fragments |
| `kernel-cmdline.conf` | Kernel command-line tokens appended before `root=UUID=...` (always end with newline or relies on `make-kpart.sh` space normalization) |
| `modules-initfs` | Early-boot module list (`#` comments allowed) |
| `packages.list` | Debian `forky` packages needed on target (firmware, boot tools, `keyd`, `i2c-tools`, etc.) |
| `check-device.sh` | Executable (`0755`) runtime hardware audit installed to `/usr/libexec/hayato/check/20-device.sh` |
| `files/` | Target `/` overlay for board-specific udev rules, `keyd` maps, UCM2 symlinks, firmware links, and IRQ scripts |

### `deviceinfo` Rules
- `deviceinfo_codename` **must match** the directory name under `devices/devices/`.
- `deviceinfo_boot_type` selects one of the three `core/boot/` backends:
  - `"depthcharge"` (ChromeOS `cgpt` + `depthchargectl`)
  - `"uefi"` (GPT `hayato_efi` `vfat` ESP + `systemd-boot`)
  - `"extlinux"` (U-Boot SBC GPT `hayato_boot` starting at `deviceinfo_extlinux_start_mib`, default `16`)
- Leave `deviceinfo_dtb=""` only for ACPI-only UEFI targets (`arm64-uefi`) or multi-DTB generic targets using `/boot/dtbs/` syncing. For board builds, set e.g. `deviceinfo_dtb="mediatek/mt8183-kukui*"`.
- On dual-MMC Chromebooks where both eMMC and SD/USB readers may report `RM=0`, set `deviceinfo_install_target="/dev/mmcblk0"` so the installer defaults to internal storage while still blocking active media via `check_machine_safety()`.

---

## 3. Kernel Family & Kconfig Decisions

- **`mediatek-mt81`**: Custom `7.2.7` source tree with MediaTek MT8192/MT8183/MT8186 patches
  (including `mt8183-fix-bluetooth.patch`, which restores v5.17 `8250_mtk.c` UART flow control for
  MT8183 Bluetooth). Both `google-asurada` and `google-kukui` share this compiled stage.
- **`arm64-mainline`**: Preferred template for new ARM64 boards. Merges upstream `defconfig` +
  `kernels/arm64-mainline/base.config` (Hayato tuning: `HZ_1000`, MGLRU, `schedutil`, `zram`, `kyber`,
  THP `madvise`, systemd cgroups/PSI) + SoC fragments (`fragments/*.config`) + optional board `kernel.config`.
- **`debian-arm64`**: Uses Debian `forky` `linux-image-arm64` (`KERNEL_SOURCE_TYPE="debian-pkg"`), upgraded in-place via `apt`.

### Critical Kconfig & Initramfs Checks Before Building
1. **USB live-boot support for tablet/detachable devices lacking microSD** (e.g., Kukui `krane`, `kodama`):
   - Verify `CONFIG_USB_XHCI_MTK=y` (or SoC xHCI driver), `CONFIG_USB_STORAGE=m`, `CONFIG_USB_UAS=m`, and `CONFIG_EXT4_FS=y` in kernel config so USB sticks enumerate reliably.
2. **Early display, touchscreen, EC, Type-C, battery, and remoteproc**:
   - Check `modules-initfs` against built-in vs modular drivers (`drm`, panels, bridges, `atmel_mxt_ts`, `elan_i2c`, `goodix_ts`, `i2c_hid_of*`, `cros_ec_typec`, `mtk_scp`, `sbs_battery`).

---

## 4. Mapping Alpine/pmOS Concepts to Debian `forky`

### Bootloader Packages (Depthcharge)
Alpine's `vboot-utils` + `depthcharge-tools` split differently in Debian `forky`:
- Install **all three** in `packages.list`:
  - `cgpt`
  - `vboot-kernel-utils` (provides `futility`; `vboot-utils` alone omits `futility` and `cgpt`!)
  - `depthcharge-tools` (provides `depthchargectl`)

### Family-Wide `deviceinfo_depthcharge_board` vs `image-max-size`
- In `depthcharge-tools/boards.ini`, individual Chromebook boards sometimes enforce smaller
  FIT limits (for example, `[boards/arm64/mt8183/kukui]` caps `image-max-size = 512 MiB`, while some older Depthcharge targets cap 32 MiB), and board compatibles like `google,asurada` vs `mediatek,mt8192` can differ.
- Setting `deviceinfo_depthcharge_board` to the SoC family (`"mt8183"` or `"mt8192"`) matches root DT compatibles across variants (`kukui`, `krane`, `kodama`, `kakadu`, `katsu`, `jacuzzi-*`), while `core/scripts/make-kpart.sh` stages **only** DTBs matched by `deviceinfo_dtb`. This prevents bloating the FIT image with unrelated vendor DTBs while covering the entire family in one image.

### Firmware Filenames (`non-free-firmware`)
- Compare exact DT `firmware-name` strings and kernel `request_firmware()` logs against Debian packages (`firmware-mediatek`, `firmware-atheros`, `firmware-realtek`, `firmware-qcom-soc`, etc.).
- **Case study (`google-kukui`)**:
  - `mtk_scp` loads `mediatek/mt8183/scp.img` (`firmware-mediatek`).
  - `ath10k` QCA6174 SDIO loads `ath10k/QCA6174/hw3.0/firmware-sdio-6.bin` (`firmware-atheros`).
  - **Missing filename**: Debian's `firmware-atheros` ships `qca/nvm_00440302_i2s_eu.bin` without `qca/nvm_00440302_i2s.bin`. Fix cleanly inside `devices/google-kukui/files/usr/lib/firmware/qca/` with a relative symlink rather than touching `hayato-core`.

### ALSA UCM2 15-Character Card Name Truncation
- ALSA card shortnames truncate at 15 bytes (e.g. `mt8183_da7219_max98357` -> `mt8183_da7219_m`).
- Upstream `alsa-ucm-conf-cros` `0.8` lacked `mt8183` profiles, while Debian `alsa-ucm-conf` shipped `conf.d/mt8183_da7219_r` (`rt1015p`) but omitted `conf.d/mt8183_da7219_m`.
- Stage relative symlinks under `devices/<codename>/files/usr/share/alsa/ucm2/conf.d/` matching the truncated kernel card IDs (`check-device.sh` should test all expected `conf.d/*.conf` paths and `/proc/asound/cards`).

### Keyboard (`keyd`), Detachable Bases, & Switch Exclusions
- ChromeOS keyboards emit action keys on the top row without raw `F1`-`F10` unless mapped via `keyd`.
- Always check `evtest` / `libinput list-devices` for:
  1. USB/pogo detachable VID:PIDs (e.g. Google Hammer `18d1:503c`, `503d`, `5044`, `5050`, `5057`, etc.).
  2. Non-keyboard `cros_ec` event nodes sharing `0000:0000` (lid switch `EV_SW`, tablet-mode switch, headset jack) — exclude their `keyd` ID hashes (e.g. `-0000:0000:c68a2d8e`) so `keyd` never swallows tablet-mode or lid transitions.
  3. Keep lock/sleep (`KEY_SLEEP`) ungrabbed so `systemd-logind` / `swaylock` handle suspend cleanly.

### Internal Panel Outputs (`eDP-*` vs `DSI-*`) & IRQ Balancing
- Clamshell Chromebooks typically expose `eDP-1`, while tablets (`krane`) expose `DSI-1`. Keep desktop panel discovery generic (`eDP-*` | `DSI-*`) in `hayato` rather than board-specific.
- When `cros_ec` or audio IRQs share CPU0 with high-throughput eMMC/SD controllers (`11230000.mmc`, `11240000.mmc`), ship a `hayato-irq-balance` helper + systemd unit in `devices/<codename>/files/` to steer storage IRQs onto another core.

---

## 5. Bootloader & Pure-Rust Installer Contract

When adding a new board, verify all three layers understand its geometry:

1. **Depthcharge GPT & Flashing (`core/scripts/lib-cgpt.sh`)**:
   - Zeros first 34 and last 33 sectors before `parted mktable gpt` (writes protective MBR required by Linux) + `cgpt create`.
   - `p1` `pmOS_kernel` (`-t kernel -S 1 -T 5 -P 10`, >=128 MiB / `262144` sectors on `google-asurada`/`google-kukui`).
   - `p2` `pmOS_boot` (`-t efi`, `ext2`, >=512 MiB floor matching `pmbootstrap` `sanity_check_boot_size`).
   - `p3` `pmOS_root` (`-t data`, `ext4`, ending at `TOTAL - ROOT_START - 33` so secondary GPT is preserved).
   - `core/scripts/make-kpart.sh` invokes `depthchargectl build --root none` (`depthchargectl` injects `kern_guid=%U` itself).
   - Uses `findmnt -rn -S <part>` (never `mountpoint -q`) and requires `udisks2` stopped during partitioning.

2. **Pure-Rust `hayato installer` (`desktop/rust/crates/hayato-cli/src/installer/`)**:
   - **Pre-flight power (`preflight::detect_power_from`)**: inspect `/sys/class/power_supply/*` by `type` (`"Mains"` / `"USB"` + `online == "1"`, `"Battery"` ignoring `scope == "Device"` stylus/HID batteries) with `AC`/`ADP`/`BAT` fallback — ChromeOS boards expose `CROS_USBPD_CHARGER*` and `sbs-*-000b` instead of ACPI `AC`/`BAT0`.
   - **Target safety (`preflight::check_machine_safety`)**: blocks installation onto any disk hosting `/`, `/boot`, `/boot/efi`, or the active `kern_guid` partition in both TUI pre-flight and headless `apply`.
   - **UI labels & diagrams (`installer/ui.rs`)**: dynamically render `cgpt_kpart_size`, `boot_size_mib`, and `boot_filesystem`, and show Depthcharge reboot instructions covering both `"internal disk"` menus (MT8192) and legacy `Ctrl+D` screens (MT8183).

---

## 6. Validation Workflow for Every New Port

1. Validate board files and Kconfig syntax inside `devices/`:
   ```sh
   ./devices/scripts/validate-devices.sh
   ```
2. Validate full umbrella integration (including desktop/core):
   ```sh
   ./build.sh validate
   ```
3. Build rootfs and compressed `.img.xz` for hardware testing:
   ```sh
   DEVICE=<codename> ./build.sh all
   DEVICE=<codename> ./build.sh release /tmp/release-<codename>
   ```
4. Boot on real hardware from microSD or USB (`Ctrl+U` / `"external disk"`), verify `hayato installer --check`, test `check-system.sh` (which executes `20-device.sh`), inspect `dmesg` for missing firmware or UCM2 errors, and record the test output in Umbrella `reports/`.
