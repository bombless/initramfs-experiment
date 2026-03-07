#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

[[ -f "$ROOT_DIR/limine-alpine.iso" ]] || "$ROOT_DIR/scripts/build-limine-iso.sh"
export_qemu_env

exec "$TOOLROOT/usr/bin/qemu-system-x86_64" \
  -L "$TOOLROOT/usr/share/qemu" \
  -M pc -m 512M -no-reboot -nographic -monitor none -serial stdio \
  -cdrom "$ROOT_DIR/limine-alpine.iso" -boot d
