#!/bin/bash
# Board hardware checks for google-kukui (Google Kukui / Krane / Kodama / Kakadu / Katsu / Jacuzzi, MT8183).
# Sourced/executed as /usr/libexec/hayato/check/20-device.sh by check-system.sh.
# shellcheck shell=bash

section "Device: google-kukui (Boot & DTB)"

_compat=""
if [ -r /proc/device-tree/compatible ]; then
	_compat="$(tr '\0' ',' </proc/device-tree/compatible 2>/dev/null || true)"
fi
case "$_compat" in
*mediatek,mt8183*)
	ok "device-tree compatible: ${_compat%,}"
	;;
"")
	warn "no /proc/device-tree/compatible (container/chroot?)"
	;;
*)
	fail "unexpected device-tree compatible '$_compat' for google-kukui (expected mediatek,mt8183)"
	;;
esac

if grep -qE '(^|[[:space:]])kern_guid=' /proc/cmdline 2>/dev/null; then
	ok "booted via Depthcharge (kern_guid present on kernel cmdline)"
else
	warn "kern_guid absent from /proc/cmdline: Depthcharge active-partition lookup unavailable"
fi

_kukui_dtbs="$(find /boot/dtbs/mediatek -maxdepth 1 -name 'mt8183-kukui*.dtb' 2>/dev/null | wc -l || echo 0)"
if [ "$_kukui_dtbs" -ge 1 ]; then
	ok "$_kukui_dtbs mt8183-kukui DTB(s) staged under /boot/dtbs/mediatek"
else
	warn "no mt8183-kukui*.dtb found under /boot/dtbs/mediatek"
fi

section "Device: google-kukui Storage & MMC IRQs"

if [ -b /dev/mmcblk0 ]; then
	ok "internal eMMC block device /dev/mmcblk0 present"
else
	warn "/dev/mmcblk0 missing (expected on MT8183 eMMC boards)"
fi

if systemctl list-unit-files hayato-irq-balance.service >/dev/null 2>&1; then
	check_svc hayato-irq-balance
else
	warn "hayato-irq-balance.service is not installed"
fi

for _mmc in 11230000.mmc 11240000.mmc; do
	_irq="$(awk -v dev="$_mmc" '$NF == dev {print $1; exit}' /proc/interrupts 2>/dev/null | tr -d ':')"
	if [ -n "$_irq" ] && [ -r "/proc/irq/$_irq/smp_affinity_list" ]; then
		_cpu="$(tr -d ' \t\r\n' <"/proc/irq/$_irq/smp_affinity_list" 2>/dev/null || true)"
		if [ "$_cpu" = "0" ]; then
			warn "$_mmc IRQ $_irq still pinned to CPU0"
		else
			ok "$_mmc IRQ $_irq affinity CPU(s): $_cpu"
		fi
	fi
done

section "Device: google-kukui Display & GPU"

_drm_drivers=""
for _drv in /sys/class/drm/card*/device/driver; do
	[ -L "$_drv" ] || continue
	_drm_drivers="$_drm_drivers $(basename "$(readlink -f "$_drv")")"
done
case "$_drm_drivers" in
*mediatek*|*panfrost*)
	ok "DRM drivers active:$_drm_drivers"
	;;
"")
	warn "no /sys/class/drm/card* drivers discovered"
	;;
*)
	warn "expected mediatek/panfrost DRM drivers, saw:$_drm_drivers"
	;;
esac

_panel_conn=""
for _st in /sys/class/drm/card*-*/status; do
	[ -r "$_st" ] || continue
	_name="$(basename "$(dirname "$_st")")"
	case "$_name" in
	*-eDP-*|*-DSI-*)
		[ "$(cat "$_st" 2>/dev/null)" = "connected" ] && _panel_conn="$_name"
		;;
	esac
done
if [ -n "$_panel_conn" ]; then
	ok "internal panel connected: $_panel_conn"
