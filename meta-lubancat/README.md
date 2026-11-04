# meta-lubancat

野火 LubanCat 系列（Rockchip 六族）的 Yocto BSP 层。

- 使用者请从仓库根 [`../README.md`](../README.md) 开始（装依赖 → 编译 → 烧写）
- 设计细节与源码级分析在 [`../docs/manual.md`](../docs/manual.md)
- 版本矩阵在 [`../docs/VERSION-MATRIX.md`](../docs/VERSION-MATRIX.md)

层元数据：`LAYERVERSION_lubancat = "0.1"`、`LAYERSERIES_COMPAT_lubancat = "scarthgap"`、
`BBFILE_PRIORITY_lubancat = "10"`、`LAYERDEPENDS_lubancat = "core rockchip"`。

## 依赖

| 层 | 分支 | 用途 |
|---|---|---|
| poky | scarthgap (5.0 LTS) | 基础 |
| meta-rockchip | scarthgap | `rk{3562,356x,3576,3588}.inc` / `rockchip-common.inc` / `linux-rockchip` / `u-boot-rockchip` / wic |
| meta-arm | scarthgap | `arm-toolchain`（可选，GPU 相关 recipe 可能引用） |
| meta-openembedded | scarthgap | `meta-oe` `meta-python` `meta-networking` |

## 支持的 MACHINE

| MACHINE | 板卡 | 状态 |
|---|---|---|
| `lubancat-rk3588` | LubanCat-4 / 4IO / 5 / 5-V2 / 5IO / 5IOB / 5IOF / 5IOI / 5IO-AIBOX1 | 族级；4-V1 已上板验证（HDMI/GPU/NPU/extboot） |
| `lubancat-4-v1` | LubanCat-4 V1（RK3588S / 8GB LPDDR4X / eMMC + TF / GMAC1 + RTL8211F） | 板级别名，钉死 4-V1 的 dtb/uEnv |
| `lubancat-rk3576` | LubanCat-3 / 3-V2 / 3IO / 3IO-test | 配置就位，编译验证 |
| `lubancat-rk3568` | LubanCat-2 / 2-V1/V2/V3 / 2H / 2IO / 2N / 2N-V2/V3 | 配置就位，编译验证 |
| `lubancat-rk3566` | LubanCat-1 / 1H / 1IO / 1N / 0 / CM4 | 配置就位，编译验证（U-Boot 走 rk3568_defconfig + rk3566.config） |
| `lubancat-rk3562` | LubanCat-1HS / 1HS-test | 配置就位，编译验证 |
| `lubancat-rk3528` | LubanCat-Q1 / Q1IO | 配置就位，编译验证（meta-rockchip 无 rk3528.inc，本层自带） |
| — | LubanCat SG200x（全志） | **不适用本层**，需另建层（fsbl + opensbi + fip.bin） |

## 用法

在**仓库根**执行（层在 `meta-lubancat/` 子目录，别把仓库根当层加进去）：

```bash
# 方式 A：kas（推荐）
kas build kas/lubancat.yml
KAS_MACHINE=lubancat-rk3568 kas build kas/lubancat.yml

# 方式 B：手动
source poky/oe-init-build-env build
bitbake-layers add-layer ../meta-lubancat
# 编辑 build/conf/local.conf: MACHINE = "lubancat-4-v1"（或任意族级 MACHINE）
bitbake lubancat-image-minimal extboot-image
./scripts/make-updateimg.sh
```

## extboot 机制（第 14 章）

boot 分区是 ext2 文件系统（GPT `bootable` 位），内容由 `recipes-bsp/extboot/extboot-image.bb` 生成：

```
boot.scr（mkimage，源=内核树 uEnv/boot.cmd）
Image
rk-kernel.dtb      ← U-Boot 早期 DTB 与内核 DTB 同源
dtb/*.dtb          族内全量
dtb/overlay/*.dtbo 族内全量
uEnv/uEnv.txt      源=内核树 uEnv/<soc>/uEnvLubanCat*.txt，只替换 cmdline 行
```

族 inc 提供 `LUBANCAT_DTB / LUBANCAT_UENV_DIR / LUBANCAT_UENV / LUBANCAT_CMDLINE`，
板级 conf 只覆盖前三个。**`boot.cmd` 与 30 份 uEnv 模板不复制进层**——构建时从
`${STAGING_KERNEL_DIR}` 取，避免随内核升级漂移。

### 首启切板（族镜像）

