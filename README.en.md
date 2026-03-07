# Alpine + Limine + Rust EFI

This directory is intended to be used as a standalone Git repository. It provides two reproducible boot flows:

- `Limine BIOS/ISO`: boots a custom Alpine initramfs through Limine and runs it directly in QEMU.
- `Rust UEFI`: a Rust EFI program that passes `initrd=` and the kernel command line to the Linux EFI stub, then boots the same Alpine initramfs.

## Repository Contents

The main source files tracked in Git are:

- `overlay/`: overlay files for the custom initramfs.
- `scripts/`: scripts for downloading tools, building images, and running QEMU.
- `rust-efi-launcher/`: source code for the Rust UEFI launcher.
- `limine.conf`: Limine boot configuration.

Generated artifacts are excluded through `.gitignore`, including:

- Downloaded Arch packages and the extracted local toolchain.
- Alpine downloads and build directories.
- Runtime and build artifacts such as `ISO`, `initramfs`, `ESP`, and `OVMF_VARS.4m.fd`.
- Rust `target/` output.

## Quick Start

Fetch the local toolchain first:

```sh
cd /home/openclaw/alpine-limine
./scripts/fetch-tools.sh
```

Build the Alpine initramfs:

```sh
./scripts/build-initramfs.sh
```

Build and boot the Limine ISO:

```sh
./scripts/build-limine-iso.sh
./scripts/run-qemu-bios.sh
```

Build and boot the Rust EFI launcher:

```sh
./scripts/build-rust-efi.sh
./scripts/run-qemu-uefi.sh
```

## OVMF Variable Store

UEFI boot uses a separate script to initialize the writable OVMF variable store:

```sh
./scripts/init-ovmf-vars.sh
```

This script copies the OVMF template from `toolroot` and creates a local writable `OVMF_VARS.4m.fd`.
That file is runtime state and is not tracked by Git.

## Proxy

If the network is unstable, set these variables before running the scripts:

```sh
export PROXY_URL=http://127.0.0.1:10808
export ALL_PROXY_URL=socks5://127.0.0.1:10808
```

If you do not set them explicitly, the scripts will still try `127.0.0.1:10808` by default.
