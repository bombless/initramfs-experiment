# Alpine + Limine + Rust EFI

这个目录可以直接作为一个独立 Git 仓库使用，包含两条可复现的启动链路：

- `Limine BIOS/ISO`：用 Limine 引导 Alpine 自制 initramfs，在 QEMU 里直接启动。
- `Rust UEFI`：一个 Rust 写的 EFI 程序，给 Linux EFI stub 传递 `initrd=` 和命令行，再把同一个 Alpine initramfs 启起来。

## 仓库内容

会提交到仓库里的主要是源码和脚本：

- `overlay/`：自定义 initramfs 覆盖层。
- `scripts/`：下载工具、构建镜像、运行 QEMU 的脚本。
- `rust-efi-launcher/`：Rust UEFI 启动器源码。
- `limine.conf`：Limine 启动配置。

不会提交的内容已经在 `.gitignore` 里处理：

- 下载下来的 Arch 包和解包工具链。
- Alpine 下载物和构建中间目录。
- `ISO`、`initramfs`、`ESP`、`OVMF_VARS.4m.fd` 等派生产物。
- Rust `target/`。

## 快速开始

先拉本地工具：

```sh
cd /home/openclaw/alpine-limine
./scripts/fetch-tools.sh
```

构建 Alpine initramfs：

```sh
./scripts/build-initramfs.sh
```

构建并启动 Limine ISO：

```sh
./scripts/build-limine-iso.sh
./scripts/run-qemu-bios.sh
```

构建并启动 Rust EFI 启动器：

```sh
./scripts/build-rust-efi.sh
./scripts/run-qemu-uefi.sh
```

## OVMF 变量盘

UEFI 启动会使用独立脚本初始化变量盘：

```sh
./scripts/init-ovmf-vars.sh
```

这个脚本会从 `toolroot` 里的 OVMF 模板复制出本地可写的 `OVMF_VARS.4m.fd`。
这个文件是运行时状态，不纳入 Git。

## 代理

如果网络不稳，可以在执行脚本前自行设置：

```sh
export PROXY_URL=http://127.0.0.1:10808
export ALL_PROXY_URL=socks5://127.0.0.1:10808
```

如果不设置，脚本将直接走直连，不会默认启用任何代理。
