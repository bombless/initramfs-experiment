#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_tool pacman
require_tool curl
require_tool bsdtar

packages=(
    limine
    qemu-system-x86
    qemu-common
    qemu-system-x86-firmware
    seabios
    capstone
    libcbor
    ndctl
    dtc
    rdma-core
    libslirp
    vde2
    libxdp
    libaio
    libisoburn
    libburn
    libisofs
    edk2-ovmf
)

for pkg in "${packages[@]}"; do
    fetch_and_extract_pkg "$pkg"
done

echo "tools extracted into: $TOOLROOT"
