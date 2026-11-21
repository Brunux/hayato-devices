#!/bin/bash
# Shared helpers for hayato-devices kernel builds and board validation.
# Works standalone inside hayato-devices or when sourced/invoked from hayato-core.

[ -n "${_LIB_DEVICES_LOADED:-}" ] && return 0
_LIB_DEVICES_LOADED=1

DEVICES_REPO="${DEVICES_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEVICES_DIR="${DEVICES_DIR:-$DEVICES_REPO/devices}"
KERNELS_DIR="${KERNELS_DIR:-$DEVICES_REPO/kernels}"

DEVICE="${DEVICE:-google-asurada}"
BUILD_ROOT="${BUILD_ROOT:-/var/tmp/hayato-build}"
WORK_DIR="${WORK_DIR:-$BUILD_ROOT/work}"
SRC_DIR="${SRC_DIR:-$BUILD_ROOT/src}"
KERNEL_STAGE="${KERNEL_STAGE:-$BUILD_ROOT/kernel-stage/$DEVICE}"

if ! declare -F log >/dev/null 2>&1; then
	log()  { printf '\033[1;34m[hayato]\033[0m %s\n' "$*"; }
	warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
	die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }
fi

load_device_context() {
	local dev="${1:-$DEVICE}"
	local dev_dir="$DEVICES_DIR/$dev"
	[ -d "$dev_dir" ] || die "unknown device: $dev (expected in $DEVICES_DIR)"
	[ -f "$dev_dir/deviceinfo" ] || die "missing $dev_dir/deviceinfo"
	[ -f "$dev_dir/kernel" ] || die "missing $dev_dir/kernel"

	# shellcheck disable=SC1090
	source "$dev_dir/deviceinfo"

	DEVICE="$dev"
	DEVICE_DIR="$dev_dir"
	ARCH="${deviceinfo_arch:-aarch64}"
	case "$ARCH" in
		aarch64) KERNEL_ARCH="arm64" ;;
		x86_64)  KERNEL_ARCH="x86_64" ;;
		*)       KERNEL_ARCH="$ARCH" ;;
	esac
	BOOT_TYPE="${deviceinfo_boot_type:-depthcharge}"

	KERNEL_FLAVOR="$(tr -d ' \t\r\n' <"$dev_dir/kernel")"
	KERNEL_DIR="$KERNELS_DIR/$KERNEL_FLAVOR"
	[ -d "$KERNEL_DIR" ] || die "kernel flavor not found: $KERNEL_DIR"
	[ -f "$KERNEL_DIR/version" ] || die "missing $KERNEL_DIR/version"

	KERNEL_VERSION="$(tr -d ' \t\r\n' <"$KERNEL_DIR/version")"
	KERNEL_PATCH_DIR="$KERNEL_DIR/patches"

	KERNEL_FRAGMENT_LIST=""
	KERNEL_FRAGMENTS=()

	if [ -f "$KERNEL_DIR/package" ]; then
		KERNEL_SOURCE_TYPE="debian-pkg"
		KERNEL_PACKAGE="$(tr -d ' \t\r\n' <"$KERNEL_DIR/package")"
		KERNEL_TARBALL=""
		KERNEL_URL=""
		KERNEL_SRC=""
		KERNEL_CONFIG=""
		KERNEL_BASE_CONFIG=""
		KERNEL_CONFIG_MODE="debian-pkg"
		KERNEL_LOCALVERSION=""
		KERNEL_RELEASE="${KERNEL_RELEASE:-debian-pkg}"
		return 0
	fi

	KERNEL_SOURCE_TYPE="source"
	KERNEL_PACKAGE=""
	KERNEL_TARBALL="linux-${KERNEL_VERSION}.tar.xz"
	KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_VERSION%%.*}.x/${KERNEL_TARBALL}"
	KERNEL_SRC="${SRC_DIR}/linux-${KERNEL_VERSION}"

	KERNEL_CONFIG="$KERNEL_DIR/config.$ARCH"
	KERNEL_BASE_CONFIG="$KERNEL_DIR/base.config"

	local cfg_for_ver=""
	if [ -f "$KERNEL_CONFIG" ]; then
		KERNEL_CONFIG_MODE="monolithic"
		cfg_for_ver="$KERNEL_CONFIG"
	elif [ -f "$KERNEL_BASE_CONFIG" ]; then
		KERNEL_CONFIG_MODE="fragments"
		cfg_for_ver="$KERNEL_BASE_CONFIG"
		KERNEL_FRAGMENTS+=("$KERNEL_BASE_CONFIG")
		local frag_raw="${deviceinfo_kernel_fragments:-}"
		if [ -f "$dev_dir/kernel-fragments" ]; then
			frag_raw="$frag_raw $(grep -v '^[[:space:]]*#' "$dev_dir/kernel-fragments" || true)"
		fi
		local f frag_path
		for f in $frag_raw; do
			f="${f%.config}"
			frag_path="$KERNEL_DIR/fragments/$f.config"
			[ -f "$frag_path" ] || die "kernel fragment not found for $dev: $frag_path"
			KERNEL_FRAGMENTS+=("$frag_path")
			KERNEL_FRAGMENT_LIST="${KERNEL_FRAGMENT_LIST:+$KERNEL_FRAGMENT_LIST }$f"
		done
		if [ -f "$dev_dir/kernel.config" ]; then
			KERNEL_FRAGMENTS+=("$dev_dir/kernel.config")
		fi
	else
		die "kernel $KERNEL_FLAVOR has neither config.$ARCH nor base.config"
	fi

	KERNEL_LOCALVERSION="$(sed -n 's/^CONFIG_LOCALVERSION="\(.*\)"$/\1/p' "$cfg_for_ver" | head -n1)"
	KERNEL_RELEASE="${KERNEL_VERSION}${KERNEL_LOCALVERSION}"
}

