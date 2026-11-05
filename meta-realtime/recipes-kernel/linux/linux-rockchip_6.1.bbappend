# =====================================================================
# meta-realtime：把 virtual/kernel 切到 LubanCat 的 PREEMPT_RT 分支
# =====================================================================
# 前提：meta-lubancat 已把内核源参数化为
#   LUBANCAT_KERNEL_BRANCH / LUBANCAT_KERNEL_SRCREV（弱赋值，默认值 = 非 RT 现状）。
# 本层**只覆盖这两个变量**，SRC_URI 其余部分仍由 meta-lubancat 组装。
#
# 为什么不整份重写 SRC_URI：
#   meta-lubancat 的 SRC_URI 里除了 git:// 还有三项
#     file://lubancat-family.cfg            FIQ console / 以太网 / 存储 / WL_ROCKCHIP
#     file://0001-...-enable-hdmi0-vp0.patch HDMI（缺了不亮）
#     file://0002-wifi-out-of-tree-paths.patch vendor wifi 路径（本层要摘掉）
#   重写会一起丢掉前两项，表现是"能起但没有串口、没有 HDMI"，很难往这上面想。

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# ---- 1) 换到 RT 分支 ----
# 用 = 不用 ?=：本层优先级 15 > 10，一定后写、一定生效；?= 反而要看解析顺序。
LUBANCAT_KERNEL_BRANCH = "lbc-develop-6.1-rt36"
# 取法：git ls-remote https://github.com/LubanCat/kernel.git refs/heads/lbc-develop-6.1-rt36
# 下面是 2026-11-05 现场 HEAD，升级时同步改 docs/VERSION-MATRIX.md。
# 该分支 Makefile 是 6.1.99，源码树带 localversion-rt = "-rt36"，
# 所以 uname -r 实测是 6.1.99-rt36-lubancat（不是 LINUX_VERSION 决定的，也不是
# 6.1.99-rk3588-rt36 —— poky 的 kernel-yocto 会用 LINUX_VERSION_EXTENSION 把
# CONFIG_LOCALVERSION 覆写成 "-lubancat"，defconfig 里的 "-rk3588" 被盖掉）。
LUBANCAT_KERNEL_SRCREV = "3d027a80ff4023e4ee6dba24db140a2eab2c1f28"

# ---- 2) 摘掉 vendor 无线路径补丁 ----
# 两个理由，任一都足以摘除：
#   a) 本层把 vendor 驱动全关（见 files/lubancat-realtime.cfg），补丁没有作用对象；
#   b) RT 分支把 rtl8821cu 的三个 .mk 改成了 ccflags-y 写法（非 RT 分支是 EXTRA_CFLAGS），
#      0002 的 hunk 上下文对不上，不摘除 do_patch 会直接 failed。
# :remove 在 finalize 阶段执行，与声明位置无关；该字符串在 SRC_URI 中唯一，不会误伤其它项。
SRC_URI:remove = "file://0002-wifi-out-of-tree-paths.patch"

# ---- 3) 追加 RT 配置片段 ----
# 必须排在 family.cfg 之后（靠层优先级保证）：merge_config.sh 里最后一份生效，
# 才能把 family.cfg 的 CONFIG_RTL8189FS=m / CONFIG_RTL8821CU=m 覆盖成 n。
# 可用 `bitbake -e virtual/kernel | grep ^SRC_URI` 核对最终顺序。
SRC_URI += "file://lubancat-realtime.cfg"

# ---- 4) 以下变量刻意不动，逐条写清避免"顺手改坏" ----
# KERNEL_FEATURES:forcevariable = ""
#   meta-lubancat 已设。forcevariable 是最高优先级覆盖，本层再写一遍无意义；
#   改成别的值会把 .scc 路线重新打开，而 LubanCat fork 没有 yocto 的 meta 分支，
#   do_kernel_metadata 会去那里找特性描述然后失败。
# LINUX_VERSION
#   RT 分支 Makefile 仍是 6.1.99，改了只会让 PV 与源码不符。
# LINUX_VERSION_EXTENSION
#   不进 uname -r（-rt36 来自源码树的 localversion-rt），但会进包版本；
#   改它等于让所有 kernel-* 包重打一遍，零收益。
# KERNEL_MODULE_AUTOLOAD
#   四条都是主线模块（rtl8188ee / rtw88_8822ce / rtw89_8851be / rtw89_8852be），
#   RT 下照样 =m；vendor 的 8189fs / 8821cu 本来就不在列表里。
#   kernel-module-split 只为"真的编出来的模块"生成 modules-load.d，不存在的不报错。
# KBUILD_DEFCONFIG
#   保持 machine include 的强赋值。RT 分支的 lubancat_linux_rk3588_defconfig
#   已经带 CONFIG_PREEMPT_RT=y，不需要换 defconfig（也换不动，那是 = 赋值）。

# ---- 5) 机器守卫 ----
# RT 分支各族的 defconfig 情况：
#   rk3588 / rk3576 / rk356x / rk3562  有 CONFIG_PREEMPT_RT=y
#   rk3528                             没有
# rk3528 编下去不会报错，只会编出一颗非 RT 内核 —— 这种"看起来成功了"最难查，
# 所以在解析阶段直接拦住。
python () {
    if "lubancat-rk3528" in (d.getVar("MACHINEOVERRIDES") or "").split(":"):
        bb.fatal("meta-realtime: rk3528 的 lubancat_linux_rk3528_defconfig 没有开 "
                 "CONFIG_PREEMPT_RT，这样编出来的是非 RT 内核。"
                 "请改用 lubancat-4-v1 / lubancat-rk3588 / lubancat-rk3576 / "
                 "lubancat-rk3568 / lubancat-rk3566 / lubancat-rk3562。")
}

# ---- 6) 首版核对 .config 时用 ----
# kas/lubancat.yml 里有 INHERIT += "rm_work"，构建结束 ${B} 就被删，事后看不到 .config。
# 要事后核对（或反复调 cfg 重编）时打开下面这行，代价是多占一份内核 work 目录（约 15 GB）。
# RM_WORK_EXCLUDE += "linux-rockchip"
