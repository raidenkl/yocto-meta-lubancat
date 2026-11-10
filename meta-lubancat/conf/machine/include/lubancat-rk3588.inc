# LubanCat RK3588 / RK3588S 系列公共配置
#
# 这一层只放「LubanCat 品牌 + RK3588 家族」的交集：串口、镜像格式、WKS、
# kernel/bootloader provider、rkbin 约束。凡是板型相关的（KERNEL_DEVICETREE、
# UBOOT_MACHINE、MACHINE_FEATURES）一律下沉到 conf/machine/<board>.conf。
#
# 依据：meta-rockchip scarthgap 的 conf/machine/include/rk3588.inc 已经提供了
#   - cortexa76/cortexa55 tune
#   - rockchip-common.inc（SERIAL_CONSOLES ?= "1500000;ttyFIQ0"、KERNEL_IMAGETYPE ?= "Image"、
#     PREFERRED_PROVIDER_virtual/{kernel,bootloader}、PREFERRED_VERSION_linux-rockchip ?= "6.1%"）
#   - mali.inc（MALI_GPU = "valhall-g610"）
# 所以这里不复制，只覆盖 / 追加。

require conf/machine/include/rk3588.inc

# 不要动 SOC_FAMILY（meta-rockchip 用它做 :rk3588 override），
# 用 MACHINEOVERRIDES 追加自己的层级，需要时写 VAR:lubancat-rk3588s 即可。
MACHINEOVERRIDES =. "lubancat:lubancat-rk3588:lubancat-rk3588s:"

# ---- 启动链 provider（弱赋值，板级 conf 可覆盖）----
PREFERRED_PROVIDER_virtual/kernel ?= "linux-rockchip"
PREFERRED_VERSION_linux-rockchip ?= "6.1%"
PREFERRED_PROVIDER_virtual/bootloader ?= "u-boot-rockchip"

# 必须覆盖 rk3588.inc 里的 KBUILD_DEFCONFIG="rk3588_linux_defconfig"：
# 那份通用 defconfig 不带 fiq-debugger console，结果是"根挂上了、串口一片空白"。
# 用 LubanCat 内核树里的 lubancat_linux_rk3588_defconfig。
KBUILD_DEFCONFIG = "lubancat_linux_rk3588_defconfig"

# ---- 串口：LubanCat 全系 RK3588 板卡是 UART2 @1500000，内核里由 fiq-debugger
#      接管为 ttyFIQ0（不是 ttyS2）。上游默认值恰好正确，这里显式写死当契约，
#      防止上游改默认值后静默漂移。
SERIAL_CONSOLES = "1500000;ttyFIQ0"
SERIAL_CONSOLES_CHECK = "${SERIAL_CONSOLES}"

# ---- 镜像 ----
KERNEL_IMAGETYPE = "Image"
WKS_FILE ?= "lubancat-gptdisk.wks.in"
IMAGE_FSTYPES ?= "wic.gz ext4 tar"

# ---- rkbin 约束（真正生效靠 u-boot recipe 的 SRCREV_rkbin，这里是断言依据）----
LUBANCAT_RKBIN_INI ?= "RK3588MINIALL.ini"
# LubanCat/rkbin master 的 RK3588MINIALL.ini 默认指向 v1.19 的最高档
# （lp4 2112MHz / lp5 2400MHz）。LubanCat 全系 RK3588/3588S 板卡的 LPDDR4X
# 定型频点是 **1848MHz**，所以这里锁到 1848 档（lp4 1848 / lp5 2112）：
# u-boot recipe 在 do_compile:prepend 里把 ini 的 Path1 与 FlashData 两处
# 一起改写，改写后再断言 bin 文件确实存在。
# 若换了 rkbin 版本，这个变量要同步改，否则编译期断言会直接报错。
LUBANCAT_DDR_BIN ?= "rk3588_ddr_lp4_1848MHz_lp5_2112MHz_v1.19.bin"

MACHINE_EXTRA_RRECOMMENDS += "kernel-modules"

# =====================================================================
# extboot / dtbo / uEnv 机制所需的族级变量（6 族同名同义，勿改名）
# =====================================================================
# 族标识，也用于 MACHINEOVERRIDES 与产物命名
LUBANCAT_FAMILY ?= "rk3588"
# 内核 CONFIG_CPU_<x> 符号后缀。注意：**没有 CONFIG_CPU_RK3566**，
# rk3566 与 rk3568 共用 CONFIG_CPU_RK3568（dtb 与 overlay 都挂在它下面）。
LUBANCAT_CPU_SYMBOL ?= "RK3588"
# 拷成 boot 分区 /rk-kernel.dtb 的那一份（U-Boot 早期 DTB 与内核 DTB 同源）
LUBANCAT_DTB ?= "rk3588s-lubancat-4-v1.dtb"
# uEnv 模板：直接取内核树的 arch/arm64/boot/dts/rockchip/uEnv/<dir>/<file>，
# 不在层里复制。内核升级时厂商模板自动跟着走。
LUBANCAT_UENV_DIR ?= "rk3588"
LUBANCAT_UENV ?= "uEnvLubanCat4-V1.txt"
# uEnv 的 cmdline 会**覆盖** dts 里的 /chosen bootargs。厂商模板只写
# `console=ttyFIQ0`（无波特率）——照抄会掉到默认波特率，串口全黑但系统能起。
# 必须显式 1500000n8。
LUBANCAT_CMDLINE ?= "earlyprintk console=ttyFIQ0,1500000n8 console=tty1 consoleblank=0 loglevel=7 rootwait rw rootfstype=ext4"
# U-Boot 追加片段（源码树 configs/<name>）。rk3566 用 rk3566.config，其余留空。
LUBANCAT_UBOOT_FRAGMENT ?= ""
# 传给 make.sh 的板名（默认 = RK_SOC_FAMILY，即 PLAT 目录名）
LUBANCAT_UBOOT_CFG ?= "${RK_SOC_FAMILY}"