族 machine 默认 `LUBANCAT_DTB = "*-generic.dtb"`：generic dtb 在本族任意板子上都能起，
首次启动由 `recipes-core/lubancat-firstboot/lubancat-board-detect` 读 SARADC 板卡 ID，
把 boot 分区的 `rk-kernel.dtb` 与 `uEnv/uEnv.txt` 换成对应板子的那份，然后重启一次。
映射表在 `files/board-table`（40 条，由厂商 `boot_init.sh` 机械转换）。

板级别名（如 `lubancat-4-v1`）钉死自己的 dtb，服务会 `cmp` 发现内容一致，不重启。
开关：`LUBANCAT_FIRSTBOOT_SWITCH = "0"` 可关掉切板，只保留扩容。

### 变量契约（族 inc ↔ 板级 conf）

| 变量 | 定义位置 | 作用 |
|---|---|---|
| `LUBANCAT_FAMILY` | 族 inc | 选 `recipes-bsp/u-boot/files/rk<family>-lubancat.cfg`，也是产物命名 |
| `LUBANCAT_CPU_SYMBOL` | 族 inc | 断言内核 `CONFIG_CPU_<x>=y`，决定 overlay 的 dtbo 门控 |
| `LUBANCAT_UBOOT_FRAGMENT` | 族 inc | 额外追加 `configs/<name>`（只有 rk3566 非空：`rk3566.config`） |
| `LUBANCAT_RKBIN_INI` | 族 inc | rkbin 里的 MINIALL ini（rk3568 必须覆盖成 `RK3568MINIALL.ini`，否则用成 rk3566 的 DDR bin） |
| `LUBANCAT_DDR_BIN` | 族 inc | `do_compile:prepend` 断言 rkbin 里确有该 DDR bin |
| `LUBANCAT_CMDLINE` | 族 inc | uEnv 的 `cmdline=` 行，**必须含 `1500000n8`** |
| `LUBANCAT_DTB` | 板级 conf | 拷成 `/rk-kernel.dtb` 的那一份 |
| `LUBANCAT_UENV_DIR` / `LUBANCAT_UENV` | 板级 conf | 取内核树里的 uEnv 模板 |
| `LUBANCAT_FAMILY_ALL_DTBS` | 族 machine | `1` = 族内全量 dtb 进 boot 分区 |
| `LUBANCAT_FIRSTBOOT_SWITCH` | 族 machine | `1` = 装并启用首启认板切 dtb 服务 |

## 设计原则

1. **薄**。凡是 `rk*.inc` / `rockchip-common.inc` 已经给的（tune、SERIAL_CONSOLES 默认值、
   kernel/bootloader provider、mali 参数）一律 `require`，不复制。本层的真实差异面只有五件事：
   - 内核源换成 `LubanCat/kernel.git:lbc-develop-6.1`
   - U-Boot / rkbin 源换成 `LubanCat/u-boot.git:main` + `LubanCat/rkbin.git:master`
   - 补齐内核 `make dtbs`（`%.img` 规则不会进 `overlay/`）与 `${DEPLOYDIR}/dtb/` 部署
   - extboot 的 boot 分区镜像
   - 板级 dts / `UBOOT_MACHINE` / `LOADER_INI`
2. **不覆盖闭源件**。`libmali` / `rkwifibt-firmware` 继续用 meta-rockchip 的，按需装进 L2 镜像。
   NPU 用户态（`librknnrt.so` + `rknn_server`）当前来自 SDK 的 rknpu2 runtime，未做成 recipe。
3. **不用 `rk-binary-native_%.bbappend` 去钉 rkbin**。rkbin 的唯一真相是
   `u-boot-rockchip.bbappend` 里的 `SRC_URI_rkbin` 与 `SRCREV_rkbin`；再钉一份容易出现两处不一致。
4. **逐族配置靠变量，不靠复制 recipe**。族差异只有 `UBOOT_MACHINE`、`LUBANCAT_UBOOT_FRAGMENT`、
   `LOADER_INI`、`KBUILD_DEFCONFIG`、`DTB/UENV` 五项，全在 `conf/machine/` 里。

## 已知待验证项

- rk3576 / rk3568 / rk3566 / rk3562 / rk3528 只做过编译级验证（`UBOOT_MACHINE` 存在、
  `EARLY_DISTRO_DTB=y`、dtb/dtbo 数量、boot-ext2 内容），**未上板**。
- `lubancat-5-rk3588-pcie_defconfig` 显式关闭 `EARLY_DISTRO_DTB`，**不能**用于 extboot；
  族机器固定 `rk3588_defconfig`。
- rk3566 无独立 spl/bl31/bl32，`RKTRUST/` 下也没有 `RK3566TRUST.ini`。
