#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_tool curl
require_tool bsdtar
require_tool cpio
require_tool gzip

mkdir -p "$ALPINE_DIR"
use_proxy

mini_index=$(curl -L --fail https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/)
mini_file=$(printf '%s\n' "$mini_index" \
    | grep -o 'alpine-minirootfs-[0-9.]*-x86_64.tar.gz' \
    | sort -V | tail -n1)

if [[ -z "$mini_file" ]]; then
    echo "failed to locate latest Alpine minirootfs" >&2
    exit 1
fi

for f in "$mini_file" vmlinuz-virt; do
    if [[ ! -f "$ALPINE_DIR/$f" ]]; then
        if [[ "$f" == vmlinuz-virt ]]; then
            curl -L --fail --retry 3 -o "$ALPINE_DIR/$f" \
                https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/netboot/vmlinuz-virt
        else
            curl -L --fail --retry 3 -o "$ALPINE_DIR/$f" \
                "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/$f"
        fi
    fi
done

rm -rf "$MINIROOTFS_DIR"
mkdir -p "$MINIROOTFS_DIR"
bsdtar -xpf "$ALPINE_DIR/$mini_file" -C "$MINIROOTFS_DIR"
install -m 0755 "$ROOT_DIR/overlay/init" "$MINIROOTFS_DIR/init"

(
    cd "$MINIROOTFS_DIR"
    find . -print0 | cpio --null -o --format=newc --owner=0:0 2>/dev/null | gzip -9 > "$ROOT_DIR/alpine-initramfs.img"
)

echo "built: $ROOT_DIR/alpine-initramfs.img"
