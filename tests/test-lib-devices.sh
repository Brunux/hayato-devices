#!/bin/bash
# Unit tests for scripts/lib-devices.sh: board context loading, kernel flavors,
# fragment ordering and the release name. Every case uses a throwaway tree.
set -u
cd "$(dirname "$0")/.." || exit 1
. tests/harness.sh

ROOT="$(pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export DEVICES_DIR="$TMP/devices"
export KERNELS_DIR="$TMP/kernels"
export BUILD_ROOT="$TMP/build"
export LIB_DEVICES_NO_AUTOLOAD=1
# shellcheck disable=SC1091
. "$ROOT/scripts/lib-devices.sh"

# make_monolithic <device> <arch>
make_monolithic() {
	local dev="$1" arch="$2"
	mkdir -p "$DEVICES_DIR/$dev" "$KERNELS_DIR/arm64-mainline"
	printf 'arm64-mainline\n' >"$DEVICES_DIR/$dev/kernel"
	printf 'deviceinfo_codename="%s"\ndeviceinfo_arch="%s"\ndeviceinfo_boot_type="extlinux"\n' \
		"$dev" "$arch" >"$DEVICES_DIR/$dev/deviceinfo"
	printf '6.12.28\n' >"$KERNELS_DIR/arm64-mainline/version"
	printf 'CONFIG_LOCALVERSION="-hayato"\nCONFIG_PREEMPT=y\n' \
		>"$KERNELS_DIR/arm64-mainline/config.aarch64"
}

# --- a monolithic config.aarch64 kernel -----------------------------------
make_monolithic board-a aarch64
(
	load_device_context board-a
	assert_eq "board-a" "$DEVICE" "the device name is recorded"
	assert_eq "$DEVICES_DIR/board-a" "$DEVICE_DIR" "the device directory is recorded"
	assert_eq "aarch64" "$ARCH" "the architecture is read"
	assert_eq "arm64" "$KERNEL_ARCH" "aarch64 maps to arm64"
	assert_eq "extlinux" "$BOOT_TYPE" "the boot type is read"
	assert_eq "arm64-mainline" "$KERNEL_FLAVOR" "the kernel flavor is read"
	assert_eq "source" "$KERNEL_SOURCE_TYPE" "config.aarch64 means source-built"
	assert_eq "monolithic" "$KERNEL_CONFIG_MODE" "a full config is monolithic"
	assert_eq "6.12.28" "$KERNEL_VERSION" "the version is read"
	assert_eq "6.12.28-hayato" "$KERNEL_RELEASE" "release is version plus CONFIG_LOCALVERSION"
	assert_eq "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.28.tar.xz" \
		"$KERNEL_URL" "the tarball URL uses the kernel's major series"
	assert_eq "0" "${#KERNEL_FRAGMENTS[@]}" "a monolithic kernel has no extra fragments"
)

# --- base.config plus fragments, in the documented order ------------------
mkdir -p "$DEVICES_DIR/board-frag" "$KERNELS_DIR/frag-kernel/fragments"
printf 'frag-kernel\n' >"$DEVICES_DIR/board-frag/kernel"
printf 'deviceinfo_codename="board-frag"\ndeviceinfo_arch="aarch64"\ndeviceinfo_boot_type="depthcharge"\ndeviceinfo_kernel_fragments="extra"\n' \
	>"$DEVICES_DIR/board-frag/deviceinfo"
printf 'soc\n# a comment\n' >"$DEVICES_DIR/board-frag/kernel-fragments"
printf 'CONFIG_BOARD=y\n' >"$DEVICES_DIR/board-frag/kernel.config"
printf '6.12.28\n' >"$KERNELS_DIR/frag-kernel/version"
printf 'CONFIG_LOCALVERSION="-frag"\n' >"$KERNELS_DIR/frag-kernel/base.config"
printf 'CONFIG_SOC=y\n' >"$KERNELS_DIR/frag-kernel/fragments/soc.config"
printf 'CONFIG_EXTRA=y\n' >"$KERNELS_DIR/frag-kernel/fragments/extra.config"
(
	load_device_context board-frag
	assert_eq "fragments" "$KERNEL_CONFIG_MODE" "base.config selects fragment mode"
	assert_eq "extra soc" "$KERNEL_FRAGMENT_LIST" "deviceinfo fragments come before kernel-fragments"
	assert_eq "4" "${#KERNEL_FRAGMENTS[@]}" "base, extra, soc and the board config are merged"
	assert_eq "$KERNELS_DIR/frag-kernel/base.config" "${KERNEL_FRAGMENTS[0]}" \
		"base.config is merged first"
	assert_eq "$KERNELS_DIR/frag-kernel/fragments/extra.config" "${KERNEL_FRAGMENTS[1]}" \
		"deviceinfo_kernel_fragments is merged second"
	assert_eq "$KERNELS_DIR/frag-kernel/fragments/soc.config" "${KERNEL_FRAGMENTS[2]}" \
		"kernel-fragments is merged third"
	assert_eq "$DEVICES_DIR/board-frag/kernel.config" "${KERNEL_FRAGMENTS[3]}" \
		"the board config is merged last"
	assert_eq "6.12.28-frag" "$KERNEL_RELEASE" "the base config supplies the localversion"
)