else
	warn "no connected eDP-* or DSI-* internal panel detected"
fi

section "Device: google-kukui Connectivity & Firmware"

if [ -r /usr/lib/firmware/mediatek/mt8183/scp.img ]; then
	ok "MT8183 SCP firmware present (/usr/lib/firmware/mediatek/mt8183/scp.img)"
else
	fail "missing /usr/lib/firmware/mediatek/mt8183/scp.img (install firmware-mediatek)"
fi

if [ -r /usr/lib/firmware/ath10k/QCA6174/hw3.0/firmware-sdio-6.bin ] || [ -r /usr/lib/firmware/mediatek/WIFI_RAM_CODE_MT7961_1.bin ]; then
	ok "Wi-Fi firmware present for QCA6174 SDIO / MT7921s"
else
	fail "missing Kukui Wi-Fi firmware (install firmware-atheros and firmware-mediatek)"
fi

if [ -r /usr/lib/firmware/qca/nvm_00440302_i2s.bin ] && [ -r /usr/lib/firmware/qca/nvm_00440302_i2s_eu.bin ]; then
	ok "QCA6174 BT I2S NVM firmware present (nvm_00440302_i2s.bin + _eu.bin)"
else
	warn "QCA6174 BT I2S NVM firmware incomplete (expected qca/nvm_00440302_i2s.bin and nvm_00440302_i2s_eu.bin)"
fi

section "Device: google-kukui Audio & UCM2"

if [ -r /usr/share/alsa/ucm2/conf.d/mt8183_da7219_m/mt8183_da7219_m.conf ] &&
	[ -r /usr/share/alsa/ucm2/conf.d/mt8183_da7219_r/mt8183_da7219_r.conf ] &&
	[ -r /usr/share/alsa/ucm2/conf.d/mt8183_mt6358_t/mt8183_mt6358_t.conf ]; then
	ok "ALSA UCM2 profiles staged for mt8183_da7219_{m,r} and mt8183_mt6358_t"
else
	warn "incomplete MT8183 ALSA UCM2 conf.d mappings under /usr/share/alsa/ucm2/conf.d/"
fi

if grep -qiE 'mt8183' /proc/asound/cards 2>/dev/null; then
	ok "MT8183 sound card registered in /proc/asound/cards"
else
	warn "no mt8183 sound card found in /proc/asound/cards"
fi

section "Device: google-kukui Input & Keyd"

if [ -r /etc/keyd/default.conf ]; then
	ok "/etc/keyd/default.conf present"
else
	fail "missing /etc/keyd/default.conf"
fi
if systemctl list-unit-files keyd.service >/dev/null 2>&1; then
	check_svc keyd
fi

section "Device: google-kukui Kernel Optimizations"

_hz="$(zcat /proc/config.gz 2>/dev/null | sed -n 's/^CONFIG_HZ=//p' | head -n1)"
if [ "$_hz" = "1000" ]; then
	ok "CONFIG_HZ=1000"
elif [ -n "$_hz" ]; then
	warn "CONFIG_HZ=$_hz (expected 1000 from mediatek-mt81)"
else
	info "CONFIG_HZ check skipped (/proc/config.gz unreadable)"
fi

if [ -r /sys/kernel/mm/lru_gen/enabled ]; then
	_mglru="$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null || true)"
	case "$_mglru" in
	0x000[1-9a-f]*|[1-9]*) ok "MGLRU enabled ($_mglru)" ;;
	*) fail "MGLRU not active (/sys/kernel/mm/lru_gen/enabled=$_mglru)" ;;
	esac
else
	fail "no /sys/kernel/mm/lru_gen/enabled: mediatek-mt81 requires CONFIG_LRU_GEN"
fi

_gov="$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null || true)"
if [ "$_gov" = "schedutil" ]; then
	ok "CPU governor is schedutil"
elif [ -n "$_gov" ]; then
	warn "CPU governor is '$_gov' (expected schedutil)"
fi
