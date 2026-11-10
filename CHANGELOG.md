# 变更记录

版本号规则：`MAJOR.MINOR.PATCH`

- **MAJOR**：层的外部契约变化（`LUBANCAT_*` 变量改名、MACHINE 重命名、分区布局变更）
- **MINOR**：新增 MACHINE / 镜像 / 脚本能力
- **PATCH**：修复、文档、不影响契约的调整

`LAYERVERSION_lubancat`（`meta-lubancat/conf/layer.conf`）与 tag 的 `MAJOR.MINOR` 保持一致。

---

## v0.1.3

### 修复

- **RK3588/3588S 的 DDR bin 锁到 1848 档**。`LubanCat/rkbin` 的 `RK3588MINIALL.ini`
  默认指向最高档（`lp4 2112MHz / lp5 2400MHz`），而 LubanCat 全系 RK3588 板卡的 LPDDR4X
  定型频点是 1848MHz。`lubancat-rk3588.inc` 的 `LUBANCAT_DDR_BIN` 改为
  `rk3588_ddr_lp4_1848MHz_lp5_2112MHz_v1.19.bin`
- `u-boot-rockchip.bbappend` 增加 ini 改写：`do_compile:prepend` 里把 `RK*MINIALL.ini`
  的 `Path1` 与 `FlashData`（后者才是真正打包进 loader 的那份）一起改写成
  `LUBANCAT_DDR_BIN`，再断言该 bin 在 rkbin 里存在。此前这里只做断言，改档位会直接
  `bbfatal`（`Path1` 与 `FlashData` 只改一处则会出现「ini 看着对、loader 里还是旧 bin」）
- `do_compile[vardeps] += "LUBANCAT_DDR_BIN LUBANCAT_RKBIN_INI"`：两个变量只在 shell 里
  内联引用，bitbake 收集不到依赖，不加会出现「改了档位但 sstate 命中、uboot.img 没变」

### 文档

- `docs/VERSION-MATRIX.md` 第 4 节增加「DDR 频点 / DDR bin」两列，补齐六族档位；
  验证级别按本轮上板结果更新（RK3576 / RK3568 / RK3566 由「编译解析级」改为「真机上板」）
- `docs/manual.md` §1.1 / §6.3 / §6.5 / §8.7 / 附录 A 同步为 1848 档，§8.7 说明
  `Path1` 与 `FlashData` 必须一起改的原因，并注明 1848 档的验证边界（只到编译期 +
  idblock 时间戳比对，未在 RK3588 板上实测串口频点）
- `docs/manual.md` 按仓库当前状态整体重写（保持 0~14 章 + 附录 A/B/C 骨架）：
  - 验收口径由 L0 / L1 / L2 改为按镜像分级（minimal / net / full），并补各族上板状态表
  - §6.1 文件树按实际目录重写，补 `meta-realtime/`、`extboot-image.bb`、
    `lubancat-firstboot/`、`netconfig/`、`tools/rkpack/`；§6.5 改为七行 MACHINE 表
  - 新增 §7.8「PREEMPT_RT 内核（`meta-realtime`）」；§7.6 三条路线改标 A/B/C 并
    补设备树 overlay 的 config 前提
  - §9 补 `packagegroup-lubancat-base` 内容表；§10 重组为「分区、打包与烧录」，
    §10.5 补 `update.img` 脚本的四件事
  - §12.0 速查表补 `weston.service` 启动失败、`uname -r` 无 `-rt36` 两条；
    §12.20 标注为历史实测，不作为镜像功能承诺
  - 删除已不存在的 `lubancat-rk356x.inc`、`recipes-kernel/dto`、旧 SDK 打包目录流程
- `README.md` §5.2 去掉「手册把这三份称作 L0 / L1 / L2」的表述，改为与 §1.2 的
  镜像分级验收一一对应

### 验证

- RK3576 / RK3568 / RK3566 三族 full 镜像均上板通过：GPU（kmscube / weston-egl）、
  NPU（`/sys/kernel/debug/rknpu/`）、网络正常
- RK3588 的 1848 档：`bitbake -c compile -f -v u-boot-rockchip` 日志可见 ini 两处改写，
  `strings idblock.img` 的 DDR 固件时间戳为 `25/04/21-14:31`，与 1848 档 bin 一致
  （2112 档那份是 `25/03/13-15:39`）

---

## v0.1.2

### 新增 meta-realtime 层（PREEMPT_RT）

- 新层 `meta-realtime`（`BBFILE_PRIORITY = 15`，`LAYERDEPENDS = "core lubancat"`），
  把 `virtual/kernel` 切到 `lbc-develop-6.1-rt36`（Linux 6.1.99 + rt36）
