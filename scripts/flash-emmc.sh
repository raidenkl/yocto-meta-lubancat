#!/usr/bin/env bash
# 把 wic 镜像烧到 eMMC（Rockusb / Maskrom 模式）
#
# 用法：
#   sudo ./scripts/flash-emmc.sh build/latest/lubancat-image-minimal.wic.gz
#   sudo ./scripts/flash-emmc.sh xxx.wic.gz --loader ./rk3588_spl_loader_v1.19.113.bin
#
# 说明：
#   - 板子先进入 loader 模式：按住 REC 再上电，或系统里 `reboot loader`
#   - 首次（Maskrom）需要先下载 loader；若是 loader 模式可省略 --loader
set -euo pipefail

IMG="${1:-}"
shift || true
LOADER=""

while [ $# -gt 0 ]; do
    case "$1" in
        --loader) LOADER="$2"; shift 2 ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
done

[ -n "$IMG" ] || { echo "用法: $0 <image.wic.gz> [--loader <loader.bin>]" >&2; exit 1; }
[ -f "$IMG" ] || { echo "找不到 $IMG" >&2; exit 1; }
command -v rkdeveloptool >/dev/null || { echo "缺 rkdeveloptool，见 scripts/host-deps.sh" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

case "$IMG" in
    *.gz) echo "==> 解压"; gunzip -c "$IMG" > "$WORK/disk.wic" ;;
    *)    cp "$IMG" "$WORK/disk.wic" ;;
esac

echo "==> 设备列表"
rkdeveloptool ld || true

if [ -n "$LOADER" ]; then
    echo "==> 下载 loader: $LOADER"
    rkdeveloptool db "$LOADER"
fi

echo "==> 写 LBA 0（整盘 wic）"
rkdeveloptool wl 0 "$WORK/disk.wic"

echo "==> 复位"
rkdeveloptool rd

echo "完成。串口 1500000 8N1 观察启动。"
echo "常见失败："
echo "  - 'Creating Comm Object failed' → udev 规则缺失或没进 loader 模式"
echo "  - 写完不启动 → 确认 idblock 在 sector 64、uboot 在 2M（见手册第 10 章）"
