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

## Install to Local `/boot`

If you want to install the Rust EFI launcher into the local EFI System Partition and register it with `efibootmgr`, run:

```sh
./scripts/install-efi-boot-entry.sh
```

By default, this script only installs files and registers the boot entry.
It does not trigger builds automatically. If artifacts are missing, it fails and tells you to build them first, or to pass `--build` explicitly.

This script will:

- Copy the EFI launcher to `/boot/EFI/alpine-limine/rust-efi-launcher.efi`.
- Copy `vmlinuz-virt` and `alpine-initramfs.img` into `/boot/`.
- Use `efibootmgr` to create a UEFI boot entry named `Alpine Limine Rust EFI`.

If you want it to build missing artifacts before installation, pass `--build` explicitly:

```sh
./scripts/install-efi-boot-entry.sh --build
```

Example with other explicit options:

```sh
./scripts/install-efi-boot-entry.sh --boot-dir /boot --label "Alpine Limine Rust EFI"
```

Requirements:

- The current system must be booted in UEFI mode.
- `/boot` must already be mounted as the EFI System Partition.
- `efibootmgr` must be installed on the host.


## Remove the UEFI Boot Entry

If you want to remove the boot entry previously created with `efibootmgr`, run:

```sh
./scripts/remove-efi-boot-entry.sh
```

If you also want to remove the files that were copied into `/boot`, run:

```sh
./scripts/remove-efi-boot-entry.sh --delete-files
```

This script matches entries by boot label and EFI loader path, then removes them with `efibootmgr --delete-bootnum`.


## OVMF Variable Store

UEFI boot uses a separate script to initialize the writable OVMF variable store:

```sh
./scripts/init-ovmf-vars.sh
```

This script copies the OVMF template from `toolroot` and creates a local writable `OVMF_VARS.4m.fd`.
That file is runtime state and is not tracked by Git.

## Proxy

If the network is unstable, you can set these variables before running the scripts:

```sh
export PROXY_URL=http://127.0.0.1:10808
export ALL_PROXY_URL=socks5://127.0.0.1:10808
```

If you do not set them, the scripts will use a direct connection and will not enable any proxy by default.
