# Alpine + Limine + Rust EFI

このディレクトリは、単独の Git リポジトリとしてそのまま使えるように構成されています。再現可能な起動フローは次の 2 本です。

- `Limine BIOS/ISO`: Limine でカスタム Alpine initramfs を起動し、そのまま QEMU で実行します。
- `Rust UEFI`: Rust 製の EFI プログラムが Linux EFI stub に `initrd=` とカーネルコマンドラインを渡し、同じ Alpine initramfs を起動します。

## リポジトリ内容

Git に含める主なソースとスクリプトは以下です。

- `overlay/`: カスタム initramfs 用のオーバーレイ。
- `scripts/`: ツールの取得、イメージのビルド、QEMU の起動を行うスクリプト群。
- `rust-efi-launcher/`: Rust UEFI ランチャーのソースコード。
- `limine.conf`: Limine の起動設定。

以下の生成物は `.gitignore` で除外されています。

- ダウンロードした Arch パッケージと展開済みのローカルツールチェーン。
- Alpine のダウンロード物とビルド用ディレクトリ。
- `ISO`、`initramfs`、`ESP`、`OVMF_VARS.4m.fd` などの実行時・生成物。
- Rust の `target/` 出力。

## クイックスタート

まずローカルツールチェーンを取得します。

```sh
cd /home/openclaw/alpine-limine
./scripts/fetch-tools.sh
```

Alpine initramfs をビルドします。

```sh
./scripts/build-initramfs.sh
```

Limine ISO をビルドして起動します。

```sh
./scripts/build-limine-iso.sh
./scripts/run-qemu-bios.sh
```

Rust EFI ランチャーをビルドして起動します。

```sh
./scripts/build-rust-efi.sh
./scripts/run-qemu-uefi.sh
```

## OVMF 変数ストア

UEFI 起動では、書き込み可能な OVMF 変数ストアを別スクリプトで初期化します。

```sh
./scripts/init-ovmf-vars.sh
```

このスクリプトは `toolroot` にある OVMF テンプレートをコピーし、ローカルの書き込み可能な `OVMF_VARS.4m.fd` を作成します。
このファイルは実行時状態のため、Git には含めません。

## プロキシ

ネットワークが不安定な場合は、スクリプト実行前に次を設定できます。

```sh
export PROXY_URL=http://127.0.0.1:10808
export ALL_PROXY_URL=socks5://127.0.0.1:10808
```

設定しない場合、スクリプトは直結で動作し、既定でプロキシを有効にはしません。
