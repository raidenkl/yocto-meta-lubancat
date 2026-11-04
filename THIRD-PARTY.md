# 第三方组件与许可

本仓库（`meta-lubancat` 层 + 脚本 + 文档）以 MIT 发布，见 `LICENSE`。
下列组件**不在**本仓库的 MIT 覆盖范围内。

## 一、构建时由 kas / bitbake 拉取，不随本仓库分发

| 组件 | 来源 | 许可 | 说明 |
|---|---|---|---|
| poky | `git.yoctoproject.org/poky` | MIT | Yocto 参考发行版 |
| meta-arm | `git.yoctoproject.org/meta-arm` | MIT | 工具链与 TF-A |
| meta-openembedded | `github.com/openembedded/meta-openembedded` | MIT | meta-oe / python / networking / filesystems |
| meta-rockchip | `github.com/JeffyCN/meta-rockchip` | MIT | Rockchip BSP 层（kernel/u-boot/wic 基础 recipe） |
| LubanCat/kernel | `github.com/LubanCat/kernel` 分支 `lbc-develop-6.1` | GPL-2.0 | 只钉 `SRCREV`，源码由 bitbake 取 |
| LubanCat/u-boot | `github.com/LubanCat/u-boot` 分支 `main` | GPL-2.0+ | 同上 |
| LubanCat/rkbin | `github.com/LubanCat/rkbin` 分支 `master` | Rockchip 二进制分发条款 | DDR/ bl31 / bl32 等预编译二进制，**本仓库只钉 SRCREV，不分发任何 bin** |

## 二、随本仓库分发

| 组件 | 路径 | 许可与来源 | 备注 |
|---|---|---|---|
| `afptool` (v2.29) | `tools/rkpack/afptool` | Rockchip 厂商工具（Android Firmware Package Tool），非开源、非 MIT | 从 LubanCat Linux SDK `tools/linux/Linux_Pack_Firmware/rockdev/` 原样复制，仅用于把 Yocto 产物打成 rkfw `update.img` |
| `rkImageMaker` | `tools/rkpack/rkImageMaker` | 同上 | 同上；负责加 `RKFW` 头与 `-RK<chip>` 标记 |

这两个是可执行二进制（x86-64 静态链接、已 stripped），**按原样（as-is）再分发**，
不提供任何担保。若你不接受厂商二进制的再分发，删除 `tools/rkpack/` 即可，
然后用 `PACK=/path/to/your/sdk/.../rockdev ./scripts/make-updateimg.sh`
指向自备 SDK —— 脚本与镜像构建完全不依赖它们（`wic` 路线不需要任何厂商工具）。

## 三、数据文件

| 文件 | 来源 | 说明 |
|---|---|---|
| `meta-lubancat/recipes-core/lubancat-firstboot/files/board-table` | 由 LubanCat SDK `debian12/overlay/etc/init.d/boot_init.sh` 的 `board_info()` **机械转换**（family 归并、剔除 rk3128） | 仅含 40 行「板卡 ID → dtb / uEnv / 板名」映射，不含代码 |
| `meta-lubancat/recipes-kernel/linux/files/0001-*.patch` | 本仓库作者 | 给 LubanCat-4 V1 的 dts 增加一行 `#include`，供 `EXTBOOT=0` / overlay 关闭时兜底 |
| `scripts/setup-mirror.sh` 中的 gh-proxy 前缀 | 第三方公共服务 | 只是 URL 前缀，可自行替换为任意镜像 |

## 四、致谢

- Rockchip 与 Jeffy Chen 维护的 `meta-rockchip`
- 野火 LubanCat 提供的 kernel / u-boot / rkbin 与 SDK
- Yocto Project 与 OpenEmbedded