# A fragment named but not on disk is a hard error.
printf 'deviceinfo_codename="board-frag"\ndeviceinfo_arch="aarch64"\ndeviceinfo_boot_type="depthcharge"\ndeviceinfo_kernel_fragments="ghost"\n' \
	>"$DEVICES_DIR/board-frag/deviceinfo"
expect_status 1 "a missing kernel fragment is refused" load_device_context board-frag

# --- a packaged Debian kernel ---------------------------------------------
mkdir -p "$DEVICES_DIR/board-deb" "$KERNELS_DIR/debian-arm64"
printf 'debian-arm64\n' >"$DEVICES_DIR/board-deb/kernel"
printf 'deviceinfo_codename="board-deb"\ndeviceinfo_arch="aarch64"\ndeviceinfo_boot_type="uefi"\n' \
	>"$DEVICES_DIR/board-deb/deviceinfo"
printf '7.2.15\n' >"$KERNELS_DIR/debian-arm64/version"
printf 'linux-image-arm64\n' >"$KERNELS_DIR/debian-arm64/package"
(
	load_device_context board-deb
	assert_eq "debian-pkg" "$KERNEL_SOURCE_TYPE" "a package marker selects the Debian kernel"
	assert_eq "debian-pkg" "$KERNEL_CONFIG_MODE" "a packaged kernel has no local config mode"
	assert_eq "debian-pkg" "$KERNEL_RELEASE" "the release is resolved from the rootfs later"
	assert_eq "linux-image-arm64" "$KERNEL_PACKAGE" "the package name is read"
	assert_eq "" "$KERNEL_CONFIG" "a packaged kernel has no source config path"
)

# --- architecture mapping --------------------------------------------------
mkdir -p "$DEVICES_DIR/board-x86" "$KERNELS_DIR/any-kernel"
printf 'any-kernel\n' >"$DEVICES_DIR/board-x86/kernel"
printf 'deviceinfo_codename="board-x86"\ndeviceinfo_arch="x86_64"\ndeviceinfo_boot_type="uefi"\n' \
	>"$DEVICES_DIR/board-x86/deviceinfo"
printf '6.10.0\n' >"$KERNELS_DIR/any-kernel/version"
printf 'CONFIG_LOCALVERSION="-any"\n' >"$KERNELS_DIR/any-kernel/base.config"
(
	load_device_context board-x86
	assert_eq "x86_64" "$KERNEL_ARCH" "x86_64 maps to itself"
)
mkdir -p "$DEVICES_DIR/board-other"
printf 'any-kernel\n' >"$DEVICES_DIR/board-other/kernel"
printf 'deviceinfo_codename="board-other"\ndeviceinfo_arch="riscv64"\ndeviceinfo_boot_type="uefi"\n' \
	>"$DEVICES_DIR/board-other/deviceinfo"
(
	load_device_context board-other
	assert_eq "riscv64" "$KERNEL_ARCH" "an unknown architecture is passed through"
)

# --- missing pieces are refused with a useful message ---------------------
mkdir -p "$DEVICES_DIR/board-broken" "$KERNELS_DIR/arm64-mainline"
printf 'arm64-mainline\n' >"$DEVICES_DIR/board-broken/kernel"
expect_status 1 "a device without deviceinfo is refused" load_device_context board-broken
expect_status 1 "an unknown device is refused" load_device_context no-such-board

mkdir -p "$DEVICES_DIR/board-nokernel"
printf 'deviceinfo_codename="board-nokernel"\n' >"$DEVICES_DIR/board-nokernel/deviceinfo"
expect_status 1 "a device without a kernel file is refused" load_device_context board-nokernel

mkdir -p "$DEVICES_DIR/board-noversion" "$KERNELS_DIR/no-version"
printf 'no-version\n' >"$DEVICES_DIR/board-noversion/kernel"
printf 'deviceinfo_codename="board-noversion"\n' >"$DEVICES_DIR/board-noversion/deviceinfo"
printf 'CONFIG_LOCALVERSION="-x"\n' >"$KERNELS_DIR/no-version/config.aarch64"
expect_status 1 "a kernel flavor without a version is refused" load_device_context board-noversion

