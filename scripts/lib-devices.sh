#!/bin/bash
# Shared helpers for lazyos-devices kernel builds and board validation.
# Works standalone inside lazyos-devices or when sourced/invoked from lazyos-core.

[ -n "${_LIB_DEVICES_LOADED:-}" ] && return 0
_LIB_DEVICES_LOADED=1

DEVICES_REPO="${DEVICES_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEVICES_DIR="${DEVICES_DIR:-$DEVICES_REPO/devices}"
KERNELS_DIR="${KERNELS_DIR:-$DEVICES_REPO/kernels}"

DEVICE="${DEVICE:-google-asurada}"
BUILD_ROOT="${BUILD_ROOT:-/var/tmp/lazyos-build}"
WORK_DIR="${WORK_DIR:-$BUILD_ROOT/work}"
SRC_DIR="${SRC_DIR:-$BUILD_ROOT/src}"
KERNEL_STAGE="${KERNEL_STAGE:-$BUILD_ROOT/kernel-stage/$DEVICE}"

if ! declare -F log >/dev/null 2>&1; then
	log()  { printf '\033[1;34m[lazyos]\033[0m %s\n' "$*"; }
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

if [ "${LIB_DEVICES_NO_AUTOLOAD:-0}" != 1 ]; then
	load_device_context "$DEVICE"
fi