- 触发方式：`KAS_BUILD_DIR=$PWD/build-rt kas build kas/lubancat.yml:kas/realtime.yml`。
  不叠加 overlay 时该层完全不参与构建
- 支持 RK3588/3588S、RK3576、RK3566/3568、RK3562（这四族 RT defconfig 自带
  `CONFIG_PREEMPT_RT=y`）；RK3528 的 defconfig 没有该选项，层里用 `bb.fatal` 拦住，
  否则会编出一颗「看起来成功」的非 RT 内核

### 内核

- `linux-rockchip_6.1.bbappend` 把源参数化：新增弱赋值
  `LUBANCAT_KERNEL_BRANCH` / `LUBANCAT_KERNEL_SRCREV`，`SRC_URI` 与 `SRCREV` 改为引用它们。
  默认值与改造前逐字节一致，非 RT 构建行为不变；RT 层只覆盖这两个变量，不重写 `SRC_URI`
  （重写会把 `family.cfg` 与 HDMI 补丁一起丢掉）
- RT 层从 `SRC_URI` 摘除 `0002-wifi-out-of-tree-paths.patch`：该补丁涉及 11 个文件，
  其中 `rtl8821cu` 的 3 个 `.mk` 在 RT 分支被改写成 `ccflags-y` 风格，上下文不匹配，
  不摘除 `do_patch` 必失败
- RT 配置片段 `lubancat-realtime.cfg`：
  - `CONFIG_PREEMPT_RT=y`（choice 三选一；依赖的 `EXPERT` 由 defconfig 的 `EMBEDDED=y` 间接 select）
  - `CONFIG_HZ_PERIODIC=n` + `CONFIG_NO_HZ_IDLE=y`：RT 分支 defconfig 里 `HZ_PERIODIC=y`
    与 `NO_HZ=y` 并存，实际把 tickless 关掉了。两行都写，避免 `olddefconfig` 保留先出现的那一项
  - 关 `PROVE_LOCKING` / `DEBUG_PREEMPT` / `DEBUG_ATOMIC_SLEEP` / `LOCK_STAT` 等延迟杀手，
    显式开 `RCU_BOOST` / `RCU_NOCB_CPU`
  - `CONFIG_WERROR=n`：`family.cfg` 末尾那句 `# CONFIG_WERROR is not set` 是死代码
    （merge_config 当注释删掉），非 RT 构建里 WERROR 一直是 y
  - vendor 无线全关（`RTL8189FS` / `RTL8821CU` / `RTL8851BE` / `RTL8852BE` / AIC8800 六项）。
    AIC8800 是关键：RT defconfig 里是 `=m`，而 0002 改过它的 Makefile，不关必失败
  - 主线 rtw88/rtw89 保留（RTL8188CE / RTL8822CE / RTL8851BE / RTL8852BE），
    `WL_ROCKCHIP=y` 必须留着，否则 rtw89 会被 olddefconfig 静默清空

### 构建

- `kas/realtime.yml`：overlay 追加 `meta-realtime` 层，`DL_DIR` / `SSTATE_DIR` 指回主构建
  （共用下载与 sstate），`TMPDIR` 由 `KAS_BUILD_DIR` 隔离
- `.gitignore` 加 `/build-rt/`
- RT 与非 RT 的 deploy 产物同名（`Image`、`boot-ext2.img`、`dtb/`），必须用独立
  `KAS_BUILD_DIR`，否则会出现「烧了 RT 固件但 `uname -r` 没有 `-rt36`」
- 打包需带 `DEPLOY=` 与 `WORK=` 指到 `build-rt`：只改 `DEPLOY` 会让脚本 `rm -rf` 掉
  非 RT 的打包中间目录

### 文档

- 新增 `docs/realtime.md`：范围与前置、设计取舍（为什么参数化 bbappend、层优先级为什么是 15）、
  构建与目录隔离、逐项配置解读、产物与打包、构建期与上板验收、延迟实测
  （SDK 交叉编译 rt-tests / ftrace `wakeup_rt`）、与非 RT 的差异对照、10 条风险、回退与清理
- 说明为什么镜像里没有 cyclictest：meta-openembedded scarthgap 全树没有 `rt-tests`

### 实测（2026-11-05，`lubancat-4-v1`，`lubancat-image-net`）

- `bitbake -c kernel_configme` + 完整构建 5435 个 task 全部通过（唯一 WARNING 是
  `extboot-image` 用了主机 `mkimage`，既有问题）
- `kernel.release` = `6.1.99-rt36-lubancat`；boot 分区 `Image` 的 banner 为
  `#1 SMP PREEMPT_RT`；`rtw89_8852be.ko` 的 vermagic 为
  `6.1.99-rt36-lubancat SMP preempt_rt`
