#!/bin/bash
# Build the kernel for the selected device's kernel flavor and stage it.
#
# Supports two config layouts under kernels/<flavor>/:
#   1. Monolithic `config.<arch>` (e.g. mediatek-mt81/config.aarch64)
#   2. Composable `base.config` + `fragments/*.config` + optional board `kernel.config`
#      (e.g. arm64-mainline), merged on top of arch defconfig via merge_config.sh
#
# Optional: BUILD_DEB=yes builds Debian packages into $BUILD_ROOT/kernel-deb/$DEVICE.
set -euo pipefail
. "$(dirname "$0")/lib-devices.sh"

STAGE="$KERNEL_STAGE"
JOBS="${JOBS:-$(nproc)}"
SERIES="$KERNEL_PATCH_DIR/series"
BUILD_DEB="${BUILD_DEB:-yes}"

if [ "${KERNEL_SOURCE_TYPE:-source}" = "debian-pkg" ]; then
	log "Device : $DEVICE"
	log "Kernel : $KERNEL_FLAVOR via Debian package '$KERNEL_PACKAGE' ($ARCH) — skipping source build"
	exit 0
fi

patches_hash() {
	{
		cat "$SERIES" 2>/dev/null
		cat "$KERNEL_PATCH_DIR"/*.patch 2>/dev/null
	} | sha256sum | cut -d' ' -f1
}

fetch_and_prepare() {
	mkdir -p "$SRC_DIR"
	if [ ! -f "$SRC_DIR/$KERNEL_TARBALL" ]; then
		log "Downloading $KERNEL_URL"
		curl -fSL -o "$SRC_DIR/$KERNEL_TARBALL" "$KERNEL_URL"
	fi
	_want="$(patches_hash)"
	if [ -f "$KERNEL_SRC/.prepared" ] && [ "$(cat "$KERNEL_SRC/.prepared")" = "$_want" ]; then
		log "Kernel source already prepared (same patches)"
	else
		log "Extracting $KERNEL_TARBALL"
		rm -rf "$KERNEL_SRC"
		tar xf "$SRC_DIR/$KERNEL_TARBALL" -C "$SRC_DIR"

		log "Applying patches"
		if [ -f "$SERIES" ]; then
			while read -r p; do
				case "$p" in '' | '#'*) continue ;; esac
				log "  $p"
				patch -d "$KERNEL_SRC" -p1 --no-backup-if-mismatch <"$KERNEL_PATCH_DIR/$p"
			done <"$SERIES"
		fi
		printf '%s\n' "$_want" >"$KERNEL_SRC/.prepared"
	fi

	if [ "$KERNEL_CONFIG_MODE" = "monolithic" ]; then
		if ! cmp -s "$KERNEL_CONFIG" "$KERNEL_SRC/.config"; then
			log "Syncing kernel config (kernels/$KERNEL_FLAVOR/config.$ARCH)"
		fi
		cp "$KERNEL_CONFIG" "$KERNEL_SRC/.config"
	else
		log "Merging composable config ($KERNEL_FLAVOR: base${KERNEL_FRAGMENT_LIST:+ + $KERNEL_FRAGMENT_LIST})"
		make -C "$KERNEL_SRC" ARCH="$KERNEL_ARCH" LLVM=1 defconfig </dev/null >/dev/null
		"$KERNEL_SRC/scripts/kconfig/merge_config.sh" -m -O "$KERNEL_SRC" \
			"$KERNEL_SRC/.config" "${KERNEL_FRAGMENTS[@]}"
	fi
}

check_config_drift() {
	# Exclude compiler-probe symbols that embed toolchain versions on every run.
	local drift="" line
	local ref_files=("$KERNEL_CONFIG")
	[ "$KERNEL_CONFIG_MODE" = "monolithic" ] || ref_files=("${KERNEL_FRAGMENTS[@]}")

	while IFS= read -r line; do
		case "$line" in
			CONFIG_CC_*|CONFIG_AS_*|CONFIG_LD_*|CONFIG_LLD_*|CONFIG_BINDGEN_*|CONFIG_RUSTC_*|CONFIG_CLANG_*|CONFIG_PAHOLE_*) continue ;;
		esac
		if [ "$KERNEL_CONFIG_MODE" = "monolithic" ]; then
			grep -qxF "$line" "$KERNEL_CONFIG" || drift="$drift ${line%%=*}"
		fi
	done <"$KERNEL_SRC/.config"

	if [ "$KERNEL_CONFIG_MODE" = "fragments" ]; then
		for frag in "${ref_files[@]}"; do
			while IFS= read -r line; do
				case "$line" in
					''|'#'*) continue ;;
				esac
				grep -qxF "$line" "$KERNEL_SRC/.config" || drift="$drift ${line%%=*}"
			done <"$frag"
		done
	fi

	[ -z "$drift" ] || warn "config drift (built .config differs from declared config):$drift"
}

build_kernel() {
	log "Building kernel $KERNEL_RELEASE ($JOBS jobs)"
	# Host tools (resolve_btfids, libsubcmd, libbpf) compile with
	# -I$(srctree)/tools/include/uapi and -I$(srctree)/tools/include, so
	# <linux/types.h> resolves to the kernel tree's tools headers instead of
	# /usr/include/linux/types.h. Current Debian forky's <asm/sigcontext.h> and
	# <asm/ptrace.h> use __u128, which those tools headers omit; prepend the
	# guarded __s128/__u128 typedefs to both tools headers.
	for _th in \
		"$KERNEL_SRC/tools/include/linux/types.h" \
		"$KERNEL_SRC/tools/include/uapi/linux/types.h"; do
		if [ -f "$_th" ] && ! grep -qs "__hayato_u128_defined" "$_th"; then
			log "Patching __u128 typedef into ${_th#"$KERNEL_SRC/"}"
			{
				cat <<'EOF'
#if defined(__SIZEOF_INT128__) && !defined(__hayato_u128_defined)
#define __hayato_u128_defined 1
typedef __signed__ __int128 __s128 __attribute__((aligned(16)));
typedef unsigned __int128 __u128 __attribute__((aligned(16)));
#endif
EOF
				cat "$_th"
			} >"$_th.hayato"
			mv "$_th.hayato" "$_th"
		fi
	done
	make -C "$KERNEL_SRC" ARCH="$KERNEL_ARCH" LLVM=1 olddefconfig </dev/null >/dev/null
	check_config_drift
	make -C "$KERNEL_SRC" ARCH="$KERNEL_ARCH" LLVM=1 -j"$JOBS"
}

install_kernel() {
	log "Installing kernel into $STAGE"
	rm -rf "$STAGE"
	mkdir -p "$STAGE/boot"
	make -C "$KERNEL_SRC" ARCH="$KERNEL_ARCH" LLVM=1 \
		INSTALL_PATH="$STAGE/boot" \
		INSTALL_MOD_PATH="$STAGE" \
		INSTALL_MOD_STRIP=1 \
		INSTALL_DTBS_PATH="$STAGE/boot/dtbs" \
		zinstall modules_install dtbs_install
	cp "$KERNEL_SRC/.config" "$STAGE/boot/config"
	cp "$KERNEL_SRC/System.map" "$STAGE/boot/System.map" 2>/dev/null || true
	log "Kernel release: $(cat "$KERNEL_SRC/include/config/kernel.release")"
	if [ "$BUILD_DEB" = yes ]; then
		package_kernel_deb "$STAGE" "$STAGE"
	fi
	ls -la "$STAGE/boot"
}

log "Device : $DEVICE"
log "Kernel : $KERNEL_FLAVOR $KERNEL_VERSION ($KERNEL_ARCH, $KERNEL_CONFIG_MODE)"

fetch_and_prepare
build_kernel
install_kernel
log "Kernel build done: $STAGE"
