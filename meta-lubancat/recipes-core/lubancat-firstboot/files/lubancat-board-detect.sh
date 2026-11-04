#!/bin/sh
# 首次启动：按 SoC + ADC 板卡 ID 选择设备树与 uEnv，写回 boot 分区后重启。
#
# 为什么必须重启：dtb 是内核启动参数，U-Boot 在启动瞬间从 boot 分区读 rk-kernel.dtb，
# 运行中的内核换不了自己那棵树。本脚本只负责把"下一次启动用哪份"定下来。
#
# 与厂商 boot_init.sh 的差别：厂商用软链（ln -sf），这里用**拷贝**。
# U-Boot 2017.09 源码里确实有 ext4fs_read_symlink（fs/ext4/ext4_common.c:2177），
# 但我们没法在硬件上验证它跟随软链的行为；拷贝零风险，代价只是多占 265 KB。
set -u

TABLE=/usr/share/lubancat/board-table
BOOT_DEV=/dev/disk/by-partlabel/boot
MNT=/run/lubancat-boot
FLAG=$MNT/.board-detected

log() { echo "lubancat-board: $*"; }

# boot 分区定位：优先 GPT 分区名；拿不到就从 /proc/cmdline 的 root= + boot_part= 推。
# 后者是 boot.cmd 一定会写进去的（root=/dev/mmcblk0p3 boot_part=2），比 by-partlabel 更稳。
find_boot_dev() {
    i=0
    while [ "$i" -lt 50 ]; do
        [ -e "$BOOT_DEV" ] && { echo "$BOOT_DEV"; return 0; }
        sleep 0.1
        i=$((i + 1))
    done

    root=""
    bpart=""
    for x in $(cat /proc/cmdline); do
        case "$x" in
            root=*)      root=${x#root=} ;;
            boot_part=*) bpart=${x#boot_part=} ;;
        esac
    done
    if [ -n "$root" ] && [ -n "$bpart" ]; then
        echo "${root%[0-9]*}$bpart"
        return 0
    fi
    return 1
}

BOOT_DEV=$(find_boot_dev) || { log "找不到 boot 分区（by-partlabel 与 cmdline 都没给）"; exit 0; }
[ -b "$BOOT_DEV" ] || { log "$BOOT_DEV 不是块设备"; exit 0; }
log "boot 分区 = $BOOT_DEV"

mkdir -p "$MNT"
grep -qs " $MNT " /proc/mounts || mount "$BOOT_DEV" "$MNT" || { log "挂载 $BOOT_DEV 失败"; exit 0; }

# 已识别过就退出。标记放在 boot 分区：重刷镜像自然复位，重装 rootfs 不会误判。
if [ -e "$FLAG" ]; then
    log "已识别过（$FLAG 存在），跳过"
    umount "$MNT"
    exit 0
fi

# ---- 1) SoC：compatible 第一项，形如 rockchip,rk3588s-lubancat-4-v1 ----
COMPAT=$(tr '\0' '\n' < /proc/device-tree/compatible 2>/dev/null | head -n1)
SOC=${COMPAT#*,}
SOC=${SOC%%-*}
case "$SOC" in
    rk3566|rk3568)  FAM=rk356x ;;
    rk3588|rk3588s) FAM=rk3588 ;;
    rk3528*)        FAM=rk3528 ;;
    *)              FAM=$SOC ;;
esac
log "compatible=$COMPAT soc=$SOC family=$FAM"

# ---- 2) ADC：找 saradc 的 iio 设备（不假设 iio:device0）----
IIO=""
for d in /sys/bus/iio/devices/iio:device*; do
    [ -e "$d/name" ] || continue
    if grep -qi 'saradc' "$d/name" 2>/dev/null; then IIO=$d; break; fi
done
if [ -z "$IIO" ]; then
    log "没有 saradc 的 iio 设备，保持当前 dtb（generic 也能用）"
    umount "$MNT"
    exit 0
fi

# 阈值表与厂商一致：12bit 是 916/1376/1840/2380/2928/3432/3900/4096，
# 10bit 是它的 1/4（229/344/460/595/732/858/975/1024）。用 scale 的整数位判断位数，
# 避免依赖 bc/awk 做浮点比较。
SCALE=$(cat "$IIO/in_voltage_scale" 2>/dev/null || echo 0)
INT=${SCALE%%.*}
if [ "${INT:-0}" -ge 1 ] 2>/dev/null; then
    TAB="229 344 460 595 732 858 975 1024"
else
    TAB="916 1376 1840 2380 2928 3432 3900 4096"
fi

adc_index() {   # $1=channel，输出 00..07
    raw=$(cat "$IIO/in_voltage$1_raw" 2>/dev/null) || { printf '07'; return; }
    i=0
    for t in $TAB; do
        if [ "$raw" -lt "$t" ]; then printf '%02d' "$i"; return; fi
        i=$((i + 1))
    done
    printf '07'
}

H=$(adc_index 2)
L=$(adc_index 3)
BID="${H}${L}"
log "adc ch2=$H ch3=$L board_id=$BID"

# ---- 3) 查表 ----
LINE=$(grep -m1 "^${FAM} ${BID} " "$TABLE" 2>/dev/null)
if [ -z "$LINE" ]; then
    log "board_id=$BID 不在表里，保持当前 dtb（generic 也能用）"
    umount "$MNT"
    exit 0
fi

DTB=$(echo "$LINE" | cut -d' ' -f3)
UENV=$(echo "$LINE" | cut -d' ' -f4)
NAME=$(echo "$LINE" | cut -d' ' -f5-)
log "识别为 $NAME -> dtb=$DTB uEnv=$UENV"

if [ ! -f "$MNT/dtb/$DTB" ]; then
    log "boot 分区没有 dtb/$DTB，保持当前"
    umount "$MNT"
    exit 0
fi

# ---- 4) 判断是否真的需要改（板级别名镜像本来就是对的那份，别白重启一次）----
CHANGED=0
cmp -s "$MNT/dtb/$DTB" "$MNT/rk-kernel.dtb" || CHANGED=1
if [ -f "$MNT/uEnv/$UENV" ]; then
    cmp -s "$MNT/uEnv/$UENV" "$MNT/uEnv/uEnv.txt" || CHANGED=1
fi
if [ "$CHANGED" = "0" ]; then
    log "已经是 $NAME，无需切换"
    touch "$FLAG"
    umount "$MNT"
    exit 0
fi

# ---- 5) 应用：先写临时文件再 mv，避免掉电留下半截 dtb ----
cp -f "$MNT/dtb/$DTB" "$MNT/rk-kernel.dtb.new" && mv -f "$MNT/rk-kernel.dtb.new" "$MNT/rk-kernel.dtb"
if [ -f "$MNT/uEnv/$UENV" ]; then
    cp -f "$MNT/uEnv/$UENV" "$MNT/uEnv/uEnv.txt.new" && mv -f "$MNT/uEnv/uEnv.txt.new" "$MNT/uEnv/uEnv.txt"
else
    log "boot 分区没有 uEnv/$UENV，uEnv 保持不动"
fi
sync
touch "$FLAG"
umount "$MNT"

log "已切换到 $NAME，重启生效"
reboot