- `.config` 核对通过：`PREEMPT_RT=y` / `NO_HZ_IDLE=y`（`HZ_PERIODIC` 已清）/ `HZ_1000`
  / `RT_GROUP_SCHED` 关 / `RCU_BOOST=y` / `WERROR` 关 / vendor 无线全关 / 主线 rtw88 与 rtw89 全 `=m`
- **修正原先的预判**：版本串不是 `6.1.99-rk3588-rt36`。`localversion-rt` 的 `-rt36` 在前，
  `CONFIG_LOCALVERSION` 在后，而后者被 poky 的 `kernel-yocto` 用 `LINUX_VERSION_EXTENSION`
  覆写成 `-lubancat`（defconfig 的 `-rk3588` 被盖掉）。非 RT 同理是 `6.1.99-lubancat`

---

## v0.1.1

### 内核

- 无线网卡按总线分成两条路线（详见手册 7.7）：
  - SDIO / USB 模组继续走 vendor 树：`RTL8189FS` / `RTL8821CU` `=m`，四个驱动全量编译通过
    （395 / 408 / 184 / 132 个目标文件）
  - PCIe（M.2）模组改走内核主线：`RTL8188EE`（RTL8188CE）、`RTW88_8822CE`（RTL8822CE）、
    `RTW89_8851BE` / `RTW89_8852BE`（RTL8851BE / RTL8852BE）全部 `=m`
  - vendor 树的 `RTL8851BE` / `RTL8852BE` 默认关闭：它们是 PCIe 版，和主线 `rtw89` 声明同一个
    PCI ID，只能二选一；且固件是 Android 风格路径，linux-firmware 里没有
- `KERNEL_MODULE_AUTOLOAD` 显式列出四颗芯片的模块名（`.ko` basename，不是目录名）
- 新增 `0002-wifi-out-of-tree-paths.patch`，一次性解决 `O=${B}` 构建下两类路径失效：
  `-I$(src)/...` 指向不存在的目录；`DRV_PATH=$(src)` 让
  `include $(wildcard $(DRV_PATH)/platform/*.mk)` 匹配为空，进而丢掉
  `-DCONFIG_IOCTL_CFG80211` / `-DRTW_USE_CFG80211_STA_EVENT`，回退到 6.1 已删除的
  `cfg80211_send_rx_assoc()` 系列 API

### 镜像

- `packagegroup-lubancat-net` 追加 6 个模块 `RRECOMMENDS`（`rtl8188ee` / `rtw88_8822ce` /
  `rtw89_8851be` / `rtw89_8852be` / `8189fs` / `8821cu`）和 3 个固件 `RDEPENDS`
  （`linux-firmware-rtl8188` / `-rtl8822` / `-rtw89`）
- 修正模块包名：`kernel-module-split` 会把 `.ko` 名里的 `_` 换成 `-`，包组里写成
  `kernel-module-rtw88_8822ce` 会导致 `do_rootfs` 报
  `nothing provides kernel-module-rtw88_8822ce`（模块其实是编好的，只是名字对不上）。
  现改为 `kernel-module-rtw88-8822ce` / `rtw89-8851be` / `rtw89-8852be`
- 新增 `linux-firmware_%.bbappend`：poky 的 linux-firmware 没有 `rtw89` 子包，
  不切出来就会连整棵固件树一起装进 rootfs
- `packagegroup-lubancat-net` 补无线工具链：`pciutils`（lspci）、`iw`、
  `wpa-supplicant`、`wireless-regdb-static`（监管域；主包只放 crda 的旧格式，必须用 `-static`）
- `lubancat-netconfig` 扩展到无线（原 `lubancat-netnaming` 并入，避免同名配方冲突）：
  - `10-lubancat-wlan.link`：用 `[Match] Type=wlan` 把无线网口钉回 `wlan0`，避免 udev 改名成
    `wlP4p65s0` 这类可预测名字（有线 `end0` / `end1` 不受影响）
  - `50-lubancat-wlan.network`：无线改由 systemd-networkd 做 DHCP，`[DHCPv4] RouteMetric=100`。
    修掉"wifi 已连接却上不了网"——busybox `udhcpc` 的 `/etc/udhcpc.d/50default` 把 metric 写死 10，
    与有线 `80-wired.network` 的 `RouteMetric=10` 撞车，`ip route add default ... metric 10` 返回
    `RTNETLINK answers: File exists` 且被 udhcpc 吞掉，结果是 wlan0 有地址却没有默认路由
  - `20-wired.network` 显式补 `RouteMetric=10`（原本用 networkd 默认的 100，会与无线再撞一次）
  - 启用 `wpa_supplicant@wlan0.service`，凭据文件 `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`
    （0600、CONFFILES，升级不覆盖）
