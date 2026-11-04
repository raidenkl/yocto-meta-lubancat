# LubanCat RK3528 系列公共配置（LubanCat-Q1 / Q1IO）
#
# **meta-rockchip 没有 rk3528.inc**（scarthgap 只有 rk3506.inc / rk3562 / rk356x / rk3576 / rk3588），
# 所以这里自己拼 tune + rockchip-common + mali，RK_SOC_FAMILY 取 "rk3528"
# （U-Boot 源码里确实有 arch/arm/mach-rockchip/rk3528 与 configs/rk3528_defconfig）。
# RK3528 = 4×Cortex-A53 + Mali-G52，所以用 armv8a/tune-cortexa53。

require conf/machine/include/arm/armv8a/tune-cortexa53.inc
require conf/machine/include/rockchip-common.inc
require conf/machine/include/mali.inc

RK_SOC_FAMILY := "rk3528"
MALI_GPU := "bifrost-g52"
MALI_VERSION ?= "g13p0"

MACHINEOVERRIDES =. "lubancat:lubancat-rk3528:"

PREFERRED_PROVIDER_virtual/kernel ?= "linux-rockchip"
PREFERRED_VERSION_linux-rockchip ?= "6.1%"
PREFERRED_PROVIDER_virtual/bootloader ?= "u-boot-rockchip"

KBUILD_DEFCONFIG = "lubancat_linux_rk3528_defconfig"

SERIAL_CONSOLES = "1500000;ttyFIQ0"
SERIAL_CONSOLES_CHECK = "${SERIAL_CONSOLES}"

KERNEL_IMAGETYPE = "Image"
WKS_FILE ?= "lubancat-gptdisk.wks.in"
IMAGE_FSTYPES ?= "wic.gz ext4 tar"

LUBANCAT_RKBIN_INI ?= "RK3528MINIALL.ini"
LUBANCAT_DDR_BIN ?= "rk3528_ddr_1056MHz_v1.11.bin"

MACHINE_EXTRA_RRECOMMENDS += "kernel-modules"

# ---- extboot / dtbo / uEnv 族级变量 ----
LUBANCAT_FAMILY ?= "rk3528"
LUBANCAT_CPU_SYMBOL ?= "RK3528"
LUBANCAT_DTB ?= "rk3528-lubancat-q1.dtb"
LUBANCAT_UENV_DIR ?= "rk3528"
LUBANCAT_UENV ?= "uEnvLubanCatQ1.txt"
LUBANCAT_CMDLINE ?= "earlyprintk console=ttyFIQ0,1500000n8 console=tty1 consoleblank=0 loglevel=7 rootwait rw rootfstype=ext4"
LUBANCAT_UBOOT_FRAGMENT ?= ""
LUBANCAT_UBOOT_CFG ?= "${RK_SOC_FAMILY}"
