# 版本矩阵

对应 `CHANGELOG.md` 的 **v0.1.2**。更新日期：2026-11-05。

## 1. Yocto 系列

| 项 | 值 |
|---|---|
| 系列 | scarthgap (5.0) |
| distro | `poky` |
| init | systemd |
| 包格式 | ipk |

## 2. 上游层（`kas/lubancat.lock.yml` 钉死）

| 层 | 仓库 | 分支 | commit |
|---|---|---|---|
| poky | `git.yoctoproject.org/poky` | scarthgap | `b6ae714a1d1bfae8384654a13da15996cac64712` |
| meta-arm | `git.yoctoproject.org/meta-arm` | scarthgap | `0a4b911d9fd63ab29c4532a907fae3282dbdcfe4` |
| meta-openembedded | `github.com/openembedded/meta-openembedded` | scarthgap | `2db6aece32c7f8ebf6015b468e1b4e21de072e3b` |
| meta-rockchip | `github.com/JeffyCN/meta-rockchip` | scarthgap | `6e9e6a8cb07cbdb4328ebd5ee1e4fed34e7a0fa8` |

## 3. BSP 三仓（bbappend 的 `SRCREV` 钉死）

| 组件 | 仓库 | 分支 | SRCREV | 版本 |
|---|---|---|---|---|
| kernel | `github.com/LubanCat/kernel` | `lbc-develop-6.1` | `a0c672347152a0ea0713a043f1d1c4ec4323ff93` | Linux 6.1.99 |
| kernel（RT） | `github.com/LubanCat/kernel` | `lbc-develop-6.1-rt36` | `3d027a80ff4023e4ee6dba24db140a2eab2c1f28` | Linux 6.1.99-rt36 |
| u-boot | `github.com/LubanCat/u-boot` | `main` | `a564b1d927aa6032520819536a5b8c450e8141c4` | 2017.09 (Rockchip fork) |
| rkbin | `github.com/LubanCat/rkbin` | `master` | `74213af1e952c4683d2e35952507133b61394862` | DDR/ bl31 / bl32 预编译 |

RT 行由 `meta-realtime` 层覆盖（`LUBANCAT_KERNEL_BRANCH` / `LUBANCAT_KERNEL_SRCREV`），
只在叠加 `kas/realtime.yml` 时生效；启用 RT 后 `uname -r` 实测为 `6.1.99-rt36-lubancat`。
RT 目前只在 RK3588 族编译验证，其余族未上板；RK3528 的 RT defconfig 没有 `PREEMPT_RT`，不支持。

打包工具：`tools/rkpack/afptool` = Android Firmware Package Tool **v2.29**。

## 4. MACHINE 与验证级别

| MACHINE | SoC | 默认 dtb | U-Boot 配置 | 内核 defconfig | DDR 频点 | DDR bin（rkbin） | 验证级别 |
|---|---|---|---|---|---|---|---|
| `lubancat-4-v1` | RK3588S | `rk3588s-lubancat-4-v1.dtb` | `rk3588_defconfig` | `lubancat_linux_rk3588_defconfig` | 1848 | `lp4_1848/lp5_2112 v1.19` | **真机上板**：串口登录 / 有线网 / HDMI / GPU(kmscube) / NPU(rknn) 均通过（那次是 2112 档 DDR；1848 档只做到编译期验证 + idblock 时间戳比对） |
| `lubancat-rk3588` | RK3588/3588S | `rk3588-lubancat-generic.dtb` | `rk3588_defconfig` | 同上 | 1848 | `lp4_1848/lp5_2112 v1.19` | 编译级（12 dtb / 278 dtbo 产出，未逐板上电） |
| `lubancat-rk3576` | RK3576 | `rk3576-lubancat-generic.dtb` | `rk3576_defconfig` | `lubancat_linux_rk3576_defconfig` | 1560 | `lp4_2112/lp5_2736 v1.09` | **真机上板**：GPU / NPU / 网络通过 |
| `lubancat-rk3568` | RK3568 | `rk356x-lubancat-generic.dtb` | `rk3568_defconfig` | `lubancat_linux_rk356x_defconfig` | 1560 | `1560MHz v1.23` | **真机上板**：GPU / NPU / 网络通过 |
| `lubancat-rk3566` | RK3566 | `rk356x-lubancat-generic.dtb` | `rk3568_defconfig` + `configs/rk3566.config` | 同上 | 1056 | `1056MHz v1.23` | **真机上板**：GPU / NPU / 网络通过 |
| `lubancat-rk3562` | RK3562 | `rk3562-lubancat-generic.dtb` | `rk3562_defconfig` | `lubancat_linux_rk3562_defconfig` | 1332 | `1332MHz v1.07` | 编译解析级 |
| `lubancat-rk3528` | RK3528 | `rk3528-lubancat-generic.dtb` | `rk3528_defconfig` | `lubancat_linux_rk3528_defconfig` | 1056 | `1056MHz v1.11` | 编译解析级 |

> 「编译解析级」= `bitbake -p` 通过 + `bitbake -e` 变量核对正确 + 组件齐全，**没有上过板**。
> 不要把这一列当成"已验证"。
>
> DDR 两列：`DDR 频点` 是板级定型频点（单位 MHz），`DDR bin` 是 rkbin `bin/rk35/` 下实际
> 打包进 loader 的文件（表里省略了 `rk<SoC>_ddr_` 前缀与 `.bin` 后缀）。bin 文件名里的频率是
> **bin 内含的最高档位**（LPDDR4x / LPDDR5 两套），不等于内核运行时实际频点——运行时由 dmc
> devfreq 协商。RK3588 全系用 1848 档（rkbin 默认是 2112/2400 档，本层在 u-boot 的
> `do_compile:prepend` 里改写 ini 的 `Path1` + `FlashData`）；RK3576 的 1560MHz 是板级频点，
> rkbin 没有对应档位的 bin，只能沿用 `lp4_2112/lp5_2736` 那一份。

## 5. 如何重新生成本表

```bash
# 上游层（在仓库根，kas 已经 clone 过）
for d in poky meta-arm meta-openembedded meta-rockchip; do
  printf '%-20s %s\n' "$d" "$(git -C $d rev-parse HEAD)"
done

# BSP 三仓（SRCREV 写在 bbappend 里）
grep -n SRCREV meta-lubancat/recipes-kernel/linux/linux-rockchip_6.1.bbappend
grep -n SRCREV meta-lubancat/recipes-bsp/u-boot/u-boot-rockchip.bbappend

# lock 一致性（应与本表第 2 节一致）
grep commit kas/lubancat.lock.yml
```

升级上游后：`kas lock --update kas/lubancat.yml` → 更新本表 → 更新 `CHANGELOG.md` → 打 tag。
