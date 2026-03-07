#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PKG_DIR="$ROOT_DIR/pkgs"
TOOLROOT="$ROOT_DIR/toolroot"
ALPINE_DIR="$ROOT_DIR/alpine"
MINIROOTFS_DIR="$ROOT_DIR/minirootfs"
ISO_ROOT="$ROOT_DIR/iso-root"
ESP_DIR="$ROOT_DIR/esp"

use_proxy() {
    if [[ -n "${PROXY_URL:-}" ]]; then
        export http_proxy="$PROXY_URL"
        export https_proxy="$PROXY_URL"
        export HTTP_PROXY="$http_proxy"
        export HTTPS_PROXY="$https_proxy"
    else
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
    fi

    if [[ -n "${ALL_PROXY_URL:-}" ]]; then
        export all_proxy="$ALL_PROXY_URL"
        export ALL_PROXY="$all_proxy"
    else
        unset all_proxy ALL_PROXY
    fi
}

fetch_and_extract_pkg() {
    local pkg="$1"
    mkdir -p "$PKG_DIR" "$TOOLROOT"
    local url
    url=$(pacman -Sp --noconfirm "$pkg" | tail -n1)
    local file="$PKG_DIR/$(basename "$url")"

    if [[ ! -f "$file" ]]; then
        use_proxy
        curl -L --fail --retry 3 -o "$file" "$url"
    fi

    bsdtar -xpf "$file" -C "$TOOLROOT"
}

export_qemu_env() {
    export LD_LIBRARY_PATH="$TOOLROOT/usr/lib:${LD_LIBRARY_PATH:-}"
}

resolve_mount_block_device() {
    local mountpoint="$1"
    local source
    local resolved

    while IFS= read -r source; do
        [[ -n "$source" ]] || continue
        [[ "$source" == /dev/* ]] || continue

        resolved=$(realpath "$source")
        if [[ -b "$resolved" ]]; then
            printf '%s
' "$resolved"
            return 0
        fi
    done < <(findmnt -rn -o SOURCE -T "$mountpoint")

    return 1
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "missing required host tool: $1" >&2
        exit 1
    }
}