mkdir -p "$DEVICES_DIR/board-noconfig" "$KERNELS_DIR/no-config"
printf 'no-config\n' >"$DEVICES_DIR/board-noconfig/kernel"
printf 'deviceinfo_codename="board-noconfig"\n' >"$DEVICES_DIR/board-noconfig/deviceinfo"
printf '6.1.0\n' >"$KERNELS_DIR/no-config/version"
expect_status 1 "a kernel flavor with neither config nor base.config is refused" \
	load_device_context board-noconfig

# --- the boot type defaults to depthcharge --------------------------------
mkdir -p "$DEVICES_DIR/board-default" "$KERNELS_DIR/arm64-mainline"
printf 'arm64-mainline\n' >"$DEVICES_DIR/board-default/kernel"
printf 'deviceinfo_codename="board-default"\ndeviceinfo_arch="aarch64"\n' \
	>"$DEVICES_DIR/board-default/deviceinfo"
(
	load_device_context board-default
	assert_eq "depthcharge" "$BOOT_TYPE" "an absent boot type defaults to depthcharge"
)

# --- package_kernel_deb and package_device_deb build valid .deb archives ---
mkdir -p "$DEVICES_DIR/board-pkg/files/etc/udev/rules.d"
printf 'arm64-mainline\n' >"$DEVICES_DIR/board-pkg/kernel"
printf 'deviceinfo_codename="board-pkg"\ndeviceinfo_arch="aarch64"\ndeviceinfo_boot_type="depthcharge"\n' \
	>"$DEVICES_DIR/board-pkg/deviceinfo"
printf 'quiet loglevel=2\n' >"$DEVICES_DIR/board-pkg/kernel-cmdline.conf"
printf 'nvme\n' >"$DEVICES_DIR/board-pkg/modules-initfs"
printf '#!/bin/bash\ntrue\n' >"$DEVICES_DIR/board-pkg/check-device.sh"
chmod 0755 "$DEVICES_DIR/board-pkg/check-device.sh"
printf '# rule\n' >"$DEVICES_DIR/board-pkg/files/etc/udev/rules.d/99-test.rules"

if command -v dpkg-deb >/dev/null 2>&1; then
	(
		export HAYATO_VERSION="0.6.0"
		export WORK_DIR="$TMP/pkg-work"
		load_device_context board-pkg
		STAGE_MOCK="$TMP/mock-kstage"
		OUT_MOCK="$TMP/mock-debs"
		mkdir -p "$STAGE_MOCK/boot/dtbs/mediatek" "$STAGE_MOCK/lib/modules/$KERNEL_RELEASE" "$OUT_MOCK"
		printf 'kernel-image\n' >"$STAGE_MOCK/boot/vmlinuz-$KERNEL_RELEASE"
		printf 'CONFIG_HZ=1000\n' >"$STAGE_MOCK/boot/config"
		printf 'dtb\n' >"$STAGE_MOCK/boot/dtbs/mediatek/test.dtb"
		ln -s /nonexistent/host/build "$STAGE_MOCK/lib/modules/$KERNEL_RELEASE/build"

		package_kernel_deb "$STAGE_MOCK" "$OUT_MOCK"
		package_device_deb "$OUT_MOCK"

		kdeb="$(ls "$OUT_MOCK"/linux-image-hayato-arm64-mainline_6.12.28+hayato0.6.0-1hayato1_*.deb 2>/dev/null | head -n1)"
		ddeb="$(ls "$OUT_MOCK"/hayato-device-board-pkg_0.6.0-1hayato1_*.deb 2>/dev/null | head -n1)"
		assert_true "kernel .deb is created" test -f "$kdeb"
		assert_true "device .deb is created" test -f "$ddeb"
		assert_contains "$(dpkg-deb -I "$kdeb")" "Provides: linux-image-6.12.28-hayato" "kernel .deb provides linux-image-<release>"
		assert_contains "$(dpkg-deb -c "$kdeb")" "./usr/lib/linux-image-6.12.28-hayato/mediatek/test.dtb" "kernel .deb ships DTBs in /usr/lib/linux-image-<release>"
		assert_false "kernel .deb strips host build symlink" bash -c "dpkg-deb -c '$kdeb' | grep -q '/lib/modules/$KERNEL_RELEASE/build'"
		assert_contains "$(dpkg-deb -c "$ddeb")" "./etc/hayato/deviceinfo" "device .deb ships /etc/hayato/deviceinfo"
		assert_contains "$(dpkg-deb -c "$ddeb")" "./usr/libexec/hayato/check/20-device.sh" "device .deb ships 20-device.sh"
	)
fi

finish
