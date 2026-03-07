#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

BOOT_DIR=/boot
ENTRY_LABEL="Alpine Limine Rust EFI"
ENTRY_DIR="EFI/alpine-limine"
EFI_FILENAME="rust-efi-launcher.efi"
SKIP_BUILD=0

usage() {
    cat <<USAGE
Usage: $0 [options]

Options:
  --boot-dir <dir>    Boot mountpoint to install into. Default: /boot
  --label <label>     UEFI boot entry label. Default: Alpine Limine Rust EFI
  --entry-dir <dir>   EFI subdirectory inside the ESP. Default: EFI/alpine-limine
  --efi-name <name>   EFI filename to install. Default: rust-efi-launcher.efi
  --skip-build        Skip building the launcher/initramfs before installation
  -h, --help          Show this help message
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --boot-dir)
            BOOT_DIR="$2"
            shift 2
            ;;
        --label)
            ENTRY_LABEL="$2"
            shift 2
            ;;
        --entry-dir)
            ENTRY_DIR="$2"
            shift 2
            ;;
        --efi-name)
            EFI_FILENAME="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

require_tool findmnt
require_tool lsblk
require_tool install
require_tool efibootmgr

LAUNCHER="$ROOT_DIR/rust-efi-launcher/target/x86_64-unknown-uefi/release/rust-efi-launcher.efi"
INITRAMFS="$ROOT_DIR/alpine-initramfs.img"
KERNEL="$ALPINE_DIR/vmlinuz-virt"

ensure_artifacts() {
    [[ -f "$INITRAMFS" && -f "$KERNEL" ]] || "$ROOT_DIR/scripts/build-initramfs.sh"
    [[ -f "$LAUNCHER" ]] || "$ROOT_DIR/scripts/build-rust-efi.sh"
}

if [[ $SKIP_BUILD -eq 0 ]]; then
    ensure_artifacts
fi

if [[ $EUID -ne 0 ]]; then
    exec sudo --preserve-env=PROXY_URL,ALL_PROXY_URL "$0" \
        --boot-dir "$BOOT_DIR" \
        --label "$ENTRY_LABEL" \
        --entry-dir "$ENTRY_DIR" \
        --efi-name "$EFI_FILENAME" \
        --skip-build
fi

if [[ ! -d /sys/firmware/efi/efivars ]]; then
    echo "efivars is not available; booted system does not appear to be running in UEFI mode" >&2
    exit 1
fi

if ! mountpoint -q "$BOOT_DIR"; then
    echo "$BOOT_DIR is not a mounted filesystem" >&2
    exit 1
fi

boot_part=$(realpath "$(findmnt -no SOURCE -T "$BOOT_DIR")")
if [[ ! -b "$boot_part" ]]; then
    echo "could not resolve a block device for $BOOT_DIR: $boot_part" >&2
    exit 1
fi

partnum=$(lsblk -no PARTNUM "$boot_part" | tr -d '[:space:]')
pkname=$(lsblk -no PKNAME "$boot_part" | tr -d '[:space:]')

if [[ -z "$partnum" || -z "$pkname" ]]; then
    echo "failed to determine disk/partition for $boot_part" >&2
    exit 1
fi

disk="/dev/$pkname"
loader_path="\\${ENTRY_DIR//\//\\}\\$EFI_FILENAME"
install_dir="$BOOT_DIR/$ENTRY_DIR"

mkdir -p "$install_dir"
install -m 0644 "$KERNEL" "$BOOT_DIR/vmlinuz-virt"
install -m 0644 "$INITRAMFS" "$BOOT_DIR/alpine-initramfs.img"
install -m 0644 "$LAUNCHER" "$install_dir/$EFI_FILENAME"
sync

echo "installed launcher: $install_dir/$EFI_FILENAME"
echo "installed kernel:   $BOOT_DIR/vmlinuz-virt"
echo "installed initramfs:$BOOT_DIR/alpine-initramfs.img"

echo "detected ESP partition: $boot_part"
echo "detected disk:          $disk"
echo "detected partnum:       $partnum"
echo "UEFI loader path:       $loader_path"

if efibootmgr -v | grep -F "$ENTRY_LABEL" | grep -F "$loader_path" >/dev/null 2>&1; then
    echo "matching efibootmgr entry already exists; skipping creation"
    exit 0
fi

efibootmgr --create \
    --disk "$disk" \
    --part "$partnum" \
    --label "$ENTRY_LABEL" \
    --loader "$loader_path"
