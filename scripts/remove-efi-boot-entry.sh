#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

ENTRY_LABEL="Alpine Limine Rust EFI"
ENTRY_DIR="EFI/alpine-limine"
EFI_FILENAME="rust-efi-launcher.efi"
DELETE_FILES=0
BOOT_DIR=/boot

usage() {
    cat <<USAGE
Usage: $0 [options]

Options:
  --label <label>       UEFI boot entry label. Default: Alpine Limine Rust EFI
  --entry-dir <dir>     EFI subdirectory inside the ESP. Default: EFI/alpine-limine
  --efi-name <name>     EFI filename to remove/match. Default: rust-efi-launcher.efi
  --boot-dir <dir>      Boot mountpoint used when deleting files. Default: /boot
  --delete-files        Also remove the installed EFI loader, kernel, and initramfs from /boot
  -h, --help            Show this help message
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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
        --boot-dir)
            BOOT_DIR="$2"
            shift 2
            ;;
        --delete-files)
            DELETE_FILES=1
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

require_tool efibootmgr

loader_path="\\${ENTRY_DIR//\//\\}\\$EFI_FILENAME"

if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" \
        --label "$ENTRY_LABEL" \
        --entry-dir "$ENTRY_DIR" \
        --efi-name "$EFI_FILENAME" \
        --boot-dir "$BOOT_DIR" \
        $([[ $DELETE_FILES -eq 1 ]] && printf '%s' '--delete-files')
fi

if [[ ! -d /sys/firmware/efi/efivars ]]; then
    echo "efivars is not available; booted system does not appear to be running in UEFI mode" >&2
    exit 1
fi

mapfile -t bootnums < <(
    efibootmgr -v | awk -v label="$ENTRY_LABEL" -v path="$loader_path" '
        $0 ~ /^Boot[0-9A-Fa-f]{4}[* ]/ {
            if (index($0, label) && index($0, path)) {
                bootnum = substr($1, 5, 4)
                sub(/[* ]$/, "", bootnum)
                print bootnum
            }
        }
    '
)

if [[ ${#bootnums[@]} -eq 0 ]]; then
    echo "no matching efibootmgr entries found for label '$ENTRY_LABEL' and loader '$loader_path'"
else
    printf 'removing boot entries:'
    for bootnum in "${bootnums[@]}"; do
        printf ' %s' "$bootnum"
    done
    printf '\n'

    for bootnum in "${bootnums[@]}"; do
        efibootmgr --bootnum "$bootnum" --delete-bootnum
    done
fi

if [[ $DELETE_FILES -eq 1 ]]; then
    install_dir="$BOOT_DIR/$ENTRY_DIR"
    rm -f "$install_dir/$EFI_FILENAME" "$BOOT_DIR/vmlinuz-virt" "$BOOT_DIR/alpine-initramfs.img"
    rmdir --ignore-fail-on-non-empty "$install_dir" 2>/dev/null || true
    echo "removed installed files from $BOOT_DIR"
fi
