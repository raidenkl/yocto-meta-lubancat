SUMMARY = "LubanCat extboot: boot 分区 ext2 镜像（boot.scr + Image + rk-kernel.dtb + 全族 dtb/dtbo + uEnv）"
DESCRIPTION = "生成厂商 extboot 风格的 boot 分区：ext2 文件系统、label=boot、由 parameter.txt \
的 (boot:bootable) 打上 GPT bootable 位。U-Boot 的 distro_bootcmd 会扫到 boot.scr，\
boot.scr 再读 uEnv/uEnv.txt（用户变量层），由 dtfile 应用 dtoverlay= 行。"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# mkfs.ext2 / debugfs：造镜像 + 自检
# 刻意**不**依赖 u-boot-tools-native：poky 的 u-boot-tools 只从 source.denx.de 拉
# （实测 25 KB/s，浅克隆要 1 小时），而它唯一提供的就是 mkimage 一个命令。
# 这里优先用 sysroot-native 的 mkimage，没有则回退主机 /usr/bin/mkimage，
# 并在构建日志里明确警告。主机依赖见 scripts/host-deps.sh（u-boot-tools）。
DEPENDS = "e2fsprogs-native"

inherit deploy

SRC_URI = "file://readme.txt"

S = "${WORKDIR}"

# boot 分区大小**必须**与 parameter.txt 的 boot 段扇区数一致：
#   0x40000 扇区 × 512 B = 128 MiB
# 改这里就要同步改 scripts/make-updateimg.sh 里的 EXTBOOT_PARAM_CMDLINE。
EXTBOOT_SIZE_MB ?= "128"

# 族内全量 dtb 是否都进 boot 分区（1=是）。板级别名 machine 不写这个变量时，
# 靠这里的默认值兜底——族机器 conf 里也写了一份，两处一致即可。
LUBANCAT_FAMILY_ALL_DTBS ?= "1"

# 取内核产物（Image）与内核树里的模板（boot.cmd / uEnv/<soc>/uEnvLubanCat*.txt）
do_compile[depends] += "virtual/kernel:do_deploy virtual/kernel:do_shared_workdir"

