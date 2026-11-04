#!/bin/sh
# 首次启动把 rootfs 扩到分区末尾。
#
# 分工要说清楚：
#   - 分区表：afptool 按 parameter 的 `-@0x00048000(rootfs:grow)` 已经把 p3 拉到磁盘末尾，
#     不需要 parted/sgdisk 改 GPT（厂商 debian 的 disk-helper 也只做文件系统扩容）。
#   - 文件系统：镜像里是打包时的大小，必须 resize2fs 一次。ext4 支持在线扩容，
#     根分区挂着也能扩。
#
# 幂等：成功后写 /var/lib/lubancat/.rootfs-resized，服务带 ConditionPathExists 也不再跑。
set -u

FLAG_DIR=/var/lib/lubancat
FLAG=$FLAG_DIR/.rootfs-resized

[ -e "$FLAG" ] && exit 0

# 1) 找根设备：/proc/mounts 里挂到 / 的那一行
ROOT=$(awk '$2 == "/" { print $1; exit }' /proc/mounts)
[ -n "${ROOT:-}" ] || { echo "lubancat-resize: 找不到根挂载点"; exit 0; }

ROOT=$(readlink -f "$ROOT")
case "$ROOT" in
    /dev/*) ;;
    *) echo "lubancat-resize: 根不是块设备（$ROOT），跳过"; exit 0 ;;
esac

PART=${ROOT##*/}                       # 例如 mmcblk0p3
NUM=$(cat "/sys/class/block/$PART/partition" 2>/dev/null || true)
[ -n "$NUM" ] || { echo "lubancat-resize: $PART 不是分区，跳过"; exit 0; }

# 2) 磁盘名：mmcblk0p3 -> mmcblk0；sda3 -> sda
case "$PART" in
    *p"$NUM") DISK=${PART%p"$NUM"} ;;
    *)        DISK=$(echo "$PART" | sed 's/[0-9]*$//') ;;
esac

# 3) 分区没到磁盘末尾时提示（正常情况下不该发生；发生了说明 grow 没生效）
if [ -r "/sys/class/block/$PART/start" ] && [ -r "/sys/class/block/$PART/size" ] \
   && [ -r "/sys/class/block/$DISK/size" ]; then
    P_START=$(cat "/sys/class/block/$PART/start")
    P_SIZE=$(cat "/sys/class/block/$PART/size")
    D_SIZE=$(cat "/sys/class/block/$DISK/size")
    # 末尾留 34 扇区给 GPT 备份表
    if [ $((P_START + P_SIZE)) -lt $((D_SIZE - 34)) ]; then
        echo "lubancat-resize: 注意！$PART 未到 /dev/$DISK 末尾（$((P_START + P_SIZE)) < $((D_SIZE - 34))）"
        echo "lubancat-resize: 分区表没 grow，文件系统只能扩到当前分区大小"
        if command -v growpart >/dev/null 2>&1; then
            growpart "/dev/$DISK" "$NUM" || echo "lubancat-resize: growpart 失败"
        fi
    fi
fi

# 4) 扩文件系统（在线，幂等）
echo "lubancat-resize: resize2fs $ROOT"
if resize2fs "$ROOT"; then
    mkdir -p "$FLAG_DIR"
    touch "$FLAG"
    echo "lubancat-resize: 完成"
else
    echo "lubancat-resize: resize2fs 失败，下次启动重试"
    exit 1
fi
