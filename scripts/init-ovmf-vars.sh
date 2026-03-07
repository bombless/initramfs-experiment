#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

[[ -x "$TOOLROOT/usr/bin/qemu-system-x86_64" ]] || "$ROOT_DIR/scripts/fetch-tools.sh"

src="$TOOLROOT/usr/share/edk2/x64/OVMF_VARS.4m.fd"
dst="$ROOT_DIR/OVMF_VARS.4m.fd"

if [[ ! -f "$src" ]]; then
    echo "missing OVMF vars template: $src" >&2
    exit 1
fi

if [[ ! -f "$dst" ]]; then
    cp "$src" "$dst"
    echo "initialized: $dst"
else
    echo "already exists: $dst"
fi
