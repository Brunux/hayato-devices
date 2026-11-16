#!/bin/sh
# Board hardware checks for arm64-extlinux (Generic U-Boot / SBC).
# Sourced by /usr/libexec/lazyos/check-system.sh.

section "Device: arm64-extlinux (U-Boot / Devicetree)"
if [ -r /sys/firmware/devicetree/base/model ]; then
	ok "device tree: $(tr -d '\0' </sys/firmware/devicetree/base/model)"
elif [ -d /sys/firmware/efi ]; then
	ok "UEFI firmware present"
else
	fail "no devicetree model in /sys/firmware/devicetree/base/model"
fi

if [ -r /boot/extlinux/extlinux.conf ]; then
	ok "extlinux entry present (/boot/extlinux/extlinux.conf)"
else
	fail "missing /boot/extlinux/extlinux.conf"
fi

if [ -d /boot/dtbs ] && find /boot/dtbs -type f -name '*.dtb' | head -n1 | grep -q .; then
	ok "DTB tree installed under /boot/dtbs"
else
	warn "no .dtb files found under /boot/dtbs"
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