resolve_hayato_version() {
	local vfile
	if [ -n "${HAYATO_VERSION:-}" ]; then
		printf '%s\n' "$HAYATO_VERSION"
		return 0
	fi
	for vfile in \
		"${HAYATO_ROOT_DIR:-}/VERSION" \
		"${HAYATO_CORE_DIR:-}/VERSION" \
		"$DEVICES_REPO/../VERSION" \
		"$DEVICES_REPO/../core/VERSION" \
		"$DEVICES_REPO/../hayato-core/VERSION"; do
		if [ -n "$vfile" ] && [ -f "$vfile" ]; then
			tr -d ' \t\r\n' <"$vfile"
			printf '\n'
			return 0
		fi
	done
	printf '0.6.0\n'
}

resolve_deb_arch() {
	case "${ARCH:-$(uname -m)}" in
		aarch64|arm64) printf 'arm64\n' ;;
		x86_64|amd64)  printf 'amd64\n' ;;
		*)             dpkg --print-architecture 2>/dev/null || printf '%s\n' "${ARCH:-arm64}" ;;
	esac
}

package_kernel_deb() {
	umask 022
	local stage_dir="${1:-$KERNEL_STAGE}"
	local out_dir="${2:-$stage_dir}"
	[ "${KERNEL_SOURCE_TYPE:-source}" = "source" ] || return 0
	[ -f "$stage_dir/boot/vmlinuz-$KERNEL_RELEASE" ] ||
		die "package_kernel_deb: missing $stage_dir/boot/vmlinuz-$KERNEL_RELEASE"
	[ -d "$stage_dir/lib/modules/$KERNEL_RELEASE" ] ||
		die "package_kernel_deb: missing $stage_dir/lib/modules/$KERNEL_RELEASE"

	local hayato_ver deb_arch pkg_name pkg_ver pkg_dir size deb_file
	hayato_ver="$(resolve_hayato_version)"
	deb_arch="$(resolve_deb_arch)"
	pkg_name="linux-image-hayato-${KERNEL_FLAVOR}"
	pkg_ver="${KERNEL_VERSION}+hayato${hayato_ver}-1hayato1"
	pkg_dir="$WORK_DIR/kernel-pkg-${KERNEL_FLAVOR}"

	rm -rf "$pkg_dir"
	install -d -m 0755 "$pkg_dir/boot/dtbs" "$pkg_dir/lib/modules" \
		"$pkg_dir/usr/lib/linux-image-$KERNEL_RELEASE"
	install -m 0644 "$stage_dir/boot/vmlinuz-$KERNEL_RELEASE" \
		"$pkg_dir/boot/vmlinuz-$KERNEL_RELEASE"
	if [ -f "$stage_dir/boot/config" ]; then
		install -m 0644 "$stage_dir/boot/config" "$pkg_dir/boot/config-$KERNEL_RELEASE"
	elif [ -f "$stage_dir/boot/config-$KERNEL_RELEASE" ]; then
		install -m 0644 "$stage_dir/boot/config-$KERNEL_RELEASE" "$pkg_dir/boot/config-$KERNEL_RELEASE"
	fi
	if [ -f "$stage_dir/boot/System.map" ]; then
		install -m 0644 "$stage_dir/boot/System.map" "$pkg_dir/boot/System.map-$KERNEL_RELEASE"
	elif [ -f "$stage_dir/boot/System.map-$KERNEL_RELEASE" ]; then
		install -m 0644 "$stage_dir/boot/System.map-$KERNEL_RELEASE" "$pkg_dir/boot/System.map-$KERNEL_RELEASE"
	fi
	if [ -d "$stage_dir/boot/dtbs" ]; then
		cp -a "$stage_dir/boot/dtbs/." "$pkg_dir/boot/dtbs/"
		cp -a "$stage_dir/boot/dtbs/." "$pkg_dir/usr/lib/linux-image-$KERNEL_RELEASE/"
	fi
	cp -a "$stage_dir/lib/modules/$KERNEL_RELEASE" "$pkg_dir/lib/modules/"
	rm -f "$pkg_dir/lib/modules/$KERNEL_RELEASE/build" \
		"$pkg_dir/lib/modules/$KERNEL_RELEASE/source"

	size="$(du -sk --exclude=DEBIAN "$pkg_dir" | cut -f1)"
	mkdir -p "$pkg_dir/DEBIAN" "$out_dir"
	cat >"$pkg_dir/DEBIAN/control" <<EOF
Package: $pkg_name
Version: $pkg_ver
Architecture: $deb_arch
Maintainer: Hayato <maintainers@hayato.org>
Installed-Size: $size
Provides: linux-image-$KERNEL_RELEASE
Section: kernel
Priority: optional
Homepage: https://github.com/Brunux/Hayato
Description: Hayato Linux kernel image and modules for $KERNEL_FLAVOR ($KERNEL_RELEASE)
 Prebuilt Linux kernel image, modules, and device trees for the $KERNEL_FLAVOR
 kernel family in Hayato.
EOF

	cat >"$pkg_dir/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
ver="$KERNEL_RELEASE"
if [ -d "/usr/lib/linux-image-\$ver" ]; then
	mkdir -p /boot/dtbs
	cp -a "/usr/lib/linux-image-\$ver/." /boot/dtbs/
fi
if [ -f /etc/debian-aarch64-revision ]; then
	sed -i "s|^kernel .*|kernel \$ver|" /etc/debian-aarch64-revision
fi
if command -v depmod >/dev/null 2>&1; then
	depmod -a "\$ver" || true
fi
if command -v update-initramfs >/dev/null 2>&1; then
	if [ -f "/boot/initrd.img-\$ver" ]; then
		update-initramfs -u -k "\$ver"
	else
		update-initramfs -c -k "\$ver"
	fi
fi
if [ -x /etc/kernel/postinst.d/zz-hayato-boot ]; then
	/etc/kernel/postinst.d/zz-hayato-boot "\$ver" "/boot/vmlinuz-\$ver"
fi
exit 0
EOF
	chmod 0755 "$pkg_dir/DEBIAN/postinst"

	rm -f "$out_dir/${pkg_name}"_*.deb
	deb_file="$out_dir/${pkg_name}_${pkg_ver}_${deb_arch}.deb"
	dpkg-deb --build --root-owner-group "$pkg_dir" "$deb_file" >/dev/null
	log "Packaged kernel -> $deb_file"
}

