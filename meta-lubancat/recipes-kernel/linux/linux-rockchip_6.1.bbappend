# 把 BSP 内核换成 LubanCat 官方 fork
#
# 为什么不用上游 meta-rockchip 的 SRC_URI（JeffyCN/mirrors, kernel-6.1-2024_04_14）：
#   1) 那棵树里没有 arch/arm64/configs/lubancat_linux_rk3588_defconfig
#   2) 没有 LubanCat 对 rk3588s.dtsi / rk3588-linux.dtsi 的改动
#   3) 没有 rk3588s-lubancat-4-v1.dts
# 换源是硬需求，不是「优化」。

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# 用 = 整份替换，不要用 += 或者 :append —— 否则 require linux-yocto.inc 带进来的
# 上游 git:// 源会一起拉，SRCREV 还会出现 SRCREV_<name> 未定义。
SRC_URI = "git://github.com/LubanCat/kernel.git;protocol=https;branch=lbc-develop-6.1"

# 钉到具体 commit。取法（不写死旧值，构建前现场取）：
#   git ls-remote https://github.com/LubanCat/kernel.git refs/heads/lbc-develop-6.1
# 下面这个值是 2026-11-02 当天 HEAD，仅供对照。
SRCREV = "a0c672347152a0ea0713a043f1d1c4ec4323ff93"

LINUX_VERSION = "6.1.99"
LINUX_VERSION_EXTENSION = "-lubancat"

# LubanCat fork 没有 yocto 的 meta 分支（没有 .scc），kernel-yocto 的
# do_kernel_metadata 会去 meta 分支找特性描述而失败。必须 forcevariable，
# 普通 = 赋值会被 kernel-yocto 的 += 追回来。
KERNEL_FEATURES:forcevariable = ""

# .cfg 放进 SRC_URI 就会被 kernel-yocto 自动合并，不需要 KERNEL_CONFIG_FRAGMENTS。
# 六族共用一份（见文件头注释），里面只列 rockchip 公共符号。
SRC_URI += "file://lubancat-family.cfg"

# ---- HDMI：板级 dts 少了一行 include ----
# LubanCat-4 V1 的 dts 没引用厂商自带的 rk3588s-lubancat-4-hdmi0-vp0.dtsi，
# 导致 &hdmi0 与 hdmi0_in_vp0..2 全部 disabled，VOP2 拿不到 crtc：
#   rockchip-vop2 fdd90000.vop: [drm:vop2_bind] *ERROR* No crtc register
#   rockchip-drm display-subsystem: failed to bind fdd90000.vop: -19
# 表现就是 HDMI 不亮、/sys/class/drm 里只有 rknpu 的 card0。
SRC_URI += "file://0001-arm64-dts-lubancat-4-v1-enable-hdmi0-vp0.patch"

# ---- vendor wifi 驱动：out-of-tree 构建下 $(src) 失效 ----
# 这批驱动只在 S == B 的 in-tree 构建里验证过。Yocto 用 O=${B} 之后 $(src) 是
# 相对源码树的路径、编译器 cwd 却是 build 树，于是踩两个坑：
#
#  1) -I$(src)/... 指向不存在的目录，第一个头文件就失败：
#       rtl8821cu/core/rtw_cmd.c:17:10: fatal error: drv_types.h: No such file
#  2) rtl8851be/rtl8852be 用 DRV_PATH=$(src) 去做
#       include $(wildcard $(DRV_PATH)/platform/*.mk)
#     通配为空 → platform/arm_rk.mk 根本没被读进来 → 少了
#     -DCONFIG_IOCTL_CFG80211 -DRTW_USE_CFG80211_STA_EVENT → 代码退回 6.1 已经
#     删掉的 cfg80211_send_rx_assoc()/cfg80211_send_disassoc()，还按老结构体
#     访问 _ADAPTER_LINK.mlmeext，报出一串与 include 无关的错误：
#       rtw_swcrypto.c:16:10: fatal error: aes.h: No such file or directory
#       error: 'struct _ADAPTER_LINK' has no member named 'mlmeext'
#
# 补丁把 $(src) 解析成绝对路径（LUBANCAT_WIFI_SRC）供 -I 与 DRV_PATH 使用；
# `make M=...` 的外部模块构建里 $(src) 本来就是绝对路径，表达式照样成立。
# 相对路径的 `include $(src)/foo.mk` 不用改——kbuild 有 --include-dir=$(abs_srctree)。
SRC_URI += "file://0002-wifi-out-of-tree-paths.patch"

# ---- 无线网卡模块开机自动加载 ----
# KERNEL_MODULE_AUTOLOAD 是**内核 recipe** 的变量，由 kernel-module-split 消费：
# 它会在对应的 kernel-module-<mod> 包里生成 <modules-load.d>/<mod>.conf，
# 所以只有该模块包被装进 rootfs 才生效（见 packagegroup-lubancat-net）。
#
# 名字必须是 .ko 的 basename，不是驱动目录名：
#   8188CE → rtl8188ee    8822CE → rtw88_8822ce
#   8851BE → rtw89_8851be  8852BE → rtw89_8852be
#
# PCIe 网卡靠 udev 的 modalias 本来也能自动加载，显式写出来是为了开机顺序确定、
# journalctl 里能直接看出是谁加载的。插着哪张卡就只 bind 哪张，其余模块加载后
# 找不到设备会自己退出，不会报错。
KERNEL_MODULE_AUTOLOAD += "rtl8188ee rtw88_8822ce rtw89_8851be rtw89_8852be"

