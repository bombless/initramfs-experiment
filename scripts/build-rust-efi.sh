#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_tool cargo
require_tool rustup

export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
use_proxy

rustup target add x86_64-unknown-uefi

cd "$ROOT_DIR/rust-efi-launcher"
cargo build --release --target x86_64-unknown-uefi

echo "built: $ROOT_DIR/rust-efi-launcher/target/x86_64-unknown-uefi/release/rust-efi-launcher.efi"
