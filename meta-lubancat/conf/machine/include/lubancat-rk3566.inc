# LubanCat RK3566 系列公共配置（LubanCat-1 / 1H / 1IO / 1N / 0 / CM4）
#
# 与 rk3568 共用 meta-rockchip 的 rk356x.inc（RK_SOC_FAMILY=rk3568，因为
# arch/arm/mach-rockchip/ 下只有 rk3568 目录，PLAT 必须是它）。
#
# U-Boot 侧：该树**没有** rk3566_defconfig，官方做法是
#   configs/rk3568_defconfig + configs/rk3566.config
# 而 rk3566.config 只有两行：
#   CONFIG_BASE_DEFCONFIG="rk3568_defconfig"
#   CONFIG_LOADER_INI="RK3566MINIALL.ini"
# 我们沿用 bbappend 的 defconfig 追加机制把它并进去（LUBANCAT_UBOOT_FRAGMENT）。

require conf/machine/include/rk356x.inc

MACHINEOVERRIDES =. "lubancat:lubancat-rk3566:"

PREFERRED_PROVIDER_virtual/kernel ?= "linux-rockchip"
PREFERRED_VERSION_linux-rockchip ?= "6.1%"
PREFERRED_PROVIDER_virtual/bootloader ?= "u-boot-rockchip"

KBUILD_DEFCONFIG = "lubancat_linux_rk356x_defconfig"

SERIAL_CONSOLES = "1500000;ttyFIQ0"
SERIAL_CONSOLES_CHECK = "${SERIAL_CONSOLES}"

KERNEL_IMAGETYPE = "Image"
WKS_FILE ?= "lubancat-gptdisk.wks.in"
IMAGE_FSTYPES ?= "wic.gz ext4 tar"

# rk3566 没有独立的 spl/bl31/bl32：共用 rk356x_spl 与 rk3568_bl31/bl32。
# 且 RKTRUST/ 下**不存在** RK3566TRUST.ini，任何按名字拼 ini 的脚本都会取不到，
# 只能回退 RK3568TRUST.ini（make.sh 由 CONFIG_LOADER_INI 决定 loader ini，
# trust ini 由 RKCHIP_TRUST 推得，这里保持 ini 名与 rkbin 实际文件一致）。
LUBANCAT_RKBIN_INI ?= "RK3566MINIALL.ini"
LUBANCAT_DDR_BIN ?= "rk3566_ddr_1056MHz_v1.23.bin"

MACHINE_EXTRA_RRECOMMENDS += "kernel-modules"

# ---- extboot / dtbo / uEnv 族级变量 ----
LUBANCAT_FAMILY ?= "rk3566"
# 注意：树里没有 CONFIG_CPU_RK3566，rk3566/rk3568 的 dtb 与 overlay 都挂在 RK3568 下。
LUBANCAT_CPU_SYMBOL ?= "RK3568"
LUBANCAT_DTB ?= "rk3566-lubancat-1.dtb"
LUBANCAT_UENV_DIR ?= "rk356x"
LUBANCAT_UENV ?= "uEnvLubanCat1.txt"
LUBANCAT_CMDLINE ?= "earlyprintk console=ttyFIQ0,1500000n8 console=tty1 consoleblank=0 loglevel=7 rootwait rw rootfstype=ext4"
LUBANCAT_UBOOT_FRAGMENT ?= "rk3566.config"
LUBANCAT_UBOOT_CFG ?= "${RK_SOC_FAMILY}"
