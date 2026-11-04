# 变更记录

版本号规则：`MAJOR.MINOR.PATCH`

- **MAJOR**：层的外部契约变化（`LUBANCAT_*` 变量改名、MACHINE 重命名、分区布局变更）
- **MINOR**：新增 MACHINE / 镜像 / 脚本能力
- **PATCH**：修复、文档、不影响契约的调整

`LAYERVERSION_lubancat`（`meta-lubancat/conf/layer.conf`）与 tag 的 `MAJOR.MINOR` 保持一致。

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
