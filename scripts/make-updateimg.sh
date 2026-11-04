#!/bin/bash
# 把 Yocto 产物打成 Rockchip rkfw 格式的 update.img（RKDevTool / upgrade_tool 可用）
#
# 两种布局：
#   EXTBOOT=1（默认）boot 分区 = ext2 文件系统（bootable 标志）
#       分区：uboot 0x4000@0x4000 / boot 0x40000@0x8000(boot:bootable) / rootfs -@0x48000(grow)
#       boot 内容来自 extboot-image recipe 的 boot-ext2.img（含 boot.scr、rk-kernel.dtb、
#       dtb/、dtb/overlay/、uEnv/uEnv.txt）
#   EXTBOOT=0        旧 FIT 布局（boot.img = kernel+dtb 单包），作为逃生路径保留
#
# 为什么参数表要自己写：
#   1) SDK 模板的 rootfs UUID 是 614e…4b53…，与我们内核 dtsi 的 PARTUUID 不一致；
#   2) extboot 布局要求 boot 128 MiB 且带 bootable 位，SDK 的 .chips 模板可直接用，
#      但里面的 uuid 仍要换。
#
# 为什么不再硬编码 -RK3588：
#   rkImageMaker 的第一个参数是芯片型号。loader.bin 在偏移 21 处存了反序的 4 位芯片号
#   （R​K3588 → "8853"），官方 device/rockchip/common/scripts/mk-updateimg.sh 就是这么取的。
#   一条脚本因此可以覆盖 rk3528/3562/3566/3568/3576/3588 全系。
#
# 用法（在仓库根执行）：
#   ./scripts/make-updateimg.sh
#   MACHINE=lubancat-rk3568 ./scripts/make-updateimg.sh
#   EXTBOOT=0 ./scripts/make-updateimg.sh          # 回退到旧 FIT 布局（逃生路径）
#   IMAGE=lubancat-image-full ./scripts/make-updateimg.sh   # 明确指定用哪份 rootfs
#   ROOTFS=/abs/path/xxx.rootfs.ext4 ./scripts/make-updateimg.sh
#   PACK=/path/to/sdk/tools/linux/Linux_Pack_Firmware/rockdev ./scripts/make-updateimg.sh
#
# PACK 默认指向本仓库的 tools/rkpack（自带 afptool + rkImageMaker），
# 所以**不需要安装 Rockchip SDK**；要用自备 SDK 时用 PACK= 覆盖即可。

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

MACHINE=${MACHINE:-lubancat-4-v1}
DEPLOY=${DEPLOY:-$REPO_ROOT/build/tmp/deploy/images/$MACHINE}
PACK=${PACK:-$REPO_ROOT/tools/rkpack}
WORK=${WORK:-$REPO_ROOT/build/updateimg}
EXTBOOT=${EXTBOOT:-1}

# 必须与内核 bootargs 里的 root= 一致（extboot 下 boot.scr 用 /dev/mmcblk0p3，
# 这个 uuid 只对 EXTBOOT=0 有意义，但留着不影响 afptool）
ROOTFS_UUID=${ROOTFS_UUID:-614e0000-0000-4000-8000-000000000000}
BOOT_UUID=${BOOT_UUID:-7A3F0000-0000-446A-8000-702F00006273}

die() { echo "ERROR: $*" >&2; exit 1; }
resolve() { readlink -f "$1" 2>/dev/null || echo "$1"; }

[ -x "$PACK/afptool" ]      || die "找不到可执行的 $PACK/afptool
    - 仓库自带工具应在 tools/rkpack/，请确认没有被 .gitignore/杀软删掉
    - 或用自备 SDK：PACK=<SDK>/tools/linux/Linux_Pack_Firmware/rockdev $0"
[ -x "$PACK/rkImageMaker" ] || die "找不到可执行的 $PACK/rkImageMaker（同 afptool 的排查方式）"
[ -d "$DEPLOY" ]            || die "找不到 deploy 目录 $DEPLOY（MACHINE=$MACHINE 还没编？或 MACHINE 写错）"

