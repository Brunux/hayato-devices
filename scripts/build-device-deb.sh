#!/bin/bash
# Build the hardware board definition and overlay package (hayato-device-<device>.deb).
#
# Usage: build-device-deb.sh [OUTDIR]
set -euo pipefail
. "$(dirname "$0")/lib-devices.sh"

OUTDIR="${1:-${HAYATO_STAGE:-$WORK_DIR/hayato-stage}}"
package_device_deb "$OUTDIR"
