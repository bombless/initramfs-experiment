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

## 安装到本机 `/boot`

如果你想把 Rust EFI 启动器安装到本机的 EFI 系统分区，并用 `efibootmgr` 增加启动项，可以运行：

```sh
./scripts/install-efi-boot-entry.sh
```

默认情况下，这个脚本只做安装，不会自动触发构建。
如果缺少产物，它会直接报错并提示你先构建，或者显式加上 `--build`。

这个脚本会做几件事：

- 把 EFI 启动器复制到 `/boot/EFI/alpine-limine/rust-efi-launcher.efi`。
- 把 `vmlinuz-virt` 和 `alpine-initramfs.img` 复制到 `/boot/`。
- 调用 `efibootmgr` 添加一个名为 `Alpine Limine Rust EFI` 的 UEFI 启动项。

如果你希望它在安装前自动构建缺失产物，可以显式加上 `--build`：

```sh
./scripts/install-efi-boot-entry.sh --build
```

如果自动探测 `efibootmgr` 需要的磁盘或分区号失败，也可以手动指定：

```sh
./scripts/install-efi-boot-entry.sh --disk /dev/nvme0n1 --part 5
```

其他可选参数：

```sh
./scripts/install-efi-boot-entry.sh --boot-dir /boot --label "Alpine Limine Rust EFI"
```

要求：

- 当前系统必须以 UEFI 模式启动。
- `/boot` 必须已经挂载到 EFI System Partition。
- 主机上需要安装 `efibootmgr`。


## 删除 UEFI 启动项

如果你想把之前加入的 `efibootmgr` 启动项删掉，可以运行：

```sh
./scripts/remove-efi-boot-entry.sh
```

如果还想连同复制到 `/boot` 的文件一起删除，可以运行：

```sh
./scripts/remove-efi-boot-entry.sh --delete-files
```

这个脚本会按启动项标签和 EFI loader 路径匹配，然后调用 `efibootmgr --delete-bootnum` 删除对应条目。


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