LOADER=$(resolve "$DEPLOY/loader.bin")
UBOOT=$(resolve "$DEPLOY/uboot.img")
# rootfs 选择：**不能**用 `ls -1 | head -1`——那是字母序，`lubancat-image-full` 永远排在
# `lubancat-image-minimal` 前面，于是你重编了 minimal，包里塞的还是几天前的 full。
# 默认按修改时间取最新的一份；也可以用 IMAGE=lubancat-image-minimal 或 ROOTFS=/path 指定。
if [ -n "${ROOTFS:-}" ]; then
    ROOTFS=$(resolve "$ROOTFS")
elif [ -n "${IMAGE:-}" ]; then
    ROOTFS=$(resolve "$(ls -1t "$DEPLOY"/${IMAGE}-*.rootfs.ext4 2>/dev/null | head -1)")
else
    ROOTFS=$(resolve "$(ls -1t "$DEPLOY"/*.rootfs.ext4 2>/dev/null | head -1)")
fi

# 多份 rootfs 并存时把选择结果打出来，避免又选错
mapfile -t _all < <(ls -1t "$DEPLOY"/*.rootfs.ext4 2>/dev/null)
if [ "${#_all[@]}" -gt 1 ]; then
    echo "==> 注意：deploy 里有 ${#_all[@]} 份 rootfs，按修改时间选了最新的一份："
    printf '    %s  (%s)\n' "$(basename "$ROOTFS")" "$(date -r "$ROOTFS" '+%F %T')"
    echo "    其他：$(for f in "${_all[@]:1}"; do printf '%s ' "$(basename "$f")"; done)"
    echo "    要指定请用 IMAGE=lubancat-image-minimal 或 ROOTFS=/abs/path"
fi

if [ "$EXTBOOT" = "1" ]; then
    BOOT=$(resolve "$DEPLOY/boot-ext2.img")
else
    BOOT=$(resolve "$DEPLOY/boot.img")
fi

for f in "$LOADER" "$UBOOT" "$BOOT" "$ROOTFS"; do
    [ -f "$f" ] || die "缺少镜像文件: $f"
done

# ---- 芯片型号：从 loader.bin 偏移 21 的 4 字节反序读出（RK3588 -> "8853" -> rev）----
# 用 dd 而不是 hexdump：hexdump 读管道时会报 "Illegal seek"（-s 需要可 seek 的输入），
# 直接给文件路径可以，但管道不行——这里统一用 dd，也少一个工具依赖。
TAG=$(dd if="$LOADER" bs=1 skip=21 count=4 2>/dev/null | rev)
case "$TAG" in
    [0-9][0-9][0-9][0-9]) TAG="RK$TAG" ;;
    *) die "无法从 $LOADER 推断芯片型号（offset 21 = '$TAG'）" ;;
esac
echo "==> 芯片型号: $TAG（由 loader.bin 头部推断）"

echo "==> 源文件（EXTBOOT=$EXTBOOT）"
printf '  %-10s %12s  %s\n' loader  "$(stat -c %s "$LOADER")" "$LOADER"
printf '  %-10s %12s  %s\n' uboot   "$(stat -c %s "$UBOOT")"  "$UBOOT"
printf '  %-10s %12s  %s\n' boot    "$(stat -c %s "$BOOT")"   "$BOOT"
printf '  %-10s %12s  %s\n' rootfs  "$(stat -c %s "$ROOTFS")" "$ROOTFS"

if [ "$EXTBOOT" = "1" ]; then
    boot_size=$(stat -c %s "$BOOT")
    # parameter 里 boot 是 0x40000 扇区 = 128 MiB，必须严格相等，
    # 否则 afptool 会因为「分区装不下」或「写入越界」报错
    [ "$boot_size" -eq $((0x40000 * 512)) ] \
        || die "boot-ext2.img 是 $boot_size 字节，但 parameter 的 boot 分区是 $((0x40000*512)) 字节（128 MiB）。同步改 EXTBOOT_SIZE_MB 与 CMDLINE。"
    file "$BOOT" | grep -qi 'ext[234] filesystem' \
        || die "$BOOT 不像 ext2 镜像（extboot-image 没生效？）"
fi

rm -rf "$WORK"; mkdir -p "$WORK/Image"
ln -f "$LOADER" "$WORK/Image/MiniLoaderAll.bin"
ln -f "$UBOOT"  "$WORK/Image/uboot.img"
ln -f "$BOOT"   "$WORK/Image/boot.img"     # extboot 下这个文件名承载的是 ext2 镜像
ln -f "$ROOTFS" "$WORK/Image/rootfs.img"

if [ "$EXTBOOT" = "1" ]; then
    # extboot 几何：boot 128 MiB 且带 bootable 位；rootfs 从 0x48000 扇区起、grow 到结尾
    # （rootfs 不再是固定 448 MiB，full 镜像超限的老问题随之消失）
    CMDLINE_BOOT='0x00040000@0x00008000(boot:bootable)'
    CMDLINE_ROOTFS='-@0x00048000(rootfs:grow)'
else
    CMDLINE_BOOT='0x00020000@0x00008000(boot)'
    CMDLINE_ROOTFS='0x01c00000@0x00078000(rootfs)'
fi

cat > "$WORK/Image/parameter.txt" <<EOF
FIRMWARE_VER: 1.0
MACHINE_MODEL: $MACHINE
MACHINE_ID: 007
MANUFACTURER: LubanCat
MAGIC: 0x5041524B
ATAG: 0x00200800
MACHINE: 0xffffffff
CHECK_MASK: 0x80
PWR_HLD: 0,0,A,0,1
TYPE: GPT
GROW_ALIGN: 0
CMDLINE: mtdparts=:0x00004000@0x00004000(uboot),$CMDLINE_BOOT,$CMDLINE_ROOTFS
uuid:rootfs=$ROOTFS_UUID
uuid:boot=$BOOT_UUID
EOF

if [ "$EXTBOOT" != "1" ]; then
    # 旧布局额外保留 misc/recovery/backup/oem/userdata 的占位，行为与历史版本一致
    sed -i 's|^CMDLINE: .*|CMDLINE: mtdparts=:0x00002000@0x00004000(uboot),0x00002000@0x00006000(misc),0x00020000@0x00008000(boot),0x00040000@0x00028000(recovery),0x00010000@0x00068000(backup),0x01c00000@0x00078000(rootfs),0x00040000@0x01c78000(oem),-@0x01cb8000(userdata:grow)|' "$WORK/Image/parameter.txt"
fi

# 只列我们真正提供的分区；parameter 里定义但 package-file 不列的分区不会被写内容
cat > "$WORK/package-file" <<'EOF'
# NAME          Relative path
package-file    package-file
bootloader      Image/MiniLoaderAll.bin
parameter       Image/parameter.txt
uboot           Image/uboot.img
boot            Image/boot.img
rootfs          Image/rootfs.img
EOF

cd "$WORK"
echo "==> afptool -pack"
"$PACK/afptool" -pack ./ Image/update.img

echo "==> rkImageMaker -$TAG"
"$PACK/rkImageMaker" "-$TAG" Image/MiniLoaderAll.bin Image/update.img update.img -os_type:androidos

[ -f update.img ] || die "update.img 未生成"
echo
echo "==> 完成"
ls -lh update.img
echo "魔数检查（应为 RKFW）: $(head -c 4 update.img | tr -d '\0')"
echo
echo "烧写（板子进 loader/maskrom 后）："
echo "  sudo upgrade_tool uf $WORK/update.img"
echo "  # 或 Windows 下用 RKDevTool 选「升级固件 → 固件」"
