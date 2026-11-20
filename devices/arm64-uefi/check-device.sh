#!/bin/sh
# Board hardware checks for arm64-uefi (Generic ARM64 UEFI / ACPI / EBBR).
# Sourced by /usr/libexec/hayato/check-system.sh.

section "Device: arm64-uefi (UEFI Boot & Kernel)"
if [ -d /sys/firmware/efi ]; then
	ok "UEFI runtime firmware present (/sys/firmware/efi)"
elif [ -r /sys/firmware/devicetree/base/model ]; then
	warn "booted via devicetree without /sys/firmware/efi ($(tr -d '\0' </sys/firmware/devicetree/base/model))"
else
	fail "neither /sys/firmware/efi nor devicetree found"
fi

if [ -r /boot/efi/loader/entries/hayato.conf ]; then
	ok "systemd-boot entry present (/boot/efi/loader/entries/hayato.conf)"
else
	fail "missing /boot/efi/loader/entries/hayato.conf"
fi

if [ -r /boot/efi/EFI/BOOT/BOOTAA64.EFI ] || [ -r /boot/efi/EFI/systemd/systemd-bootaa64.efi ]; then
	ok "UEFI bootloader EFI binary installed"
else
	fail "missing BOOTAA64.EFI / systemd-bootaa64.efi on ESP"
fi

if [ -d /sys/class/drm ]; then
	_cards="$(ls -1 /sys/class/drm 2>/dev/null | grep -E '^card[0-9]+$' | tr '\n' ' ' || true)"
	[ -n "$_cards" ] && ok "DRM display device(s): ${_cards% }" || warn "no DRM card detected under /sys/class/drm"
fi

if have iw; then
	_wl="$(iw dev 2>/dev/null | awk '$1 == "Interface" { print $2; exit }')"
	[ -n "$_wl" ] && ok "Wi-Fi interface detected: $_wl" || info "no wireless interface active"
fi

if [ -r /proc/asound/cards ] && grep -qv '^---' /proc/asound/cards 2>/dev/null; then
	info "ALSA sound cards: $(awk '/^[[:space:]]*[0-9]+/ { print $2 }' /proc/asound/cards 2>/dev/null | tr '\n' ' ')"
fi