do_compile() {
    root="${WORKDIR}/extboot-root"
    ksrc="${STAGING_KERNEL_DIR}/arch/arm64/boot/dts/rockchip/uEnv"
    ddir="${DEPLOY_DIR_IMAGE}/dtb"
    img="${WORKDIR}/boot-ext2.img"

    rm -rf "$root" "$img"
    install -d "$root/dtb/overlay" "$root/uEnv"

    # ---- 1) boot.cmd 来自内核树，逐字使用，不固化、不改写 ----
    # 厂商版本已经处理了「无 initrd」：booti ${kernel_addr_r} - ${fdt_addr_r}。
    [ -f "$ksrc/boot.cmd" ] || bbfatal "找不到 ${ksrc}/boot.cmd（内核树的 uEnv 目录结构变了？）"

    # bitbake 任务的 PATH 只有 hosttools + sysroot-native，看不到 /usr/bin，
    # 所以不能用 command -v，必须按绝对路径逐个试。
    MKIMAGE=""
    for c in "${STAGING_BINDIR_NATIVE}/mkimage" /usr/bin/mkimage /usr/local/bin/mkimage; do
        if [ -x "$c" ]; then MKIMAGE="$c"; break; fi
    done
    [ -n "$MKIMAGE" ] || bbfatal "需要 mkimage：sudo apt-get install -y u-boot-tools（或 bitbake u-boot-tools-native 后重跑）"
    case "$MKIMAGE" in
        "${STAGING_BINDIR_NATIVE}"/*) ;;
        *) bbwarn "使用主机 mkimage（$MKIMAGE）。要完全可复现请 bitbake u-boot-tools-native 并把它加回 DEPENDS。" ;;
    esac
    "$MKIMAGE" -A arm -O linux -T script -C none -n "LubanCat extboot" \
        -d "$ksrc/boot.cmd" "$root/boot.scr" > /dev/null

    # ---- 2) 内核与 dtb ----
    [ -f "${DEPLOY_DIR_IMAGE}/Image" ] || bbfatal "缺 ${DEPLOY_DIR_IMAGE}/Image：先 bitbake virtual/kernel"
    install -m 0644 "${DEPLOY_DIR_IMAGE}/Image" "$root/Image"

    [ -f "$ddir/${LUBANCAT_DTB}" ] || bbfatal "缺 $ddir/${LUBANCAT_DTB}：检查 LUBANCAT_DTB 与内核 do_deploy"
    # U-Boot 早期 DTB 与内核 DTB 必须同源，都指向这一份
    install -m 0644 "$ddir/${LUBANCAT_DTB}" "$root/rk-kernel.dtb"

    if [ "${LUBANCAT_FAMILY_ALL_DTBS}" = "1" ]; then
        for f in "$ddir"/*.dtb; do
            [ -e "$f" ] && install -m 0644 "$f" "$root/dtb/"
        done
    else
        install -m 0644 "$ddir/${LUBANCAT_DTB}" "$root/dtb/"
    fi
    for f in "$ddir"/overlay/*.dtbo; do
        [ -e "$f" ] && install -m 0644 "$f" "$root/dtb/overlay/"
    done

    # ---- 3) uEnv：只替换 cmdline 一行，其余（含逐板 dtoverlay= 候选清单）原样保留 ----
    # 先把该族所有 uEnvLubanCat*.txt 都放进去（约 30~60 KB），
    # 这样板上想换板时只需把 /uEnv/uEnv.txt 指到另一份（厂商 boot_init.sh 的做法），
    # 不必重新打包。随后生成真正的 /uEnv/uEnv.txt（已改 cmdline），会覆盖同名项。
    if [ -d "$ksrc/${LUBANCAT_UENV_DIR}" ]; then
        for f in "$ksrc/${LUBANCAT_UENV_DIR}"/*.txt; do
            [ -e "$f" ] || continue
            # 每份都要改 cmdline：切板脚本会直接把某份模板拷成 /uEnv/uEnv.txt，
            # 模板里若还是厂商的 `console=ttyFIQ0`（无波特率）就会串口全黑。
            sed -e "s|^cmdline=.*|cmdline=\"${LUBANCAT_CMDLINE}\"|" "$f" > "$root/uEnv/$(basename "$f")"
        done
    fi

    uenv="$ksrc/${LUBANCAT_UENV_DIR}/${LUBANCAT_UENV}"
    # 族镜像默认用 generic dtb，对应的 uEnv 模板在内核树的 uEnv/ 根目录（uEnvLubanCat.txt）
    [ -f "$uenv" ] || uenv="$ksrc/${LUBANCAT_UENV}"
    [ -f "$uenv" ] || bbfatal "找不到 uEnv 模板：${LUBANCAT_UENV_DIR}/${LUBANCAT_UENV} 与根目录 ${LUBANCAT_UENV} 都不存在"
    sed -e "s|^cmdline=.*|cmdline=\"${LUBANCAT_CMDLINE}\"|" "$uenv" > "$root/uEnv/uEnv.txt"

    # ---- 4) 断言（这些错了不会立刻报错，只会「串口全黑」或「overlay 静默不生效」）----
    grep -q '^cmdline=.*1500000n8' "$root/uEnv/uEnv.txt" \
        || bbfatal "uEnv 的 cmdline 没有 1500000n8：uEnv 会覆盖 dts 的 bootargs，串口将无输出"
    n_dtbo=$(ls "$root/dtb/overlay"/*.dtbo 2>/dev/null | wc -l)
    [ "$n_dtbo" -gt 0 ] || bbfatal "boot 分区里 0 个 dtbo：内核的 do_lubancat_dtbs 没跑或没 deploy"
    [ -f "$root/rk-kernel.dtb" ] || bbfatal "rk-kernel.dtb 缺失"

    # ---- 5) 造 ext2 ----
    truncate -s ${EXTBOOT_SIZE_MB}M "$img"
    mkfs.ext2 -q -F -L boot -d "$root" "$img"

    # ---- 6) 自检：不信任 mkfs 的返回码，直接读回镜像里的内容 ----
    debugfs -R "ls -l /" "$img" 2>/dev/null | grep -q boot.scr \
        || bbfatal "boot-ext2.img 里没有 boot.scr"
    debugfs -R "cat /uEnv/uEnv.txt" "$img" 2>/dev/null | grep -q 1500000n8 \
        || bbfatal "boot-ext2.img 里的 uEnv.txt 内容不对"

    bbnote "boot-ext2.img: $(du -h "$img" | cut -f1), dtb=$(ls "$root/dtb"/*.dtb 2>/dev/null | wc -l), dtbo=${n_dtbo}"
}

do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 ${WORKDIR}/boot-ext2.img ${DEPLOYDIR}/boot-ext2.img
}
# 显式声明：只靠 `inherit deploy` 时，某些组合下 do_build 不会把 do_deploy 串进来
# （实测 scarthgap 上 `bitbake -c listtasks` 里只有 do_deploy_setscene）。
addtask deploy after do_compile before do_build
