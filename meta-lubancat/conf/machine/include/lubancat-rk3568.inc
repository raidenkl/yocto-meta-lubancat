# LubanCat RK3568 系列公共配置（LubanCat-2 / 2-V1/V2/V3 / 2H / 2IO / 2N / 2N-V2/V3）
#
# rk3566 与 rk3568 共用 meta-rockchip 的 rk356x.inc（RK_SOC_FAMILY=rk3568），
# 但 DDR bin 不同，所以必须拆成两个 MACHINE。

require conf/machine/include/rk356x.inc

MACHINEOVERRIDES =. "lubancat:lubancat-rk3568:"

PREFERRED_PROVIDER_virtual/kernel ?= "linux-rockchip"
PREFERRED_VERSION_linux-rockchip ?= "6.1%"
PREFERRED_PROVIDER_virtual/bootloader ?= "u-boot-rockchip"

# rk356x.inc 同样没设 KBUILD_DEFCONFIG，必须覆盖。
KBUILD_DEFCONFIG = "lubancat_linux_rk356x_defconfig"

SERIAL_CONSOLES = "1500000;ttyFIQ0"
SERIAL_CONSOLES_CHECK = "${SERIAL_CONSOLES}"

KERNEL_IMAGETYPE = "Image"
WKS_FILE ?= "lubancat-gptdisk.wks.in"
IMAGE_FSTYPES ?= "wic.gz ext4 tar"

# **关键**：U-Boot 的 rk3568_defconfig 里 CONFIG_LOADER_INI="RK3566MINIALL.ini"
# （内含 rk3566 的 DDR bin，频率档位不同），rk3568 必须覆盖成 RK3568MINIALL.ini，
# 否则表现为「一行都不打印的假死」。覆盖点在本族的 rk3568-lubancat.cfg 里。
LUBANCAT_RKBIN_INI ?= "RK3568MINIALL.ini"
LUBANCAT_DDR_BIN ?= "rk3568_ddr_1560MHz_v1.23.bin"

MACHINE_EXTRA_RRECOMMENDS += "kernel-modules"

# ---- extboot / dtbo / uEnv 族级变量 ----
# 注意：**没有 CONFIG_CPU_RK3566**，rk3566/rk3568 的 dtb 与 overlay 都挂在
# CONFIG_CPU_RK3568 下，所以两族的 CPU_SYMBOL 相同。
LUBANCAT_FAMILY ?= "rk3568"
LUBANCAT_CPU_SYMBOL ?= "RK3568"
LUBANCAT_DTB ?= "rk3568-lubancat-2.dtb"
LUBANCAT_UENV_DIR ?= "rk356x"
LUBANCAT_UENV ?= "uEnvLubanCat2.txt"
LUBANCAT_CMDLINE ?= "earlyprintk console=ttyFIQ0,1500000n8 console=tty1 consoleblank=0 loglevel=7 rootwait rw rootfstype=ext4"
LUBANCAT_UBOOT_FRAGMENT ?= ""
LUBANCAT_UBOOT_CFG ?= "${RK_SOC_FAMILY}"
