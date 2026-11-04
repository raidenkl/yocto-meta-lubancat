# 把 U-Boot 与 rkbin 换成 LubanCat 官方仓库，并支持「defconfig + 片段」的逐族配置
#
# 布局约束（不能改）：u-boot-rockchip.bb 的 make.sh 里硬编码
#     RKBIN_TOOLS=../rkbin/tools
# 并且 recipe 本来就用 destsuffix=rkbin 把 rkbin 拉到 ${WORKDIR}/rkbin，
# ${S} 是 ${WORKDIR}/git，所以 ../rkbin 正好成立。改 destsuffix 会直接找不到 rkbin。
#
# 为什么保留上游 recipe 的 make.sh 流程而不是自己调 make：
#   make.sh 末行是 `make PYTHON=python2 ...`，而 recipe 的 do_configure:prepend
#   已经把 make.sh 里的 make 行删掉、并把若干 .py 的 shebang 改成 python3，
#   由 u-boot.inc 负责真正编译，make.sh 只负责打包 idblock.img / uboot.img / uboot.img。
#   自己重写这段反而更容易踩 python2 的坑。
#
# 注意：**不要**在这里再定义 do_configure:prepend()。上游 recipe 已经有同名的
# prepend 函数体，bbappend 里同名再定义会把上游那份整段替换掉（python2→python3
# 的修复全丢）。所以本层用一个独立任务插在 do_patch 与 do_configure 之间。
#
# 六族差异只在三处，全部由 conf/machine/lubancat-<family>.inc 提供：
#   UBOOT_MACHINE            defconfig 文件名
#   LUBANCAT_UBOOT_FRAGMENT  追加片段（只有 rk3566 用，值为 rk3566.config）
#   LUBANCAT_UBOOT_CFG       传给 make.sh 的板名（= RK_SOC_FAMILY）
# 本文件不含任何 SoC 硬编码。

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = " \
    git://github.com/LubanCat/u-boot.git;protocol=https;branch=main \
    git://github.com/LubanCat/rkbin.git;protocol=https;branch=master;name=rkbin;destsuffix=rkbin \
"

# 取法：git ls-remote https://github.com/LubanCat/u-boot.git refs/heads/main
SRCREV = "a564b1d927aa6032520819536a5b8c450e8141c4"
# 取法：git ls-remote https://github.com/LubanCat/rkbin.git refs/heads/master
SRCREV_rkbin = "74213af1e952c4683d2e35952507133b61394862"
SRCREV_FORMAT = "default_rkbin"

# UBOOT_MACHINE 由机器 conf 给，这里不写死。

# 逐族配置片段，文件名跟 LUBANCAT_FAMILY 走（rockchip 前缀由 rc 文件保证存在）
SRC_URI += "file://${LUBANCAT_FAMILY}-lubancat.cfg"

# recipe 的 do_compile:append 会在 RK_UBOOT_CFG 为空时回退 RK_SOC_FAMILY；
# 这里显式给出，rk3566 也保持 rk3568（arch/arm/mach-rockchip 下只有该目录）。
RK_UBOOT_CFG ?= "${LUBANCAT_UBOOT_CFG}"

# 为什么用独立任务而不是 do_configure:prepend()：见文件头注释。
do_lubancat_uboot_defconfig() {
    cfg="${WORKDIR}/${LUBANCAT_FAMILY}-lubancat.cfg"
    defcfg="${S}/configs/${UBOOT_MACHINE}"

    [ -f "$cfg" ] || bbfatal "missing ${cfg}"
    [ -f "$defcfg" ] || bbfatal "no ${defcfg}; check UBOOT_MACHINE (ls configs | grep ${LUBANCAT_FAMILY})"

    # 用 marker 去重：同一个 ${S} 上可能多次执行，无脑 cat >> 会越堆越多
    if grep -q "LUBANCAT-CFG-BEGIN" "$defcfg"; then
        bbnote "defconfig already patched, skip"
        return 0
    fi

    # 1) 官方片段先并入（如 rk3566.config：CONFIG_BASE_DEFCONFIG / CONFIG_LOADER_INI）
    #    走 defconfig 路径时 kconfig 的 conf_read 认 "# CONFIG_X is not set"，
    #    与 .cfg 片段走 merge_config.sh（会删注释行）的行为不同，不要混淆。
    if [ -n "${LUBANCAT_UBOOT_FRAGMENT}" ]; then
        frag="${S}/configs/${LUBANCAT_UBOOT_FRAGMENT}"
        [ -f "$frag" ] || bbfatal "no fragment ${frag} (LUBANCAT_UBOOT_FRAGMENT)"
        {
            echo ""
            echo "# ---- LUBANCAT-FRAG-BEGIN (${LUBANCAT_UBOOT_FRAGMENT}) ----"
            cat "$frag"
            echo "# ---- LUBANCAT-FRAG-END ----"
        } >> "$defcfg"
        bbnote "merged ${LUBANCAT_UBOOT_FRAGMENT} into ${defcfg}"
    fi

    # 2) 本族的增量（后写者覆盖前写者，所以 LOADER_INI 之类可以在这里改）
    {
        echo ""
        echo "# ---- LUBANCAT-CFG-BEGIN (meta-lubancat) ----"
        cat "$cfg"
        echo "# ---- LUBANCAT-CFG-END ----"
    } >> "$defcfg"

    bbnote "appended ${LUBANCAT_FAMILY}-lubancat.cfg to ${defcfg}"
}
addtask lubancat_uboot_defconfig after do_patch before do_configure

# 编译期断言：DDR bin 与板卡内存参数必须对得上。
# 配错档位表现的是一句话都不打印的「假死」，极难定位。
do_compile:prepend() {
    ini="${WORKDIR}/rkbin/RKBOOT/${LUBANCAT_RKBIN_INI}"

    if [ -f "$ini" ]; then
        if ! grep -q "${LUBANCAT_DDR_BIN}" "$ini"; then
            bbfatal "DDR bin mismatch: ${ini} 里没有 ${LUBANCAT_DDR_BIN}。请确认 rkbin 分支/提交，或同步修改 LUBANCAT_DDR_BIN。"
        fi
        bbnote "rkbin DDR bin: $(grep -A2 '^\[CODE471_OPTION\]' "$ini" | grep -m1 Path1)"
    else
        bbwarn "${ini} 不存在，跳过 DDR bin 断言"
    fi
}

# 编译后断言：dtfile 是 Rockchip 私有命令，挂 CONFIG_CMD_FDT 之下、没有独立 Kconfig
# 符号。uEnv.txt 里的 dtoverlay= 全靠它解析并 fdt apply，缺了就是「overlay 静默不生效」。
do_compile:append() {
    # 不要用 `strings u-boot | grep dtfile` 判断：命令表里的字符串在 ELF 里不一定
    # 以独立可打印串出现（SDK 里 CONFIG_CMD_FDT=y 的 u-boot 也 grep 不到），
    # 而 uboot.img 又是打包/压缩过的。可靠判据是编译产物本身：
    #   cmd/dtfile.o 存在 + .config 里 CONFIG_CMD_FDT=y
    if [ -f "${B}/cmd/dtfile.o" ]; then
        bbnote "dtfile 已编入（cmd/dtfile.o）"
    elif [ -f "${S}/cmd/dtfile.c" ]; then
        bbwarn "cmd/dtfile.c 存在但没编出 cmd/dtfile.o：检查 ${B}/.config 里 CONFIG_CMD_FDT=y"
    else
        bbwarn "源码树里没有 cmd/dtfile.c：uEnv 的 dtoverlay= 将不生效（extboot + 内核 dtb 切换不受影响）"
    fi
}