package_device_deb() {
	umask 022
	local out_dir="${1:-${HAYATO_STAGE:-$WORK_DIR/hayato-stage}}"
	[ -n "${DEVICE_DIR:-}" ] && [ -d "$DEVICE_DIR" ] ||
		die "package_device_deb: DEVICE_DIR is not loaded"

	local hayato_ver deb_arch pkg_name pkg_ver pkg_dir size deb_file
	hayato_ver="$(resolve_hayato_version)"
	deb_arch="$(resolve_deb_arch)"
	pkg_name="hayato-device-${DEVICE}"
	pkg_ver="${hayato_ver}-1hayato1"
	pkg_dir="$WORK_DIR/device-pkg-${DEVICE}"

	rm -rf "$pkg_dir"
	install -d -m 0755 "$pkg_dir/etc/hayato" "$pkg_dir/usr/libexec/hayato/check" \
		"$pkg_dir/usr/share/hayato/devices/$DEVICE"

	printf '%s\n' "$DEVICE" >"$pkg_dir/etc/hayato/device"
	chmod 0644 "$pkg_dir/etc/hayato/device"
	install -m 0644 "$DEVICE_DIR/deviceinfo" "$pkg_dir/etc/hayato/deviceinfo"
	if [ -f "$DEVICE_DIR/kernel-cmdline.conf" ]; then
		install -m 0644 "$DEVICE_DIR/kernel-cmdline.conf" "$pkg_dir/etc/hayato/kernel-cmdline.conf"
	fi
	if [ -f "$DEVICE_DIR/check-device.sh" ]; then
		install -m 0755 "$DEVICE_DIR/check-device.sh" "$pkg_dir/usr/libexec/hayato/check/20-device.sh"
	fi
	if [ -f "$DEVICE_DIR/modules-initfs" ]; then
		install -m 0644 "$DEVICE_DIR/modules-initfs" \
			"$pkg_dir/usr/share/hayato/devices/$DEVICE/modules-initfs"
	fi
	if [ -d "$DEVICE_DIR/files" ]; then
		for entry in "$DEVICE_DIR/files"/*; do
			[ -e "$entry" ] || continue
			[ "$(basename "$entry")" = ".keep" ] && continue
			cp -a "$entry" "$pkg_dir/"
		done
	fi

	size="$(du -sk --exclude=DEBIAN "$pkg_dir" | cut -f1)"
	mkdir -p "$pkg_dir/DEBIAN" "$out_dir"
	cat >"$pkg_dir/DEBIAN/control" <<EOF
Package: $pkg_name
Version: $pkg_ver
Architecture: $deb_arch
Maintainer: Hayato <maintainers@hayato.org>
Installed-Size: $size
Provides: hayato-device
Conflicts: hayato-device
Replaces: hayato-device
Section: admin
Priority: optional
Homepage: https://github.com/Brunux/Hayato
Description: Hayato hardware board definition and overlays for $DEVICE
 Device metadata (/etc/hayato/deviceinfo), kernel command-line defaults,
 board-specific udev/keyd/ALSA overlays, and hardware health checks for
 $DEVICE.
EOF

	cat >"$pkg_dir/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
if [ -f "/usr/share/hayato/devices/$DEVICE/modules-initfs" ]; then
	mkdir -p /etc/initramfs-tools
	touch /etc/initramfs-tools/modules
	grep -v '^[[:space:]]*#' "/usr/share/hayato/devices/$DEVICE/modules-initfs" 2>/dev/null | while read -r _m; do
		[ -n "\$_m" ] || continue
		grep -qxF "\$_m" /etc/initramfs-tools/modules 2>/dev/null || printf '%s\n' "\$_m" >>/etc/initramfs-tools/modules
	done
fi
_root_id="\$(stat -Lc %d:%i / 2>/dev/null || true)"
_pid1_id="\$(stat -Lc %d:%i /proc/1/root 2>/dev/null || true)"
if [ -n "\$_root_id" ] && [ -n "\$_pid1_id" ] && [ "\$_root_id" = "\$_pid1_id" ]; then
	command -v udevadm >/dev/null 2>&1 && udevadm control --reload-rules 2>/dev/null || true
	command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload 2>/dev/null || true
	if [ -x /usr/local/sbin/hayato-irq-balance ]; then
		/usr/local/sbin/hayato-irq-balance >/dev/null 2>&1 || true
	fi
fi
exit 0
EOF
	chmod 0755 "$pkg_dir/DEBIAN/postinst"

	rm -f "$out_dir/${pkg_name}"_*.deb
	deb_file="$out_dir/${pkg_name}_${pkg_ver}_${deb_arch}.deb"
	dpkg-deb --build --root-owner-group "$pkg_dir" "$deb_file" >/dev/null
	log "Packaged device overlay -> $deb_file"
}

if [ "${LIB_DEVICES_NO_AUTOLOAD:-0}" != 1 ]; then
	load_device_context "$DEVICE"
fi
