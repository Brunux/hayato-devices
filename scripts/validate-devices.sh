#!/bin/bash
# Validate device manifests, kernel flavors, fragment syntax, patches, and shell syntax.
set -euo pipefail

LIB_DEVICES_NO_AUTOLOAD=1
. "$(dirname "$0")/lib-devices.sh"

FAIL=0
pass() { printf '  OK    %s\n' "$*"; }
err()  { printf '  FAIL  %s\n' "$*" >&2; FAIL=1; }

log "Checking shell syntax"
while IFS= read -r sh_file; do
	if bash -n "$sh_file"; then
		pass "bash -n ${sh_file#"$DEVICES_REPO/"}"
	else
		err "bash -n failed: $sh_file"
	fi
done < <(find "$DEVICES_REPO/scripts" "$DEVICES_DIR" -type f -name '*.sh' | sort)

log "Checking Kconfig fragments and patch series"
for kdir in "$KERNELS_DIR"/*; do
	[ -d "$kdir" ] || continue
	kname="$(basename "$kdir")"
	[ -f "$kdir/version" ] || err "kernels/$kname: missing version file"
	if [ -f "$kdir/patches/series" ]; then
		while read -r p; do
			case "$p" in '' | '#'*) continue ;; esac
			[ -f "$kdir/patches/$p" ] || err "kernels/$kname/patches/series references missing patch: $p"
		done <"$kdir/patches/series"
		pass "kernels/$kname/patches/series verified"
	fi
	for cfg in "$kdir/base.config" "$kdir/fragments"/*.config; do
		[ -e "$cfg" ] || continue
		bad="$(grep -nEv '^(#.*|[[:space:]]*|CONFIG_[A-Z0-9_]+=(y|m|[0-9]+|0x[0-9a-fA-F]+|"[^"]*"))[[:space:]]*$' "$cfg" || true)"
		if [ -n "$bad" ]; then
			err "invalid Kconfig line in ${cfg#"$DEVICES_REPO/"}: $bad"
		else
			pass "syntax valid: ${cfg#"$DEVICES_REPO/"}"
		fi
	done
done

log "Checking device definitions"
for dev_dir in "$DEVICES_DIR"/*; do
	[ -d "$dev_dir" ] || continue
	dev="$(basename "$dev_dir")"
	if [ "$dev" = "_template" ]; then
		[ -f "$dev_dir/deviceinfo" ] && [ -f "$dev_dir/kernel" ] && [ -f "$dev_dir/check-device.sh" ] ||
			err "_template is incomplete"
		pass "device _template complete"
		continue
	fi

	# Clear per-device variables before loading
	unset deviceinfo_codename deviceinfo_arch deviceinfo_boot_type deviceinfo_dtb deviceinfo_kernel_fragments
	if ! (load_device_context "$dev" >/dev/null 2>&1); then
		err "device $dev failed load_device_context"
		continue
	fi
	load_device_context "$dev"
	[ "${deviceinfo_codename:-}" = "$dev" ] || err "$dev: deviceinfo_codename='${deviceinfo_codename:-}' does not match directory '$dev'"
	case "${deviceinfo_boot_type:-}" in
		depthcharge|uefi|extlinux) pass "$dev: boot_type=${deviceinfo_boot_type}" ;;
		*) err "$dev: unsupported deviceinfo_boot_type='${deviceinfo_boot_type:-}'" ;;
	esac
	[ -f "$dev_dir/check-device.sh" ] || err "$dev: missing check-device.sh"
	[ -x "$dev_dir/check-device.sh" ] || err "$dev: check-device.sh is not executable"
	if [ -d "$dev_dir/files/usr/local/sbin" ] || [ -d "$dev_dir/files/usr/local/bin" ]; then
		while IFS= read -r binf; do
			[ -x "$binf" ] || err "$dev: overlay binary not executable: ${binf#"$DEVICES_REPO/"}"
		done < <(find "$dev_dir/files/usr/local" -type f 2>/dev/null || true)
	fi
	pass "device $dev validated ($KERNEL_FLAVOR $KERNEL_VERSION, $ARCH, mode=$KERNEL_CONFIG_MODE)"
done

[ "$FAIL" -eq 0 ] || exit 1
log "All lazyos-devices checks passed"
