# LubanCat RK3562 系列公共配置（LubanCat-1HS / 1HS-test）
#
# rk3562.inc 没设 KBUILD_DEFCONFIG，落到 rockchip_linux_defconfig，必须覆盖。

require conf/machine/include/rk3562.inc

MACHINEOVERRIDES =. "lubancat:lubancat-rk3562:"

PREFERRED_PROVIDER_virtual/kernel ?= "linux-rockchip"
PREFERRED_VERSION_linux-rockchip ?= "6.1%"
PREFERRED_PROVIDER_virtual/bootloader ?= "u-boot-rockchip"

KBUILD_DEFCONFIG = "lubancat_linux_rk3562_defconfig"

SERIAL_CONSOLES = "1500000;ttyFIQ0"
SERIAL_CONSOLES_CHECK = "${SERIAL_CONSOLES}"

KERNEL_IMAGETYPE = "Image"
WKS_FILE ?= "lubancat-gptdisk.wks.in"
IMAGE_FSTYPES ?= "wic.gz ext4 tar"

LUBANCAT_RKBIN_INI ?= "RK3562MINIALL.ini"
LUBANCAT_DDR_BIN ?= "rk3562_ddr_1332MHz_v1.07.bin"

MACHINE_EXTRA_RRECOMMENDS += "kernel-modules"

# ---- extboot / dtbo / uEnv 族级变量 ----
LUBANCAT_FAMILY ?= "rk3562"
LUBANCAT_CPU_SYMBOL ?= "RK3562"
LUBANCAT_DTB ?= "rk3562-lubancat-1hs.dtb"
LUBANCAT_UENV_DIR ?= "rk3562"
LUBANCAT_UENV ?= "uEnvLubanCat1HS.txt"
LUBANCAT_CMDLINE ?= "earlyprintk console=ttyFIQ0,1500000n8 console=tty1 consoleblank=0 loglevel=7 rootwait rw rootfstype=ext4"
LUBANCAT_UBOOT_FRAGMENT ?= ""
LUBANCAT_UBOOT_CFG ?= "${RK_SOC_FAMILY}"
