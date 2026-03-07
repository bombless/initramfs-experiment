#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

BOOT_DIR=/boot
ENTRY_LABEL="Alpine Limine Rust EFI"
ENTRY_DIR="EFI/alpine-limine"
EFI_FILENAME="rust-efi-launcher.efi"
DO_BUILD=0
AUTO_YES=0
DISK_OVERRIDE=
PART_OVERRIDE=

usage() {
    cat <<USAGE
Usage: $0 [options]

Options:
  --boot-dir <dir>    Boot mountpoint to install into. Default: /boot
  --label <label>     UEFI boot entry label. Default: Alpine Limine Rust EFI
  --entry-dir <dir>   EFI subdirectory inside the ESP. Default: EFI/alpine-limine
  --efi-name <name>   EFI filename to install. Default: rust-efi-launcher.efi
  --disk <device>     Override parent disk for efibootmgr, e.g. /dev/nvme0n1
  --part <number>     Override partition number for efibootmgr, e.g. 5
  --build             Build missing launcher/initramfs before installation
  --yes               Skip interactive confirmation
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
        --disk)
            DISK_OVERRIDE="$2"
            shift 2
            ;;
        --part)
            PART_OVERRIDE="$2"
            shift 2
            ;;
        --build)
            DO_BUILD=1
            shift
            ;;
        --yes)
            AUTO_YES=1
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

check_artifacts() {
    local missing=0
    for file in "$INITRAMFS" "$KERNEL" "$LAUNCHER"; do
        if [[ ! -f "$file" ]]; then
            echo "missing required artifact: $file" >&2
            missing=1
        fi
    done

    if [[ $missing -ne 0 ]]; then
        echo "run with --build to generate missing artifacts first" >&2
        exit 1
    fi
}

prompt_value() {
    local prompt="$1"
    local default_value="$2"
    local reply
    if [[ -n "$default_value" ]]; then
        read -r -p "$prompt [$default_value]: " reply
        printf '%s\n' "${reply:-$default_value}"
    else
        read -r -p "$prompt: " reply
        printf '%s\n' "$reply"
    fi
}

if [[ $DO_BUILD -eq 1 ]]; then
    ensure_artifacts
else
    check_artifacts
fi

if [[ $EUID -ne 0 ]]; then
    extra_args=()
    [[ $DO_BUILD -eq 1 ]] && extra_args+=(--build)
    [[ $AUTO_YES -eq 1 ]] && extra_args+=(--yes)
    [[ -n "$DISK_OVERRIDE" ]] && extra_args+=(--disk "$DISK_OVERRIDE")
    [[ -n "$PART_OVERRIDE" ]] && extra_args+=(--part "$PART_OVERRIDE")
    exec sudo --preserve-env=PROXY_URL,ALL_PROXY_URL "$0" \
        --boot-dir "$BOOT_DIR" \
        --label "$ENTRY_LABEL" \
        --entry-dir "$ENTRY_DIR" \
        --efi-name "$EFI_FILENAME" \
        "${extra_args[@]}"
fi

if [[ ! -d /sys/firmware/efi/efivars ]]; then
    echo "efivars is not available; booted system does not appear to be running in UEFI mode" >&2
    exit 1
fi

if ! mountpoint -q "$BOOT_DIR"; then
    echo "$BOOT_DIR is not a mounted filesystem" >&2
    exit 1
fi

boot_part=$(resolve_mount_block_device "$BOOT_DIR" || true)
if [[ -z "$boot_part" && $AUTO_YES -ne 1 ]]; then
    echo "automatic ESP partition detection failed for $BOOT_DIR" >&2
    echo "findmnt returned:" >&2
    findmnt -T "$BOOT_DIR" -o TARGET,SOURCE,FSTYPE,OPTIONS >&2 || true
    boot_part=$(prompt_value 'Enter the ESP partition device (e.g. /dev/nvme0n1p5)' '')
fi

if [[ -z "$boot_part" || ! -b "$boot_part" ]]; then
    echo "could not resolve a block device for $BOOT_DIR" >&2
    echo "findmnt returned:" >&2
    findmnt -T "$BOOT_DIR" -o TARGET,SOURCE,FSTYPE,OPTIONS >&2 || true
    echo "You can rerun with --disk /dev/... --part N" >&2
    exit 1
fi

partnum="$PART_OVERRIDE"
disk="$DISK_OVERRIDE"

if [[ -z "$partnum" ]]; then
    partnum=$(resolve_partition_number "$boot_part" || true)
fi

if [[ -z "$disk" ]]; then
    disk=$(resolve_parent_disk "$boot_part" || true)
fi

if [[ (-z "$disk" || -z "$partnum") && $AUTO_YES -ne 1 ]]; then
    echo "automatic efibootmgr disk/partition detection is incomplete" >&2
    echo "resolved ESP partition: $boot_part" >&2
    [[ -z "$disk" ]] && disk=$(prompt_value 'Enter parent disk for efibootmgr (e.g. /dev/nvme0n1)' "$disk")
    [[ -z "$partnum" ]] && partnum=$(prompt_value 'Enter partition number for efibootmgr (e.g. 5)' "$partnum")
fi

if [[ -z "$disk" || -z "$partnum" ]]; then
    echo "failed to determine disk/partition for $boot_part" >&2
    echo "You can rerun with --disk /dev/... --part N" >&2
    exit 1
fi

loader_path="\\${ENTRY_DIR//\//\\}\\$EFI_FILENAME"
install_dir="$BOOT_DIR/$ENTRY_DIR"

printf '%s\n' 'Installation plan:'
printf '  boot mountpoint:     %s\n' "$BOOT_DIR"
printf '  ESP partition:       %s\n' "$boot_part"
printf '  disk:                %s\n' "$disk"
printf '  partition number:    %s\n' "$partnum"
printf '  EFI directory:       %s\n' "$install_dir"
printf '  EFI launcher target: %s\n' "$install_dir/$EFI_FILENAME"
printf '  kernel target:       %s\n' "$BOOT_DIR/vmlinuz-virt"
printf '  initramfs target:    %s\n' "$BOOT_DIR/alpine-initramfs.img"
printf '  UEFI label:          %s\n' "$ENTRY_LABEL"
printf '  UEFI loader path:    %s\n' "$loader_path"

if [[ $AUTO_YES -ne 1 ]]; then
    if [[ ! -t 0 ]]; then
        echo 'refusing to continue without confirmation on a non-interactive terminal; rerun with --yes' >&2
        exit 1
    fi
    read -r -p 'Proceed with copy and efibootmgr entry creation? [y/N] ' reply
    case "$reply" in
        y|Y|yes|YES)
            ;;
        *)
            echo 'aborted by user'
            exit 1
            ;;
    esac
fi

mkdir -p "$install_dir"
install -m 0644 "$KERNEL" "$BOOT_DIR/vmlinuz-virt"
install -m 0644 "$INITRAMFS" "$BOOT_DIR/alpine-initramfs.img"
install -m 0644 "$LAUNCHER" "$install_dir/$EFI_FILENAME"
sync

echo "installed launcher: $install_dir/$EFI_FILENAME"
echo "installed kernel:   $BOOT_DIR/vmlinuz-virt"
echo "installed initramfs:$BOOT_DIR/alpine-initramfs.img"

if efibootmgr -v | grep -F "$ENTRY_LABEL" | grep -F "$loader_path" >/dev/null 2>&1; then
    echo "matching efibootmgr entry already exists; skipping creation"
    exit 0
fi

efibootmgr --create \
    --disk "$disk" \
    --part "$partnum" \
    --label "$ENTRY_LABEL" \
    --loader "$loader_path"
