#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

[[ -x "$TOOLROOT/usr/bin/qemu-system-x86_64" ]] || "$ROOT_DIR/scripts/fetch-tools.sh"
[[ -f "$ROOT_DIR/alpine-initramfs.img" ]] || "$ROOT_DIR/scripts/build-initramfs.sh"
[[ -f "$ROOT_DIR/rust-efi-launcher/target/x86_64-unknown-uefi/release/rust-efi-launcher.efi" ]] || "$ROOT_DIR/scripts/build-rust-efi.sh"

export_qemu_env

rm -rf "$ESP_DIR"
mkdir -p "$ESP_DIR/EFI/BOOT"
cp "$ROOT_DIR/rust-efi-launcher/target/x86_64-unknown-uefi/release/rust-efi-launcher.efi" "$ESP_DIR/EFI/BOOT/BOOTX64.EFI"
cp "$ALPINE_DIR/vmlinuz-virt" "$ESP_DIR/"
cp "$ROOT_DIR/alpine-initramfs.img" "$ESP_DIR/"

"$ROOT_DIR/scripts/init-ovmf-vars.sh"

exec "$TOOLROOT/usr/bin/qemu-system-x86_64" \
  -L "$TOOLROOT/usr/share/qemu" \
  -M q35 -m 512M -no-reboot -nographic -monitor none -serial stdio \
  -drive if=pflash,format=raw,readonly=on,file="$TOOLROOT/usr/share/edk2/x64/OVMF_CODE.4m.fd" \
  -drive if=pflash,format=raw,file="$ROOT_DIR/OVMF_VARS.4m.fd" \
  -drive format=raw,file=fat:rw:"$ESP_DIR"
