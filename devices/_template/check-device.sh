#!/bin/sh
# Board hardware witness checks (installed to /usr/libexec/lazyos/check/20-device.sh).
# Sourced by check-system.sh, which supplies: section, ok, warn, fail, skip, info, have, asroot, check_svc.

section "Device: ${DEVICE:-unknown}"
if [ -r /sys/firmware/devicetree/base/model ]; then
	ok "device tree: $(tr -d '\0' </sys/firmware/devicetree/base/model)"
elif [ -d /sys/firmware/efi ]; then
	ok "UEFI firmware present"
fi
