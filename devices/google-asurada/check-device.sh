#!/bin/sh
# Board hardware checks for google-asurada (Google Hayato, MT8192).
# Sourced by /usr/libexec/lazyos/check-system.sh (provides section/ok/warn/fail/skip/info/have/asroot/check_svc).

# ---------------------------------------------------------------------------
section "Device: google-asurada (Boot & DTB)"
# ---------------------------------------------------------------------------
CMDLINE="$(cat /proc/cmdline 2>/dev/null || true)"
case "$CMDLINE" in
	*kern_guid=%U*)
		fail "kern_guid=%U was not substituted: depthcharge did not boot this kpart" ;;
	*kern_guid=*)
		ok "depthcharge substituted kern_guid" ;;
	*)
		warn "no kern_guid in the kernel command line" ;;
esac

_guid=""
for _x in $CMDLINE; do
	case "$_x" in
		kern_guid=*) _guid="${_x#kern_guid=}" ;;
	esac
done
if [ -n "$_guid" ]; then
	_kpart_part="$(findfs PARTUUID="$_guid" 2>/dev/null || true)"
	if [ -z "$_kpart_part" ]; then
		fail "kern_guid=$_guid names no partition: nothing to boot from next time"
	else
		ok "kernel partition $_kpart_part (kern_guid=$_guid)"
		if ! have futility; then
			skip "futility not installed (package vboot-kernel-utils): kernel partition not verified"
		elif [ "${PRIV:-no}" != yes ]; then
			skip "sudo -n does not work: futility cannot read $_kpart_part, so the FIT is unverified"
		else
			_fv="$(asroot futility show "$_kpart_part" 2>/dev/null || true)"
			case "$_fv" in
				*'Body verification succeeded'*)
					ok "the kernel partition holds a dev-signed FIT" ;;
				*)
					fail "futility cannot verify a signed kpart in $_kpart_part" ;;
			esac
		fi
	fi
fi

if [ -r /sys/firmware/devicetree/base/model ]; then
	_model="$(tr -d '\0' </sys/firmware/devicetree/base/model)"
	_compat="$(tr '\0' ' ' </sys/firmware/devicetree/base/compatible)"
	case "$_compat" in
		*google,*) ok "device tree: $_model" ;;
		*)         fail "device tree is not a Google Chromebook DTB: $_model ($_compat)" ;;
	esac
else
	fail "/sys/firmware/devicetree/base is missing (booted without a device tree?)"
fi

# ---------------------------------------------------------------------------
section "Device: MT8192 Display, GPU & Type-C Mux"
# ---------------------------------------------------------------------------
if [ -d /sys/module/panfrost ]; then
	ok "panfrost loaded (GPU acceleration available)"
else
	warn "panfrost is not loaded: no GPU acceleration"
fi

_dp=""
for _s in /sys/class/drm/card*-DP-*/status; do
	[ -e "$_s" ] || continue
	_dp="${_s%/status}"
	_dp="${_dp##*/}"
	break
done
if [ -n "$_dp" ]; then
	ok "external display connector $_dp present (DPI and ANX7625 in the DTB)"
else
	fail "no DP connector: the DTB describes no DPI output (mt8192-asurada-external-display.patch)"
fi

if [ -x /usr/local/sbin/lazyos-dp-mux ]; then
	ok "lazyos-dp-mux is executable"
else
	fail "/usr/local/sbin/lazyos-dp-mux is missing or not executable: the Type-C crosspoint is never set"
fi
if grep -qs lazyos-dp-mux /etc/udev/rules.d/90-lazyos-dp-mux.rules 2>/dev/null; then
	ok "udev runs lazyos-dp-mux when a port enters DisplayPort alt mode"
else
	fail "/etc/udev/rules.d/90-lazyos-dp-mux.rules is missing: only the left-hand port reaches the monitor"
fi
if have i2cset; then
	ok "i2cset is installed"
else
	fail "i2cset is missing (i2c-tools): lazyos-dp-mux cannot write the crosspoint"
fi

for _alt in /sys/class/typec/port*-partner/port*-partner.*/; do
	[ -r "$_alt/active" ] || continue
	[ "$(cat "$_alt/active" 2>/dev/null)" = yes ] || continue
	_port="${_alt#/sys/class/typec/}"
	_port="${_port%%-*}"
	case $_port in
		port0) _want=0x21 ;;
		port1) _want=0x12 ;;
		*) continue ;;
	esac
	_bus=""
	for _c in /sys/bus/i2c/devices/*-0058; do
		[ -e "$_c/of_node/ports/port@0/endpoint/bus-type" ] || continue
		_bus="${_c##*/}"
		_bus="${_bus%%-*}"
		break
	done
	_got=0x
	if [ -n "$_bus" ] && have i2cget; then
		if [ "${PRIV:-no}" != yes ]; then
			skip "Type-C crosspoint on $_port (i2cget needs root and sudo -n does not work)"
			continue
		fi
		_got="$(asroot i2cget -f -y "$_bus" 0x2c 0xb4 2>/dev/null || echo 0x)"
	fi
	case $_got in
		"$_want") ok "Type-C crosspoint on $_port ($_got)" ;;
		0x) skip "Type-C crosspoint on $_port (no i2c bus or i2cget here)" ;;
		*) fail "Type-C crosspoint is $_got, not $_want: a monitor on $_port gets no picture" ;;
	esac
