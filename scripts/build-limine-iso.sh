#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

[[ -x "$TOOLROOT/usr/bin/limine" ]] || "$ROOT_DIR/scripts/fetch-tools.sh"
[[ -f "$ROOT_DIR/alpine-initramfs.img" ]] || "$ROOT_DIR/scripts/build-initramfs.sh"

export_qemu_env

rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/EFI/BOOT"

cp "$TOOLROOT/usr/share/limine/limine-bios.sys" "$ISO_ROOT/"
cp "$TOOLROOT/usr/share/limine/limine-bios-cd.bin" "$ISO_ROOT/"
cp "$TOOLROOT/usr/share/limine/limine-uefi-cd.bin" "$ISO_ROOT/"
cp "$TOOLROOT/usr/share/limine/BOOTX64.EFI" "$ISO_ROOT/EFI/BOOT/"
cp "$ALPINE_DIR/vmlinuz-virt" "$ISO_ROOT/"
cp "$ROOT_DIR/alpine-initramfs.img" "$ISO_ROOT/"
cp "$ROOT_DIR/limine.conf" "$ISO_ROOT/"

"$TOOLROOT/usr/bin/xorriso" -as mkisofs -R -r -J \
  -b limine-bios-cd.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus \
  -apm-block-size 2048 \
  --efi-boot limine-uefi-cd.bin \
  -efi-boot-part --efi-boot-image --protective-msdos-label \
  "$ISO_ROOT" -o "$ROOT_DIR/limine-alpine.iso"

"$TOOLROOT/usr/bin/limine" bios-install "$ROOT_DIR/limine-alpine.iso"

echo "built: $ROOT_DIR/limine-alpine.iso"
