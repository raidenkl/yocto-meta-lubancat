# 变更记录

版本号规则：`MAJOR.MINOR.PATCH`

- **MAJOR**：层的外部契约变化（`LUBANCAT_*` 变量改名、MACHINE 重命名、分区布局变更）
- **MINOR**：新增 MACHINE / 镜像 / 脚本能力
- **PATCH**：修复、文档、不影响契约的调整

`LAYERVERSION_lubancat`（`meta-lubancat/conf/layer.conf`）与 tag 的 `MAJOR.MINOR` 保持一致。

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