done

_dpr=""
for _cand in /usr/local/bin/lazyos-dp-resume "$HOME/.config/bin/lazyos-dp-resume"; do
	[ -x "$_cand" ] && _dpr="$_cand" && break
done
if [ -n "$_dpr" ]; then
	ok "lazyos-dp-resume is executable ($_dpr)"
	if grep -qs 'resolution' "$_dpr"; then
		ok "lazyos-dp-resume retrains the link after writing the crosspoint"
	else
		fail "$_dpr lost its modeset: the crosspoint would be right and the link still dead"
	fi
else
	fail "lazyos-dp-resume is missing or not executable: the monitor keeps its picture only until the first suspend"
fi

# ---------------------------------------------------------------------------
section "Device: MT8192 Input, Sensors, Wireless & Audio"
# ---------------------------------------------------------------------------
if have keyd || have keyd.rvaiya; then
	check_svc keyd "keyd.service is active"
	if grep -rqsE '^[[:space:]]*sleep[[:space:]]*=' /etc/keyd/ 2>/dev/null; then
		fail "keyd maps the sleep key: logind never sees KEY_SLEEP and the Lock key cannot suspend"
	else
		ok "keyd leaves the sleep key alone"
	fi
	if grep -qs '^leftmeta = f20$' /etc/keyd/default.conf 2>/dev/null; then
		ok "keyd maps Alt+Search to F20"
	else
		fail "/etc/keyd/default.conf does not map leftmeta = f20: holding Alt and tapping Search does nothing"
	fi
	if [ "${PRIV:-no}" = yes ]; then
		_match="$(asroot journalctl -u keyd -b --no-pager 2>/dev/null | grep 'DEVICE: match' | tail -1 || true)"
		if [ -n "$_match" ]; then
			ok "keyd matched its keyboard: $(printf '%s' "$_match" | sed 's/.*DEVICE: match *//')"
		else
			warn "keyd logged no 'DEVICE: match' this boot"
		fi
	else
		skip "keyd's journal needs sudo -n here: the matched keyboard is not read"
	fi
else
	fail "keyd is missing: MT8192 top row has no F-keys or VT switching"
fi

_accel=""
for _d in /sys/bus/iio/devices/iio:device*; do
	[ -r "$_d/name" ] || continue
	[ "$(cat "$_d/name" 2>/dev/null)" = cros-ec-accel ] || continue
	[ -r "$_d/in_accel_x_raw" ] && _accel="$_d" && break
done
if [ -n "$_accel" ]; then
	ok "accelerometer present ($_accel, cros-ec-accel) for tablet rotation"
else
	warn "no cros-ec-accel with in_accel_*_raw: tablet mode starts without rotation"
fi

if [ -r /proc/asound/cards ]; then
	_codec="$(grep -oE 'mt[0-9]+[a-z0-9_]*' /proc/asound/cards 2>/dev/null | sort -u | tr '\n' ' ')"
	[ -n "$_codec" ] && ok "ALSA codec: $(printf '%s' "$_codec" | sed 's/ $//')" ||
		warn "no MediaTek codec name in /proc/asound/cards"
fi

# ---------------------------------------------------------------------------
section "Device: MT8192 Storage & IRQ Tuning"
# ---------------------------------------------------------------------------
if [ -r /sys/block/mmcblk0/queue/scheduler ]; then
	case "$(cat /sys/block/mmcblk0/queue/scheduler 2>/dev/null)" in
		*'[kyber]'*) ok "eMMC I/O scheduler: kyber" ;;
		*) warn "eMMC I/O scheduler: $(cat /sys/block/mmcblk0/queue/scheduler 2>/dev/null) (expected [kyber])" ;;
	esac
fi

_mmc_irq=$(awk '$NF == "11f70000.mmc" {print $1; exit}' /proc/interrupts 2>/dev/null | tr -d ':')
if [ -n "$_mmc_irq" ] && [ -r "/proc/irq/$_mmc_irq/smp_affinity_list" ]; then
	_aff=$(cat "/proc/irq/$_mmc_irq/smp_affinity_list" 2>/dev/null)
	case "$_aff" in
		0|0-*) warn "microSD IRQ $_mmc_irq affinity is $_aff (storage traffic will starve CPU0 input processing)" ;;
		*) ok "microSD IRQ $_mmc_irq routed to CPU $_aff (CPU0 input handling protected)" ;;
	esac
fi