- 板上实测：有线 metric 10 + 无线 metric 100 两条默认路由共存，`curl --interface wlan0`
  访问外网返回 200，`resolvectl status wlan0` 拿到 DHCP 下发的 DNS 223.5.5.5 / 119.29.29.29

### 构建

- `local.conf.sample` 新增 kernel.org 固件包镜像规则：`KERNELORG_FW_SRC` /
  `KERNELORG_FW_MIRROR` + `PREMIRRORS:prepend`，只重写 `/firmware/` 这一段。
  实测 `cdn.kernel.org` 0.04 MB/s、阿里云 15 MB/s（curl）/ 0.86 MB/s（bitbake wget），
  365 MB 的 `linux-firmware` 从 2.5 小时降到 25 秒~5 分钟

### 文档

- 手册 12.17 重写为"已修复"，补上三站症状与判别方法（`--include-dir` 兜得住 include、
  兜不住 `-I` 与 `wildcard`）；FAQ 第 12 条同步
- 手册新增 3.5.1：kernel.org 固件包的镜像加速、镜像站目录层级差异（写错静默回落原地址）、
  以及"改 `local.conf` 对正在跑的构建无效"这条坑
- 手册新增 7.7.3：模块包名规则（`_` → `-`）与两套名字的区分（包依赖用短横线、
  `KERNEL_MODULE_AUTOLOAD` / `modprobe` 用下划线）
- 手册新增 7.7.5：没有 `lspci` 时用 sysfs 确认 PCI 设备与驱动绑定；节点名
  `wlP4p65s0` 的来历，以及 `.link` 三种 `[Match]` 写法的实测对比（`OriginalName`
  在设备已被改名后失效，`Type=wlan` 才通用）
- 修掉 12.1 节里一段残留的空表格标记

---

## v0.1.0

首个可用版本。Yocto 系列：**scarthgap (5.0)**。

### 机器与镜像

- 6 个族级 MACHINE：`lubancat-rk3588` / `rk3576` / `rk3568` / `rk3566` / `rk3562` / `rk3528`，
  以及板级别名 `lubancat-4-v1`
- 三档镜像：`lubancat-image-minimal`（串口可登录）/ `-net`（有线网络可用）/ `-full`（weston + libmali + kmscube）
- 内核 6.1（`LubanCat/kernel:lbc-develop-6.1`）、U-Boot 2017.09（`LubanCat/u-boot:main`）、
  rkbin（`LubanCat/rkbin:master`），全部以 `SRCREV` 钉死

### extboot 机制

- `recipes-bsp/extboot/extboot-image.bb` 生成 128 MiB ext2 的 `boot-ext2.img`
  （`boot.scr` / `Image` / `rk-kernel.dtb` / 全族 `dtb/` / `dtb/overlay/` / `uEnv/`）
- 内核侧新增 `do_lubancat_dtbs`（`make dtbs` 产 dtbo）与 `do_deploy:append`（把 dtb/dtbo 装到 `deploy/dtb/`）
- U-Boot 侧按族追加 cfg 片段，rk3566 走 `rk3568_defconfig` + `configs/rk3566.config`

### 首次启动

- `lubancat-firstboot`：`resize2fs` 自动扩容（幂等，带完成标记）
- `lubancat-board-detect`：读 SARADC 板卡 ID，按 `board-table`（40 条）把 `rk-kernel.dtb` 与
  `uEnv/uEnv.txt` 换成对应板子的那份，重启一次生效；内容一致时只打标记不重启

### 打包

- `scripts/make-updateimg.sh`：rkfw `update.img`，芯片型号从 `loader.bin` 偏移 21 自动推断；
  `EXTBOOT=0` 保留旧 FIT 布局作逃生路径
- `tools/rkpack/`：随仓库分发 `afptool` + `rkImageMaker`，**不再需要安装 Rockchip SDK**
- `scripts/flash-emmc.sh`：`rkdeveloptool` 烧 wic 整盘

### 已知限制

- 仅 `lubancat-4-v1` 在真机上走完启动验收；其余 5 族只做到解析/构建级验证
- SG200x（全志核）不在范围内，需要另一套内核树与打包链
- `lubancat-5-rk3588-pcie_defconfig` 关闭了 `EARLY_DISTRO_DTB`，不能用于 extboot，族机器固定用 `rk3588_defconfig`
- 只提供 poky（systemd）rootfs；不支持主线内核、OTA、安全启动、双系统
