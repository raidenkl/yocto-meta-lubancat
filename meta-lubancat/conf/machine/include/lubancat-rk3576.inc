# LubanCat RK3576 系列公共配置（LubanCat-3 / 3-V2 / 3IO）
#
# 与 lubancat-rk3588.inc 同构：族内所有板共享，板级 conf 只覆盖 LUBANCAT_DTB / LUBANCAT_UENV。
# 依据 meta-rockchip conf/machine/include/rk3576.inc（tune + rockchip-common + mali）。
# 注意：rk3576.inc **没有**设 KBUILD_DEFCONFIG，落到 rockchip-common 的
# "rockchip_linux_defconfig"——那份不带 fiq console，必须在这里覆盖。

require conf/machine/include/rk3576.inc

MACHINEOVERRIDES =. "lubancat:lubancat-rk3576:"

PREFERRED_PROVIDER_virtual/kernel ?= "linux-rockchip"
PREFERRED_VERSION_linux-rockchip ?= "6.1%"
PREFERRED_PROVIDER_virtual/bootloader ?= "u-boot-rockchip"

KBUILD_DEFCONFIG = "lubancat_linux_rk3576_defconfig"

SERIAL_CONSOLES = "1500000;ttyFIQ0"
SERIAL_CONSOLES_CHECK = "${SERIAL_CONSOLES}"

KERNEL_IMAGETYPE = "Image"
WKS_FILE ?= "lubancat-gptdisk.wks.in"
IMAGE_FSTYPES ?= "wic.gz ext4 tar"

LUBANCAT_RKBIN_INI ?= "RK3576MINIALL.ini"
LUBANCAT_DDR_BIN ?= "rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.09.bin"

MACHINE_EXTRA_RRECOMMENDS += "kernel-modules"

# ---- extboot / dtbo / uEnv 族级变量 ----
LUBANCAT_FAMILY ?= "rk3576"
LUBANCAT_CPU_SYMBOL ?= "RK3576"
LUBANCAT_DTB ?= "rk3576-lubancat-3.dtb"
LUBANCAT_UENV_DIR ?= "rk3576"
LUBANCAT_UENV ?= "uEnvLubanCat3.txt"
LUBANCAT_CMDLINE ?= "earlyprintk console=ttyFIQ0,1500000n8 console=tty1 consoleblank=0 loglevel=7 rootwait rw rootfstype=ext4"
LUBANCAT_UBOOT_FRAGMENT ?= ""
LUBANCAT_UBOOT_CFG ?= "${RK_SOC_FAMILY}"
