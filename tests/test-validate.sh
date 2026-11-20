#!/bin/bash
# Negative-case tests for scripts/validate-devices.sh: each case starts from a
# valid throwaway devices tree, breaks one rule, and asserts the validator fails
# with the message a maintainer would need.
set -u
cd "$(dirname "$0")/.." || exit 1
. tests/harness.sh

ROOT="$(pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Copy the validator and its library so DEVICES_REPO resolves to the throwaway
# tree, not to this checkout.
mkdir -p "$TMP/scripts"
cp "$ROOT/scripts/lib-devices.sh" "$ROOT/scripts/validate-devices.sh" "$TMP/scripts/"

reset_tree() {
	rm -rf "$TMP/devices" "$TMP/kernels"
	mkdir -p "$TMP/devices/good" "$TMP/kernels/arm64-mainline"
	printf 'arm64-mainline\n' >"$TMP/devices/good/kernel"
	printf 'deviceinfo_codename="good"\ndeviceinfo_arch="aarch64"\ndeviceinfo_boot_type="depthcharge"\n' \
		>"$TMP/devices/good/deviceinfo"
	printf '6.12.28\n' >"$TMP/kernels/arm64-mainline/version"
	printf 'CONFIG_LOCALVERSION="-hayato"\nCONFIG_PREEMPT=y\n' \
		>"$TMP/kernels/arm64-mainline/config.aarch64"
	printf '#!/bin/bash\ntrue\n' >"$TMP/devices/good/check-device.sh"
	chmod +x "$TMP/devices/good/check-device.sh"
}

# check_validate EXPECTED WHAT [MESSAGE]: run the validator from the throwaway
# tree and assert both the status and, optionally, one line of its output.
check_validate() {
	local expected="$1" what="$2" needle="${3:-}"
	local out status
	out="$(
		cd "$TMP" &&
			env -u DEVICES_REPO -u DEVICES_DIR -u KERNELS_DIR -u DEVICE \
				-u BUILD_ROOT -u WORK_DIR -u SRC_DIR -u KERNEL_STAGE \
				bash scripts/validate-devices.sh 2>&1
	)"
	status=$?
	assert_eq "$expected" "$status" "$what"
	if [ -n "$needle" ]; then
		assert_contains "$out" "$needle" "$what (message)"
	fi
}

# --- a valid tree passes ---------------------------------------------------
reset_tree
check_validate 0 "a valid tree passes" "All hayato-devices checks passed"

# --- an invalid Kconfig line ----------------------------------------------
reset_tree
printf 'CONFIG_BROKEN=not a value\n' >>"$TMP/kernels/arm64-mainline/base.config"
check_validate 1 "an invalid Kconfig line fails" "invalid Kconfig line"

# A quoted value, a number and a hex value are valid.
reset_tree
printf 'CONFIG_STR="hello world"\nCONFIG_NUM=42\nCONFIG_HEX=0x1a\n# a comment\n' \
	>>"$TMP/kernels/arm64-mainline/base.config"
check_validate 0 "quoted, numeric and hex Kconfig values pass"

# --- a patch series that names a missing file -----------------------------
reset_tree
mkdir -p "$TMP/kernels/arm64-mainline/patches"
printf 'missing.patch\n# a comment\n' >"$TMP/kernels/arm64-mainline/patches/series"
check_validate 1 "a patch series naming a missing file fails" "references missing patch"

reset_tree
mkdir -p "$TMP/kernels/arm64-mainline/patches"
printf 'present.patch\n' >"$TMP/kernels/arm64-mainline/patches/series"
printf 'diff\n' >"$TMP/kernels/arm64-mainline/patches/present.patch"
check_validate 0 "a patch series whose files exist passes"

# --- a kernel flavor missing its version ----------------------------------
reset_tree
rm -f "$TMP/kernels/arm64-mainline/version"
check_validate 1 "a kernel without a version fails" "missing version file"

# --- a kernel flavor with neither package nor config ----------------------
reset_tree
rm -f "$TMP/kernels/arm64-mainline/config.aarch64"
check_validate 1 "a kernel with no package, base.config or config fails" \
	"needs package, base.config, or config.<arch>"

# --- an empty package marker ----------------------------------------------
reset_tree
rm -f "$TMP/kernels/arm64-mainline/config.aarch64"
printf '   \n' >"$TMP/kernels/arm64-mainline/package"
check_validate 1 "an empty package marker fails" "package is empty"

# --- the codename must match the directory --------------------------------
reset_tree
printf 'deviceinfo_codename="other"\ndeviceinfo_arch="aarch64"\ndeviceinfo_boot_type="depthcharge"\n' \
	>"$TMP/devices/good/deviceinfo"
check_validate 1 "a codename that does not match the directory fails" \
	"does not match directory"

# --- the boot type must be one of the three backends ----------------------
reset_tree
printf 'deviceinfo_codename="good"\ndeviceinfo_arch="aarch64"\ndeviceinfo_boot_type="bios"\n' \
	>"$TMP/devices/good/deviceinfo"
check_validate 1 "an unsupported boot type fails" "unsupported deviceinfo_boot_type"

# --- check-device.sh must exist and be executable -------------------------
reset_tree
rm -f "$TMP/devices/good/check-device.sh"
check_validate 1 "a device without check-device.sh fails" "missing check-device.sh"

reset_tree
chmod 644 "$TMP/devices/good/check-device.sh"
check_validate 1 "a non-executable check-device.sh fails" "check-device.sh is not executable"

# --- _template must be complete -------------------------------------------
reset_tree
mkdir -p "$TMP/devices/_template"
printf 'deviceinfo_codename="_template"\n' >"$TMP/devices/_template/deviceinfo"
check_validate 1 "an incomplete _template fails" "_template is incomplete"

# --- every device shell file must parse -----------------------------------
reset_tree
printf 'if [\n' >"$TMP/devices/good/broken.sh"
check_validate 1 "a device shell file with a syntax error fails" "bash -n failed"

# --- overlay binaries must be executable ----------------------------------
reset_tree
mkdir -p "$TMP/devices/good/files/usr/local/bin"
printf '#!/bin/sh\ntrue\n' >"$TMP/devices/good/files/usr/local/bin/tool"
chmod 644 "$TMP/devices/good/files/usr/local/bin/tool"
check_validate 1 "a non-executable overlay binary fails" "overlay binary not executable"

# --- a device whose kernel flavor cannot be loaded ------------------------
reset_tree
printf 'no-such-flavor\n' >"$TMP/devices/good/kernel"
check_validate 1 "a device naming a missing kernel flavor fails" \
	"failed load_device_context"

finish