# ---- Rockchip BSP 的 out-of-tree 构建坑：mali_csffw.bin ----
# drivers/gpu/arm/bifrost/csf/mali_kbase_csf_firmware.c 里是
#     asm(".incbin \"drivers/gpu/arm/bifrost/mali_csffw.bin\"");
# 这是相对**汇编器当前工作目录**的路径。Yocto 用 O=${B} 做 out-of-tree 构建，
# 汇编时 cwd 是 kernel-build-artifacts（B），而该 bin 只在 kernel-source（S）里，
# 于是报：Error: file not found: drivers/gpu/arm/bifrost/mali_csffw.bin
# 修法：编译前把它复制到 ${B} 的同名相对路径下（不改内核源码，不关 GPU 驱动）。
#
# 用独立任务而不是 do_compile:prepend()，避免和 class 里的同名 prepend 互相覆盖。
do_lubancat_mali_fw() {
    fw="${S}/drivers/gpu/arm/bifrost/mali_csffw.bin"
    if [ -f "$fw" ]; then
        install -d "${B}/drivers/gpu/arm/bifrost"
        install -m 0644 "$fw" "${B}/drivers/gpu/arm/bifrost/"
        bbnote "mali_csffw.bin -> ${B}/drivers/gpu/arm/bifrost/"
    else
        bbwarn "mali_csffw.bin 不在 ${S}，跳过"
    fi
}
addtask lubancat_mali_fw after do_configure before do_compile

# =====================================================================
# extboot：dtbo 与全族 dtb 的构建 / 部署
# =====================================================================
# 为什么 do_compile 不带它们：do_compile 走 arch/arm64/Makefile 的 %.img 规则
#     $(MAKE) rockchip/$*.dtb Image.lz4 modules
#     $(srctree)/scripts/mkimg --dtb $*.dtb
# 只点名单个 dtb，**从不进入 dts/rockchip/overlay/**，所以编译完是 0 个 dtbo。
# 而 overlay 的编译链本身是齐的：
#     dts/rockchip/Makefile:48   subdir-y := $(dts-dirs) overlay
#     dts/rockchip/overlay/Makefile   dtbo-$(CONFIG_CPU_RK35xx) += ...（524 个源）
#     scripts/Makefile.lib:424   $(obj)/%.dtbo: $(src)/%.dts
# 所以只要补一次 `make dtbs` 就行，不必手写 cpp+dtc。
do_lubancat_dtbs() {
    sym="CONFIG_CPU_${LUBANCAT_CPU_SYMBOL}"
    if ! grep -q "^${sym}=y" "${B}/.config"; then
        bbfatal "${sym} 未开，overlay 编不出 dtbo（dtb 也可能缺失）"
    fi

    # 必须显式 -C ${S} O=${B}：bitbake 任务默认 cwd 是 ${WORKDIR}，
    # 而 kernel-yocto 的 do_compile 自己会 `cd ${B}`。少了 -C 会报
    #   make: *** No rule to make target 'dtbs'.  Stop.
    oe_runmake -C ${S} O=${B} dtbs

    n_dtbo=$(ls ${B}/arch/arm64/boot/dts/rockchip/overlay/*.dtbo 2>/dev/null | wc -l)
    n_dtb=$(ls ${B}/arch/arm64/boot/dts/rockchip/*.dtb 2>/dev/null | wc -l)
    [ "${n_dtbo}" -gt 0 ] || bbfatal "0 个 dtbo：dtfile 将无事可做，检查 ${sym} 与 overlay/Makefile 门控"
    bbnote "dtbs: ${n_dtb} dtb, ${n_dtbo} dtbo (${sym})"
}
addtask lubancat_dtbs after do_compile before do_deploy

# 部署到独立子目录：kernel.bbclass 的 do_deploy 已经会装 KERNEL_DEVICETREE 那一个
# （同名 + 版本化软链），全部装到 dtb/ 子目录可避免互相覆盖，也让 extboot-image
# 有一个稳定的取数路径：${DEPLOY_DIR_IMAGE}/dtb/{*.dtb,overlay/*.dtbo}
do_deploy:append() {
    install -d ${DEPLOYDIR}/dtb/overlay
    if ls ${B}/arch/arm64/boot/dts/rockchip/*.dtb >/dev/null 2>&1; then
        install -m 0644 ${B}/arch/arm64/boot/dts/rockchip/*.dtb ${DEPLOYDIR}/dtb/
    fi
    if ls ${B}/arch/arm64/boot/dts/rockchip/overlay/*.dtbo >/dev/null 2>&1; then
        install -m 0644 ${B}/arch/arm64/boot/dts/rockchip/overlay/*.dtbo ${DEPLOYDIR}/dtb/overlay/
    fi
}
