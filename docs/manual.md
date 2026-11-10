# 基于 Yocto 的 LubanCat 构建环境实施手册

> 覆盖板卡：RK3588 / RK3588S / RK3576 / RK3568 / RK3566 / RK3562 / RK3528 六族 39 份板级 dtb  
> Yocto 版本：scarthgap 5.0 LTS｜内核：Linux 6.1.99（LubanCat fork）｜U-Boot：2017.09（LubanCat fork）  
> 编写基线：2026-11-10（对应 `CHANGELOG.md` v0.1.3）。文中 SHA、bin 版本、分支名都标了取法——**换时间点构建请重新取值，不要照抄旧值。**

---

## 目录

- [0. 阅读指南与版本矩阵](#0-阅读指南与版本矩阵)
- [1. 目标与边界](#1-目标与边界)
- [2. 主机环境与依赖安装](#2-主机环境与依赖安装)
- [3. 工作区与层获取](#3-工作区与层获取)
- [4. bblayers.conf 与 local.conf](#4-bblayersconf-与-localconf)
- [5. BSP 与 meta 层选型](#5-bsp-与-meta-层选型)
- [6. meta-lubancat 设计与机器配置](#6-meta-lubancat-设计与机器配置)
- [7. 内核定制与「必须实测」清单](#7-内核定制与必须实测清单)
- [8. U-Boot 与 rkbin](#8-u-boot-与-rkbin)
- [9. 镜像与包组](#9-镜像与包组)
- [10. 分区、打包与烧录](#10-分区打包与烧录)
- [11. SDK / eSDK / devtool](#11-sdk--esdk--devtool)
- [12. 故障排查手册](#12-故障排查手册)
- [13. CHTUZKI/yocto-rk3588-core 仓库评估](#13-chtuzkiyocto-rk3588-core-仓库评估)
- [14. extboot：设备树切换 / dtbo / uEnv 的全系方案](#14-extboot设备树切换--dtbo--uenv-的全系方案)
- [附录 A 变量速查表](#附录-a-变量速查表)
- [附录 B 验收清单](#附录-b-验收清单)
- [附录 C 命令卡](#附录-c-命令卡)

---

## 0. 阅读指南与版本矩阵

### 0.1 读者假设

你已经在 LubanCat 上跑通过「U-Boot → TFTP 拉 Image/dtb → NFS rootfs」这条链，能读 DTS、会改 Kconfig、知道 `ttyFIQ0` 是什么。本手册不解释 Yocto 的基本概念（layer / recipe / task），只讲**落到这些板子上会踩什么**。

只想要「一条命令编出能烧的镜像」，看根目录 `README.md`；本手册是它背后的原理、边界与排错。

### 0.2 版本矩阵

| 组件                | 来源                                                      | 分支                     | 提交 / 版本                                                                   | 取法                                                |
| ----------------- | ------------------------------------------------------- | ---------------------- | ------------------------------------------------------------------------- | ------------------------------------------------- |
| poky              | `https://git.yoctoproject.org/poky`                     | `scarthgap`            | `b6ae714a1d1bfae8384654a13da15996cac64712`                                | `git -C poky rev-parse HEAD`                      |
| meta-arm          | `https://git.yoctoproject.org/meta-arm`                 | `scarthgap`            | `0a4b911d9fd63ab29c4532a907fae3282dbdcfe4`                                | 同上                                                |
| meta-openembedded | `https://github.com/openembedded/meta-openembedded.git` | `scarthgap`            | `2db6aece32c7f8ebf6015b468e1b4e21de072e3b`                                | 同上                                                |
| meta-rockchip     | `https://github.com/JeffyCN/meta-rockchip.git`          | `scarthgap`            | `6e9e6a8cb07cbdb4328ebd5ee1e4fed34e7a0fa8`                                | 同上                                                |
| **U-Boot**        | `https://github.com/LubanCat/u-boot.git`                | **`main`**             | `a564b1d927aa6032520819536a5b8c450e8141c4`                                | `git ls-remote … refs/heads/main`                 |
| **rkbin**         | `https://github.com/LubanCat/rkbin.git`                 | **`master`**           | `74213af1e952c4683d2e35952507133b61394862`                                | `git ls-remote … refs/heads/master`               |
| **内核**            | `https://github.com/LubanCat/kernel.git`                | `lbc-develop-6.1`      | `a0c672347152a0ea0713a043f1d1c4ec4323ff93`；产物版本串 **`6.1.99-lubancat`**    | `git ls-remote … refs/heads/lbc-develop-6.1`      |
| **内核（RT）**        | 同上                                                      | `lbc-develop-6.1-rt36` | `3d027a80ff4023e4ee6dba24db140a2eab2c1f28`；版本串 **`6.1.99-rt36-lubancat`** | `git ls-remote … refs/heads/lbc-develop-6.1-rt36` |
| DDR bin           | 由 rkbin 的 `RKBOOT/RK*MINIALL.ini` 决定，本层按 machine 改写     | —                      | RK3588 族 `rk3588_ddr_lp4_1848MHz_lp5_2112MHz_v1.19.bin`（见 §8.7）           | 读 ini                                             |
| 打包工具              | `tools/rkpack/`（随仓库）                                    | —                      | `afptool` 2.29 + `rkImageMaker`                                           | `sha256sum -c tools/rkpack/SHA256SUMS`            |
| 主机                | Ubuntu 22.04 / 24.04 或 Debian 12                        | —                      | —                                                                         | `lsb_release -a`                                  |

上游四个层的 SHA 已写进 `kas/lubancat.lock.yml`；BSP 三仓的 SRCREV 写在两个 bbappend 里（`LUBANCAT_KERNEL_BRANCH` / `LUBANCAT_KERNEL_SRCREV` 是内核那一对的弱赋值入口）。

> **为什么要钉 SHA**：上游 `meta-rockchip` 的 `u-boot-rockchip.bb` 与 `linux-rockchip_6.1.bb` 内部已经钉了 `SRCREV`，但你自己这三个仓库用的是 `branch=`，不钉的话每次 `bitbake` 可能拿到不同代码，「昨天能编今天不能编」的第一嫌疑永远是这里。

### 0.3 本书约定

- `$WS` = 仓库根（`yocto-meta-lubancat/`），也是 kas 的工作目录；构建目录是 `$WS/build`（RT 是 `$WS/build-rt`）。
- 「已验证」= 有板上串口日志或构建日志支撑；历史结论与当前状态的差别会单独标注。各族当前状态见 §1.2。
- 串口一律指 UART2，1500000 8N1，主机侧 `/dev/ttyUSB0`，内核侧 `ttyFIQ0`。

---

## 1. 目标与边界

### 1.1 硬件事实（决定了后面每一个配置项）

以 LubanCat-4 V1（EBF410116 V1.2，RK3588S）为基准；其他族只在差异处单独说明。

| 项    | 事实                                                                  | 对 Yocto 配置的直接影响                                                         |
| ---- | ------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| SoC  | **RK3588S**（不是 RK3588）                                              | `gmac1` 在 `ethernet@fe1c0000`（全功能 RK3588 里该地址是 gmac0）；DTS 用 `rk3588s-*` |
| 内存   | 8GB LPDDR4X @1848MHz，4 通道 × 2GB                                     | DDR bin 锁 1848 档（`rk3588_ddr_lp4_1848MHz_lp5_2112MHz_v1.19.bin`）        |
| 存储   | eMMC（`sdhci`，HS400）+ TF（`sdmmc`，SDR104）                             | 两套 mmc 序号不固定 → 挂根一律用 `/dev/mmcblk0p3` 或 `PARTUUID`，不写死分区号语义             |
| 以太网  | GMAC1 + **RTL8211F**，`rgmii-rxid`，reset `gpio3 PB2`，`tx_delay=0x1b` | `CONFIG_STMMAC_ETH` / `CONFIG_DWMAC_ROCKCHIP` / `CONFIG_REALTEK_PHY`    |
| 调试串口 | **UART2，1500000 8N1**，内核里是 `ttyFIQ0`（fiq-debugger 接管）               | `SERIAL_CONSOLES="1500000;ttyFIQ0"`，不能写 `ttyS2`                         |
| 按键   | MR（MaskROM）、REC（loader）                                             | 烧写流程见 §10.3                                                             |
| 电源   | RK806 + RK8602/RK8603                                               | `CONFIG_MFD_RK806` / `CONFIG_REGULATOR_RK860X`                          |
| NPU  | 内置 RKNPU（`fdab0000.npu`）                                            | 内核侧 `rknpu` 驱动；用户态 `librknnrt.so` 不在默认镜像里（§12.19）                       |

### 1.2 三级验收

镜像三者递进：`lubancat-image-minimal` → `-net` → `-full`。判据与镜像一一对应：

| 阶段       | 对应镜像                     | 判定点（缺一不可）                                                                                                                                                          |
| -------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 能启动、能登录  | `lubancat-image-minimal` | 串口 DDR → U-Boot → `Starting kernel` → 内核日志 → `login:`；`uname -r` 为 `6.1.99-lubancat`；`/proc/cmdline` 含 `console=ttyFIQ0,1500000n8 root=/dev/mmcblk0p3 boot_part=2` |
| 网络闭环     | `lubancat-image-net`     | `ip -br link` 有 `end1`；`ethtool end1` 见 `1000Mb/s Full`；`ping` 网关通；`ip -s link` 计数增长；无线见 §7.7                                                                      |
| 图形 / NPU | `lubancat-image-full`    | `ls /sys/class/drm/` 出现 `card0-HDMI-A-1`；`kmscube` 出画面；`/sys/class/misc/mali0/device/gpuinfo` 可读；NPU 见 §12.19（需自备 `librknnrt.so`）                                  |

各族当前验证状态（与 `docs/VERSION-MATRIX.md` 第 4 节一致）：

| MACHINE           | SoC          | 上板状态                                                    |
| ----------------- | ------------ | ------------------------------------------------------- |
| `lubancat-4-v1`   | RK3588S      | 已上板：串口 / 有线网 / HDMI / GPU / NPU（GPU/NPU 那次是 2112 档 DDR） |
| `lubancat-rk3576` | RK3576       | 已上板：GPU / NPU / 网络                                      |
| `lubancat-rk3568` | RK3568       | 已上板：GPU / NPU / 网络                                      |
| `lubancat-rk3566` | RK3566       | 已上板：GPU / NPU / 网络                                      |
| `lubancat-rk3588` | RK3588/3588S | 编译级：12 dtb / 278 dtbo 产出，未逐板上电                          |
| `lubancat-rk3562` | RK3562       | 编译解析级                                                   |
| `lubancat-rk3528` | RK3528       | 编译解析级                                                   |

「编译级」= `bitbake -p` 通过 + `bitbake -e` 变量核对正确 + 产物数量符合预期，**没有上过板**。RK3588 族从 v0.1.3 起 DDR 锁 1848 档，该档只做到编译期验证 + idblock 时间戳比对，未在 RK3588 板上实测串口频点。

### 1.3 明确不做

- 不做 Android；不迁主线 U-Boot（主线没有 RK3588/3568 的 DDR 初始化，必须依赖 rkbin 闭源 blob）。
- 不承诺 NPU 模型精度（那是 RKNN 工具链的事）。
- 不在生产镜像里保留 `debug-tweaks`（默认 `local.conf` 是开着的，发布前必须改）。

---

## 2. 主机环境与依赖安装

### 2.1 发行版与资源预算

| 项    | 下限                           | 建议                                   |
| ---- | ---------------------------- | ------------------------------------ |
| 发行版  | Ubuntu 22.04 LTS / Debian 12 | 22.04（社区验证最多）                        |
| CPU  | 8 核                          | 16 核以上                               |
| 内存   | 16 GiB                       | 32 GiB（`PARALLEL_MAKE` 大了会 OOM）      |
| 磁盘   | 300 GB 空闲                    | 500 GB SSD                           |
| 文件系统 | ext4 / xfs，大小写敏感、支持硬链接       | **禁止** NTFS、exFAT、9p、VMware 共享目录、网络盘 |

目录预算：`DL_DIR` 60 GB、`SSTATE_DIR` 80 GB、`TMPDIR` 120 GB。三者分放不同物理盘能明显提速。

实测规模：full 镜像 8815 个 task，64 核 / 16 线程约 1 小时；minimal 首次（含下载）8 核约 6~10 小时。

### 2.2 依赖安装

```bash
sudo ./scripts/host-deps.sh
```

脚本做四件事：装 Yocto 必需包 → 装 wic / 分区工具 → 装 `u-boot-tools`（提供 `mkimage`）与 `bmap-tools` → 以 `$SUDO_USER` 身份 `pip install --user kas`（**不能**用 root 装，否则普通用户构建时看不到）→ 检查 locale 并打印磁盘与内存。

手工等价：

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential chrpath cpio debianutils diffstat file gawk gcc git \
  iputils-ping libacl1 liblz4-tool locales python3 python3-git python3-jinja2 \
  python3-pexpect python3-pip python3-subunit python3-venv socat texinfo unzip \
  wget xz-utils zstd parted gdisk dosfstools mtools e2fsprogs device-tree-compiler \
  u-boot-tools bmap-tools
sudo locale-gen en_US.UTF-8
```

两个不要：**不要装 `python3-wic`**（Ubuntu 源里没有这个包，加上它整条 `apt-get install` 会失败，wic 由 poky 自带）；**不要用 root 跑构建**（sstate 属主会乱）。

### 2.3 三个必查项

```bash
# 1) locale：非 UTF-8 会让 bitbake 在解析阶段报 UnicodeDecodeError
locale -a | grep -i en_US.utf8 || sudo locale-gen en_US.UTF-8
echo 'export LANG=en_US.UTF-8' >> ~/.bashrc

# 2) 文件句柄：默认 1024，并发一上来就 Too many open files
ulimit -n 65536

# 3) 磁盘
df -h $WS
```

`scripts/setup-mirror.sh` 会顺手设好这两项（`LANG` 与 `nofile`），所以国内网络场景下 `source` 它一次就够。

### 2.4 `rkdeveloptool`（apt 里没有，要自己编）

只在走 wic 整盘烧写时用；走 `update.img`（推荐，§10.3）不需要。

```bash
git clone https://github.com/rockchip-linux/rkdeveloptool
cd rkdeveloptool && autoreconf -i && ./configure && make -j"$(nproc)" && sudo make install
# 报 "Creating Comm Object failed" 时装 udev 规则后重插 USB：
# sudo cp 99-rk-rockusb.rules /etc/udev/rules.d/ && sudo udevadm control --reload
```

---

## 3. 工作区与层获取

### 3.1 两种方式，选一个

| 方式                                    | 复现性                                         | 适合                  |
| ------------------------------------- | ------------------------------------------- | ------------------- |
| **kas**（推荐）                           | 高：一个 yml 描述全部层 + `local.conf` 内容，lock 钉 SHA | 日常构建、CI、交接          |
| 手动 clone + `bitbake-layers add-layer` | 中：`bblayers.conf` 容易与文档漂开                   | 想逐层看清楚，或改 kas 不熟的现场 |

kas 的核心价值是**消除「`bblayers.conf` 和文档不一致」这个最常见的复现失败**。

**方式 A：kas**

```bash
git clone https://github.com/<your-org>/yocto-meta-lubancat.git
cd yocto-meta-lubancat

python3 -m venv .kas && . .kas/bin/activate && pip install kas
# 国内 pip 镜像没同步 kas 时报 "No matching distribution found"：
#   pip install -i https://pypi.org/simple kas

source ./scripts/setup-mirror.sh       # 只影响当前 shell 的 git
kas build kas/lubancat.yml             # 拉 4 个上游层 + 编 minimal + extboot-image
```

`kas/lubancat.lock.yml` 会被自动加载。命令必须在仓库根执行：kas 的 work dir 取当前目录，四个上游层会 clone 到 `./poky`、`./meta-arm` 等位置，`build/` 也建在仓库根（都已 `.gitignore`）。

**方式 B：手动**

```bash
./scripts/fetch-layers.sh              # 拉 4 个上游层到仓库根，并打印各自 commit
mkdir -p build/conf
cp build-conf/local.conf.sample build/conf/local.conf   # 按本机改 BB_NUMBER_THREADS / PARALLEL_MAKE

source poky/oe-init-build-env build
bitbake-layers add-layer ../meta-arm/meta-arm ../meta-arm/meta-arm-toolchain \
  ../meta-openembedded/meta-oe ../meta-openembedded/meta-python \
  ../meta-openembedded/meta-networking ../meta-openembedded/meta-filesystems \
  ../meta-rockchip ../meta-lubancat
bitbake-layers show-layers             # 11 个层
bitbake lubancat-image-minimal extboot-image
```

### 3.2 层清单

| 层                                                                          | 来源      | 作用                                                                 |
| -------------------------------------------------------------------------- | ------- | ------------------------------------------------------------------ |
| `poky/{meta,meta-poky,meta-yocto-bsp}`                                     | Yocto   | 基础                                                                 |
| `meta-arm/{meta-arm,meta-arm-toolchain}`                                   | Yocto   | 工具链与固件                                                             |
| `meta-openembedded/{meta-oe,meta-python,meta-networking,meta-filesystems}` | OE      | 工具、python 包、网络、文件系统                                                |
| `meta-rockchip`                                                            | JeffyCN | BSP：`rk35xx.inc`、`linux-rockchip`、`u-boot-rockchip`、`mali.inc`、wic |
| **`meta-lubancat`**                                                        | 本仓库     | 板级差异（priority 10）                                                  |
| `meta-realtime`（可选）                                                        | 本仓库     | PREEMPT_RT 内核（priority 15），只在叠加 `kas/realtime.yml` 时参与             |

### 3.3 国内网络优化：先关全量克隆，再谈代理（实测数据）

慢的主因不是「GitHub 被墙」，而是 **bitbake 默认做全量 `git clone`**：kernel 仓库全量 3~4 GB、u-boot 600 MB+，而真正需要的只有一个提交。

Ubuntu 22.04 + 电信网络实测（2026-11）：

| 路径            | 做法                     | 实测                      |
| ------------- | ---------------------- | ----------------------- |
| u-boot        | bitbake 默认（全量克隆）       | **62 KiB/s**，20 分钟才 44% |
| u-boot        | `--depth 1` 直连         | 22 MB，**<40 s**         |
| u-boot        | `--depth 1` 经 gh-proxy | 22 MB，53 s              |
| 10 MB tarball | 直连                     | ~30 KB/s                |
| 10 MB tarball | 经 gh-proxy             | **4.3 MB/s**            |

结论：**浅克隆是数量级收益，代理是补充**。已写进 `build-conf/local.conf.sample` 与 `kas/lubancat.yml`：

```conf
PREMIRRORS:prepend = "https://github.com/(.*)  https://gh-proxy.com/https://github.com/\1  \n"
BB_GIT_SHALLOW = "1"
BB_GIT_SHALLOW_DEPTH = "1"
BB_GENERATE_SHALLOW_TARBALLS = "1"
```


git 克隆的代理放在 shell 里按需生效（`scripts/setup-mirror.sh` 就是这么做的），**不要**写进 `~/.gitconfig`——那会把 `git push` 也改写到代理上。

三个坑：

1. 浅克隆要求 `SRCREV` 在分支顶端附近；某个 recipe 钉的是历史提交时会回退全量（能编，只是慢）。
2. 已经用全量拉了一半的仓库，改 shallow 后报 `shallow mismatch`，删掉 `build/downloads/git2/github.com.LubanCat.*` 再跑。
3. 代理前缀是会失效的第三方服务，换前缀前先测速：
   ```bash
   curl -L -o /dev/null --max-time 12 -w '%{speed_download}\n' \
       https://gh-proxy.com/https://github.com/git/git/archive/refs/tags/v2.34.1.tar.gz
   ```

**`linux-firmware` 是另一个数量级的坑**：它走 `${KERNELORG_MIRROR}`（`cdn.kernel.org`），不在 GitHub 那条规则覆盖范围内，365 MB 的 tar.xz 实测 0.04 MB/s（约 2.5 小时）。加一条只针对 `/firmware/` 的前缀重写即可，别改 `KERNELORG_MIRROR` 本身（它会连带影响内核源码 tarball）：

```conf
KERNELORG_FW_SRC    = "https://cdn.kernel.org/pub/linux/kernel/firmware/"
KERNELORG_FW_MIRROR = "https://mirrors.aliyun.com/linux-kernel/firmware/"
PREMIRRORS:prepend = "${KERNELORG_FW_SRC}  ${KERNELORG_FW_MIRROR}  \n"
```

`PREMIRRORS` 的语义是**先试镜像，不通再回落原地址**，所以镜像站挂了不会把构建卡死；校验仍按 `SRC_URI[sha256sum]` 走。目录层级写错会 404，而 404 之后 bitbake 静默回落原地址，表现为「配了镜像还是慢」。

改 `local.conf` 不影响正在跑的构建（bitbake 启动时就解析完了）。已经卡在慢速下载上时，可以先 `curl` 拽进 `DL_DIR`（文件名与校验通过后 bitbake 会复用）：

```bash
cd build/downloads
curl -L -O https://mirrors.aliyun.com/linux-kernel/firmware/linux-firmware-20240909.tar.xz
sha256sum linux-firmware-20240909.tar.xz    # 必须等于配方里的值
```

### 3.4 目录布局

```
yocto-meta-lubancat/          ← 仓库根，也是 kas 的 work dir
├── kas/  build-conf/  scripts/  tools/rkpack/  docs/
├── meta-lubancat/  meta-realtime/
├── poky/  meta-arm/  meta-openembedded/  meta-rockchip/   ← 拉下来的层，已忽略
├── build/                                                  ← 非 RT 构建
│   ├── conf/local.conf
│   ├── latest/                        ← bbclass 生成的产物软链
│   └── tmp/deploy/images/<machine>/
└── build-rt/                                               ← RT 构建（KAS_BUILD_DIR）
```

已有旧工作区时可以把层目录移进来或做软链（本来就被忽略），也可以用 `KAS_REPO_REF_DIR=$HOME/old-workspace kas build …` 复用只读对象库。

这一步的常见报错：

| 现象                                  | 原因与处置                                      |
| ----------------------------------- | ------------------------------------------ |
| `does not contain a layer.conf`     | `add-layer` 指到了仓库根，层在 `meta-lubancat/` 子目录 |
| `Nothing PROVIDES 'linux-rockchip'` | 少加了 `meta-rockchip`，或分支不是 scarthgap        |
| `LAYERSERIES_COMPAT_lubancat` 报错    | 层与 poky 不是同一系列                             |
| `kas: command not found`            | 没装 kas，或 `~/.local/bin` 不在 PATH            |
| `path ... does not exist`           | 不在仓库根执行 kas                                |

---

## 4. bblayers.conf 与 local.conf

### 4.1 三条覆盖通则（所有「为什么覆盖不生效」都归到这里）

1. **conf 先于 recipe 解析**：machine conf 里的 `=` 能压住 recipe 里的 `?=`，压不住 recipe 里的 `=`。
2. **`BBFILE_PRIORITY` 只决定 `.bb` / `.bbappend` 谁生效，不决定变量值**。变量值靠解析顺序与 override。
3. 想稳，用 `VAR:lubancat-rk3588 = "..."`；临时试验，用 `local.conf` 的 `VAR:pn-xxx = "..."`。

bbappend 按层优先级**从低到高**应用，高优先级后写、后生效——这是 `meta-realtime` 用 priority 15 覆盖 `meta-lubancat`（10）里 `?=` 弱赋值的原因。

### 4.2 BBLAYERS

```conf
BBLAYERS ?= " \
  ${TOPDIR}/../poky/meta \
  ${TOPDIR}/../poky/meta-poky \
  ${TOPDIR}/../poky/meta-yocto-bsp \
  ${TOPDIR}/../meta-arm/meta-arm \
  ${TOPDIR}/../meta-arm/meta-arm-toolchain \
  ${TOPDIR}/../meta-openembedded/meta-oe \
  ${TOPDIR}/../meta-openembedded/meta-python \
  ${TOPDIR}/../meta-openembedded/meta-networking \
  ${TOPDIR}/../meta-openembedded/meta-filesystems \
  ${TOPDIR}/../meta-rockchip \
  ${TOPDIR}/../meta-lubancat \
"
```

| 层                 | `BBFILE_PRIORITY` | 说明                                                         |
| ----------------- | ----------------- | ---------------------------------------------------------- |
| poky / meta-poky  | 5                 | 基础                                                         |
| meta-rockchip     | 5                 | BSP，提供 `rk3588.inc`、`linux-rockchip`、`u-boot-rockchip`、wic |
| **meta-lubancat** | **10**            | 高于 BSP，保证 `.bbappend` 与整份 `.bb` 都覆盖生效                      |
| meta-realtime（可选） | **15**            | 覆盖 `LUBANCAT_KERNEL_*`，并让 RT 的 cfg 排在 `family.cfg` 之后      |

`LAYERDEPENDS_lubancat = "core rockchip"` 只列真正必需的层：`meta-arm` / `meta-openembedded` 是可选能力（GPU、python 包、网络工具），装上了不会因为没列而报错；反过来列了却没装，会直接 parse error。

### 4.3 local.conf 必改项

```conf
MACHINE = "lubancat-4-v1"
DISTRO  = "poky"

# 目录：TMPDIR 不能含 '..'（sanity checker 直接报错），三个目录都放 build/ 下
DL_DIR     = "${TOPDIR}/downloads"
SSTATE_DIR = "${TOPDIR}/sstate-cache"
TMPDIR     = "${TOPDIR}/tmp"

# 并发：见 4.3.1；64 核 / 62 GiB 取 16 / -j8
BB_NUMBER_THREADS = "16"
PARALLEL_MAKE     = "-j 8"

PACKAGE_CLASSES = "package_ipk"
INIT_MANAGER    = "systemd"

# bring-up 阶段：root 空密码 + 串口/ssh 调试工具
EXTRA_IMAGE_FEATURES = "debug-tweaks tools-debug"

# 省空间：任务完成后删 work 目录（devtool 期间要临时关掉）
INHERIT += "rm_work"

# systemd + weston 的组合强制要求 pam（poky 的 required-distro-features.inc）
DISTRO_FEATURES:append = " pam"

# 闭源件许可（libmali 等）
LICENSE_FLAGS_ACCEPTED = "synaptics-killswitch"

# BSP 内核补丁历史包袱多，先关掉 patch 相关 QA
ERROR_QA:remove = "patch-status patch-fuzz"
```

`build-conf/local.conf.sample` 是这份的完整版；`kas/lubancat.yml` 的 `local_conf_header` 是它的 kas 等价物。**改默认值必须两处一起改**，否则 kas 与手动两条路会静默漂开。

### 4.3.1 并发怎么算（不要按核数直接填）

`BB_NUMBER_THREADS × PARALLEL_MAKE` 是**标称**并发，不是稳态并发——bitbake 同一时刻跑着 fetch/unpack/package 这类不吃 CPU 的任务，真正编译的进程数通常只有标称值的 1/3~1/2。所以两个值都按「标称略超订」设，再用内存兜底。顺序是**先内存、后 CPU**：

| 步骤           | 公式                                  | 示例（64 核 / 62 GiB）                               |
| ------------ | ----------------------------------- | ----------------------------------------------- |
| 可给编译的内存      | `MemTotal − 8 GiB`（系统 + page cache） | 54 GiB                                          |
| 单编译进程峰值      | 保守 2 GiB（链接阶段；重模板能到 3~4）            | 2 GiB                                           |
| 并发编译进程上限     | 内存 / 2 GiB                          | ≈ 25~27                                         |
| 标称并发         | CPU 核数的 1.5~2 倍，但不超过「内存上限 × 4」      | 16 × 8 = 128                                    |
| 重 recipe 降并行 | 单独 `-j4`                            | gcc / llvm / nodejs / rust / qtbase / libstdc++ |

代入后就是 `BB_NUMBER_THREADS = "16"` + `PARALLEL_MAKE = "-j 8"`，再对内存大户做 `pn-` 覆盖。什么时候该改：

- `vmstat 5` 的 `us+sy` 长期 < 60% → BB 偏小，加到 20~24  
  |  |  |  
  | --- | --- |
- `dmesg -T | grep -i oom` 出现 → 先降 BB 到 12，再降 `PARALLEL_MAKE` 到 `-j6`，别动 `pn-` 覆盖
- 8 核 / 16 GiB 的机器 → BB=6、PM=`-j4`，否则必 OOM

**必须配 `BB_DISKMON_DIRS`**：磁盘写满时 bitbake 默认会继续写到失败，留下的半截 sstate 会污染后续构建。注意第二列是**剩余 inode 数**，单位 K：

```conf
BB_DISKMON_DIRS = "STOPTASKS,${TMPDIR},2G,100K STOPTASKS,${DL_DIR},2G,100K \
  STOPTASKS,${SSTATE_DIR},2G,100K HALT,${TMPDIR},500M,10K HALT,${DL_DIR},500M,10K HALT,${SSTATE_DIR},500M,10K"
```

写成 `1G` 等于要求 10 亿个 inode，永远超限。

### 4.4 可观测性（强烈建议开）

```conf
INHERIT += "buildhistory"
BUILDHISTORY_COMMIT = "1"
```

回归时 `diff` 两次构建的 rootfs 差异，比人眼靠谱。`site.conf` / `auto.conf` 用于团队共享配置，个人临时改动留在 `local.conf`；两者都存在时别在两边写同一个变量。

---

## 5. BSP 与 meta 层选型

### 5.1 三条路线

**方案 A：上游 poky + meta-rockchip（本仓库主线）**

- 分层干净：`poky`（发行版）+ `meta-rockchip`（BSP）+ `meta-lubancat`（板级差异）+ 可选 `meta-realtime`。
- scarthgap 的 `meta-rockchip` 已经是「Rockchip BSP 化」的：默认内核就是 `linux-rockchip 6.1`（不是 `linux-yocto`），默认 U-Boot 是 Rockchip 2017.09 fork，内置 `rkbin` 与 `make.sh` 打包流程。
- 缺点：只提供 EVB 式 machine，**没有** LubanCat 板级支持（`conf/machine/` 里 rk3588 只有 EVB）。板级支持要自己写——这正是 `meta-lubancat` 的职责。

**方案 B：厂商 SDK 的 `RK_YOCTO` 开关**

野火 `LubanCat_Linux_SDK` 里有 `RK_YOCTO`，但默认 `# RK_YOCTO is not set`——即厂商没把 Yocto 路径作为交付选项验证过。同类厂商走 manifest，版本多停在 kirkstone（4.0）。适用场景：必须复用只存在于 SDK 的闭源件，且能接受 kirkstone。

**方案 C：完全自研**（poky + 自己写 u-boot/kernel recipe）

只有需要「完全掌控打包流程」时才值得。工作量是 A 的 3 倍以上，且会重新踩一遍 `make.sh`、idblock 偏移、FIT 体积这些坑。

### 5.2 对比矩阵

| 维度            | A 上游 meta-rockchip                       | B 厂商 SDK             | C 自研 |
| ------------- | ---------------------------------------- | -------------------- | ---- |
| Yocto 版本      | **scarthgap 5.0 LTS**                    | kirkstone 4.0        | 自选   |
| 内核            | linux-rockchip 6.1（BSP，可换 LubanCat fork） | SDK 内 6.1/5.10       | 自选   |
| U-Boot        | 2017.09 fork + rkbin + make.sh           | SDK 内同源              | 自己接  |
| 闭源件完备度        | 中（GPU/NPU recipe 有，版本不保证）                | 高                    | 靠自己  |
| LubanCat 板级支持 | 无，需自建（本层约 100 行配置 + extboot）             | 有（要开 `RK_YOCTO` 并验证） | 全靠自己 |
| 升级路径          | 清晰（换 Yocto LTS）                          | 跟随厂商 SDK             | 自己维护 |
| 复现性           | 高（层 + SHA 可钉）                            | 中（repo manifest）     | 高    |

### 5.3 结论：A 为主线，B 只做「零件仓库」

- 主线用 A，把「LubanCat 与 EVB 的差异」全部收进 `meta-lubancat`。
- 需要 GPU/NPU 时，从 meta-rockchip 取 `rockchip-libmali` / `rockchip-librga` / `rockchip-npu` / `mali.inc`，而不是整体切到 B。
- 只有某个闭源件在 meta-rockchip 里确实缺失、且 SDK 里有，才把那个 `.deb`/`.so` 单独包成 recipe 放进本层。

---

## 6. meta-lubancat 设计与机器配置

### 6.1 文件树

```
yocto-meta-lubancat/
├── kas/{lubancat.yml, lubancat.lock.yml, realtime.yml}
├── build-conf/local.conf.sample
├── scripts/{host-deps,fetch-layers,setup-mirror,make-updateimg,flash-emmc}.sh
├── tools/rkpack/{afptool, rkImageMaker, SHA256SUMS}
├── docs/{manual.md, realtime.md, boot-artifacts.md, VERSION-MATRIX.md, repo-strategy.md}
├── meta-realtime/
│   ├── conf/layer.conf                                    # priority 15
│   └── recipes-kernel/linux/{linux-rockchip_6.1.bbappend, files/lubancat-realtime.cfg}
└── meta-lubancat/
    ├── conf/layer.conf                                    # priority 10
    ├── conf/machine/lubancat-{4-v1,rk3528,rk3562,rk3566,rk3568,rk3576,rk3588}.conf
    ├── conf/machine/include/lubancat-rk{3528,3562,3566,3568,3576,3588}.inc
    ├── classes/lubancat-image.bbclass
    ├── wic/lubancat-gptdisk.wks.in
    ├── recipes-kernel/linux/linux-rockchip_6.1.bbappend
    │   └── files/{lubancat-family.cfg, 0001-…hdmi0-vp0.patch, 0002-wifi-out-of-tree-paths.patch}
    ├── recipes-kernel/linux-firmware/linux-firmware_%.bbappend   # 切出 -rtw89 固件子包
    ├── recipes-bsp/u-boot/{u-boot-rockchip.bbappend, files/rk*-lubancat.cfg}
    ├── recipes-bsp/extboot/extboot-image.bb               # boot-ext2.img
    ├── recipes-core/images/lubancat-image-{minimal,net,full}.bb
    ├── recipes-core/packagegroups/packagegroup-lubancat-{base,net}.bb
    ├── recipes-core/lubancat-firstboot/                   # 扩容 + 切板
    └── recipes-connectivity/lubancat-netconfig/            # systemd-networkd + wpa_supplicant
```

### 6.2 层职责边界：只放「差异」

本层相对上游 BSP 的真实差异只有六件事，别的一律 `require`：

1. 内核源换 `LubanCat/kernel.git`（分支与 SRCREV 抽成 `LUBANCAT_KERNEL_BRANCH` / `LUBANCAT_KERNEL_SRCREV` 两个弱赋值，RT 层只覆盖这两个变量）。
2. U-Boot / rkbin 源换 `LubanCat/u-boot.git:main` + `LubanCat/rkbin.git:master`。
3. WKS：**去掉 trust 分区**、固定 rootfs `PARTUUID`。
4. 板级 dts、`UBOOT_MACHINE`、`KBUILD_DEFCONFIG`、DDR bin 档位。
5. extboot：`boot-ext2.img`（boot 分区从 FIT 单包改成 ext2 + dtb/dtbo/uEnv 文件）。
6. 首次启动两件事：rootfs 扩容、按 ADC 板卡 ID 切 dtb/uEnv。

### 6.3 `lubancat-rk3588.inc` 逐项说明

```conf
require conf/machine/include/rk3588.inc
```

这一句就拿到了：`cortexa76/cortexa55` tune、`KERNEL_IMAGETYPE ?= "Image"`、`SERIAL_CONSOLES ?= "1500000;ttyFIQ0"`、`PREFERRED_PROVIDER_virtual/{kernel,bootloader}`、`PREFERRED_VERSION_linux-rockchip ?= "6.1%"`、`MALI_GPU="valhall-g610"`、`RK_ISP_VERSION`。**不要复制这些值**，复制了就等着上游改默认而你不动。

```conf
MACHINEOVERRIDES =. "lubancat:lubancat-rk3588:lubancat-rk3588s:"
```

刻意不动 `SOC_FAMILY`：meta-rockchip 内部用 `:rk3588` 做 override，改它会把那套 override 打断。用 `MACHINEOVERRIDES` 追加自己的层级最安全。

```conf
KBUILD_DEFCONFIG = "lubancat_linux_rk3588_defconfig"
SERIAL_CONSOLES = "1500000;ttyFIQ0"
SERIAL_CONSOLES_CHECK = "${SERIAL_CONSOLES}"
```

`KBUILD_DEFCONFIG` **必须覆盖**：`rk3588.inc` 给的是 `rk3588_linux_defconfig`，那份不带 fiq-debugger console，结果是「根挂上了、串口一片空白」。串口那两行上游默认值恰好正确，这里显式写死当**契约**：上游哪天改默认值，你在自己层里能看到差异，而不是某天镜像突然没了 `login:`。


```conf
LUBANCAT_RKBIN_INI ?= "RK3588MINIALL.ini"
LUBANCAT_DDR_BIN ?= "rk3588_ddr_lp4_1848MHz_lp5_2112MHz_v1.19.bin"
```

`LubanCat/rkbin` 的 ini 默认指向该 SoC 的最高档（RK3588 是 lp4 2112 / lp5 2400），而 LubanCat 全系 RK3588 板卡的 LPDDR4X 定型频点是 **1848MHz**。`u-boot-rockchip.bbappend` 在 `do_compile:prepend` 里把 ini 的 `Path1` 与 `FlashData`（后者才是真正打进 loader 的那份）一起改写成 `LUBANCAT_DDR_BIN`，再断言该 bin 在 rkbin 里存在。把「配错 DDR」从「板上假死、串口无输出」变成「编译期一行报错」，就是这两个变量的全部意义——细节与实测见 §8.7。

extboot 相关的族级变量（六族同名同义，勿改名）：

| 变量                                        | 作用                                      | 谁给         |
| ----------------------------------------- | --------------------------------------- | ---------- |
| `LUBANCAT_FAMILY`                         | 选 `files/<family>-lubancat.cfg`，也是产物命名  | 族 inc      |
| `LUBANCAT_CPU_SYMBOL`                     | 断言内核 `CONFIG_CPU_<x>=y`，决定 overlay 门控   | 族 inc      |
| `LUBANCAT_DTB`                            | 拷成 boot 分区 `/rk-kernel.dtb` 的那份         | 板级 conf 覆盖 |
| `LUBANCAT_UENV_DIR` / `LUBANCAT_UENV`     | 取内核树里的 uEnv 模板                          | 板级 conf 覆盖 |
| `LUBANCAT_CMDLINE`                        | uEnv 的 `cmdline=` 行，**必须含 `1500000n8`** | 族 inc      |
| `LUBANCAT_UBOOT_FRAGMENT`                 | 追加 `configs/<name>`，只有 rk3566 非空        | 族 inc      |
| `LUBANCAT_UBOOT_CFG`                      | 传给 `make.sh` 的板名（= `RK_SOC_FAMILY`）     | 族 inc      |
| `LUBANCAT_RKBIN_INI` / `LUBANCAT_DDR_BIN` | DDR 档位改写与断言的依据                          | 族 inc      |

### 6.4 `lubancat-4-v1.conf`

```conf
require conf/machine/include/lubancat-rk3588.inc

# 不要加 vfat：MACHINE_FEATURES 里的 vfat 会让 poky 往 KERNEL_FEATURES 追加
# cfg/fs/vfat.scc，而 linux-rockchip 不是 linux-yocto，没有那份 kernel-cache 元数据
MACHINE_FEATURES = "usbhost usbgadget alsa screen ext2"

KERNEL_DEVICETREE = "rockchip/rk3588s-lubancat-4-v1.dtb"
UBOOT_MACHINE = "rk3588_defconfig"

LUBANCAT_DTB = "rk3588s-lubancat-4-v1.dtb"
LUBANCAT_UENV_DIR = "rk3588"
LUBANCAT_UENV = "uEnvLubanCat4-V1.txt"
```

四个易错点：

- **`KERNEL_DEVICETREE` 的 `rockchip/` 前缀不能省**。`linux-rockchip.inc` 会把它求值成  
  `KERNEL_IMAGETYPE_FOR_MAKE = rk3588s-lubancat-4-v1.img`，再由 Rockchip 内核的 `%.img` 规则把  
  kernel + dtb 打包成 `boot.img`。前缀写错 → `boot.img` 不生成 → wic 的 boot 分区为空  
  （extboot 布局不受影响，它直接用 deploy 里的 `Image` 与 `dtb/`）。
- **`MACHINE` 不要带下划线**。Yocto 会把 `MACHINE` 拼进 override 与包名，下划线在部分上下文里会被规范化成连字符，导致 `VAR:my_board` 永远不匹配。  
  |  |  |  
  | --- | --- |
- `UBOOT_MACHINE` 的合法值以**实查**为准：`ls configs | grep rk35xx`。`evb-rk3588_defconfig` 是 mainline 命名，Rockchip 2017.09 fork 里是 `rk3588_defconfig`（`LubanCat/u-boot main` 已确认存在，自带 `CONFIG_BAUDRATE=1500000`）。
- `LUBANCAT_DTB` 必须是 deploy 目录 `dtb/` 里真实存在的文件，否则 `extboot-image` 会 `bbfatal`。

### 6.5 多系列扩展（模板化）

| 系列                | include               | `UBOOT_MACHINE`                              | 内核 defconfig                      | 默认 dtb                        | 关键差异                                    |
| ----------------- | --------------------- | -------------------------------------------- | --------------------------------- | ----------------------------- | --------------------------------------- |
| `lubancat-4-v1`   | `lubancat-rk3588.inc` | `rk3588_defconfig`                           | `lubancat_linux_rk3588_defconfig` | `rk3588s-lubancat-4-v1.dtb`   | 板级别名，不切板；gmac1 在 `fe1c0000`             |
| `lubancat-rk3588` | 同上                    | `rk3588_defconfig`                           | 同上                                | `rk3588-lubancat-generic.dtb` | 族镜像，首启切板                                |
| `lubancat-rk3576` | `lubancat-rk3576.inc` | `rk3576_defconfig`                           | `lubancat_linux_rk3576_defconfig` | `rk3576-lubancat-generic.dtb` | DDR 只有 lp4 2112 / lp5 2736 一档           |
| `lubancat-rk3568` | `lubancat-rk3568.inc` | `rk3568_defconfig`                           | `lubancat_linux_rk356x_defconfig` | `rk356x-lubancat-generic.dtb` | 必须覆盖 `CONFIG_LOADER_INI`（见下）            |
| `lubancat-rk3566` | `lubancat-rk3566.inc` | `rk3568_defconfig` + `configs/rk3566.config` | 同上                                | `rk356x-lubancat-generic.dtb` | 无 `rk3566_defconfig`；共用 rk356x 的 dtb 目录 |
| `lubancat-rk3562` | `lubancat-rk3562.inc` | `rk3562_defconfig`                           | `lubancat_linux_rk3562_defconfig` | `rk3562-lubancat-generic.dtb` | 3 份板级 dtb                               |
| `lubancat-rk3528` | `lubancat-rk3528.inc` | `rk3528_defconfig`                           | `lubancat_linux_rk3528_defconfig` | `rk3528-lubancat-generic.dtb` | 上游无 `rk3528.inc`，本层自拼                   |

四个必须知道的差异：

- **RK3566 没有 `rk3566_defconfig`**。官方组合是 `rk3568_defconfig` + `configs/rk3566.config`（后者只有两行：`CONFIG_BASE_DEFCONFIG` 与 `CONFIG_LOADER_INI`）。层里用 `LUBANCAT_UBOOT_FRAGMENT = "rk3566.config"` 把它并进 defconfig。
- **没有 `CONFIG_CPU_RK3566`**。rk3566 与 rk3568 的 dtb、overlay 全挂在 `CONFIG_CPU_RK3568` 下，所以两族 `LUBANCAT_CPU_SYMBOL` 都是 `RK3568`，但 `UBOOT_MACHINE` 与 DDR bin 必须分开。这也是 rk3568 的 boot 分区里有 16 份 dtb（9 份 3568 + 6 份 3566 + generic）的原因。
- **`rk3568_defconfig` 的 `CONFIG_LOADER_INI` 是 `RK3566MINIALL.ini`**（内含 rk3566 的 1056 档 DDR bin）。做 rk3568 时必须覆盖成 `RK3568MINIALL.ini`，否则表现是「一行都不打印的假死」。覆盖点在本族的 `files/rk3568-lubancat.cfg`。
- **meta-rockchip 没有 `rk3528.inc`**（scarthgap 只有 rk3506 / rk3562 / rk356x / rk3576 / rk3588），本层自带一份：`armv8a/tune-cortexa53` + `rockchip-common.inc` + `mali.inc`。

新增一族的最小改动集：一个 `conf/machine/include/lubancat-<soc>.inc`（约 40 行，含 `KBUILD_DEFCONFIG`、串口、DDR、extboot 变量）+ 一个 `conf/machine/lubancat-<soc>.conf`（约 5 行）+ 一份 `files/<family>-lubancat.cfg`（U-Boot 能力 + `CONFIG_LOADER_INI`）。

---

## 7. 内核定制与「必须实测」清单

### 7.1 为什么必须换内核源

上游 `meta-rockchip` 的 `linux-rockchip_6.1.bb` 拉的是 `JeffyCN/mirrors` 的 `kernel-6.1-2024_04_14`。那棵树里：

- 没有 `arch/arm64/configs/lubancat_linux_rk3588_defconfig`（六族都没有）
- 没有 `arch/arm64/boot/dts/rockchip/rk35xx-lubancat-*.dts`
- 没有 LubanCat 对 `rk3588s.dtsi` / `rk3588-linux.dtsi` 的板级改动
- 没有 `arch/arm64/boot/dts/rockchip/uEnv/`（extboot 的 `boot.cmd` 与 30 份 uEnv 模板都在里面）

所以 `KBUILD_DEFCONFIG` 会直接找不到，`do_kernel_metadata` 失败。换源是硬需求。

### 7.2 bbappend 写法（当前版本）

```conf
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# 分支与 SRCREV 抽成弱赋值：RT 层只覆盖这两个变量，不重写 SRC_URI
LUBANCAT_KERNEL_BRANCH ?= "lbc-develop-6.1"
LUBANCAT_KERNEL_SRCREV ?= "a0c672347152a0ea0713a043f1d1c4ec4323ff93"

SRC_URI = "git://github.com/LubanCat/kernel.git;protocol=https;branch=${LUBANCAT_KERNEL_BRANCH}"
SRCREV  = "${LUBANCAT_KERNEL_SRCREV}"

LINUX_VERSION = "6.1.99"
LINUX_VERSION_EXTENSION = "-lubancat"
KERNEL_FEATURES:forcevariable = ""

SRC_URI += "file://lubancat-family.cfg"
SRC_URI += "file://0001-arm64-dts-lubancat-4-v1-enable-hdmi0-vp0.patch"
SRC_URI += "file://0002-wifi-out-of-tree-paths.patch"
```

五个点：

1. `SRC_URI` 用 `=` 整份替换。用 `+=` 会把上游 recipe 里 `require linux-yocto.inc` 带进来的源一起拉，并且 `SRCREV` 会出现 `SRCREV_<name>` 未定义。
2. **不要**在 RT 层整份重写 `SRC_URI`——那会把 `lubancat-family.cfg` 与两个补丁一起丢掉。覆盖方用强赋值改 `LUBANCAT_KERNEL_*` 即可。
3. `.cfg` 放进 `SRC_URI` 就会被 kernel-yocto 自动合并，**不需要** `KERNEL_CONFIG_FRAGMENTS`；合并顺序按 SRC_URI 顺序，**最后一份生效**（这是 RT 层 priority 必须高于 lubancat 的原因之一）。
4. `KERNEL_FEATURES:forcevariable = ""` 必须带 `forcevariable`：普通 `=` 会被 kernel-yocto 的 `+=` 追回来，然后它去 meta 分支找 `.scc`（LubanCat fork 没有）而失败。
5. 整份替换 SRC_URI 的副作用：上游 `cgroups.cfg` / `ext4.cfg` 也没了。`lubancat-family.cfg` 里已经把 ext4 相关项补回来。

`lubancat-family.cfg` 的定位不是完整配置（完整配置由 `lubancat_linux_<soc>_defconfig` 提供），只写「缺了就起不来 / 起得来但看不到、连不上 / dtbo 挂不上」的项：`CONFIG_DTC_SYMBOLS`（overlay 的 `__symbols__` 前提）、fiq-debugger 三项、`STMMAC/DWMAC/REALTEK_PHY`、`NFS_FS/ROOT_NFS/IP_PNP`、`MMC_*`、ext4 五项、`RK806/RK860X`、无线相关（§7.7）。

### 7.3 `KBUILD_DEFCONFIG` 选哪个

| 选项                               | 有无 FIQ console | 后果                                |
| -------------------------------- | -------------- | --------------------------------- |
| `lubancat_linux_<soc>_defconfig` | **有**          | 串口有内核日志、有 `login:`                |
| `rockchip_linux_defconfig`       | 通常无            | 能挂根、能启动，但**串口一片空白**，最容易被误判成「内核崩了」 |

选 LubanCat 的。`linux-rockchip.inc` 的 `do_kernel_metadata:prepend` 有个兜底：若 `KBUILD_DEFCONFIG` 文件不存在，会尝试把 `rockchip_linux_defconfig` + `<soc>_linux.config` 拼出来。这正是「照抄别人的 `rockchip_linux_defconfig`」时悄悄发生的事——不报错，只是丢了 FIQ console。

`rk3576.inc` / `rk3562.inc` / `rk356x.inc` 都没设 `KBUILD_DEFCONFIG`，会落到 `rockchip-common.inc` 的 `rockchip_linux_defconfig`，所以六族 inc 里都显式覆盖了。

### 7.4 dts 落地三种方案

| 方案              | 做法                                                                                                                                   | 适用                                   |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------ |
| **A 用内核自带 dts** | `KERNEL_DEVICETREE = "rockchip/<board>.dtb"`                                                                                         | **默认，本仓库全部走这条**                      |
| B 把 dts 拷进内核树   | bbappend 里在 `do_configure` 之后拷到 `${B}/arch/arm64/boot/dts/rockchip/`，并往该目录 `Makefile` 追加 `dtb-$(CONFIG_ARCH_ROCKCHIP) += <name>.dtb` | 自研板                                  |
| C 打补丁           | 把 dts + Makefile 改动做成 `.patch` 进 `SRC_URI`                                                                                           | 要长期维护、要 code review（本层的 HDMI 补丁就是这条） |

方案 B 的关键细节：**必须同时改 Makefile**。只拷文件不改 Makefile，表现为 `No rule to make target 'rockchip/<name>.dtb'`，报错点离真实原因很远：

```python
do_configure:append() {
    install -m 0644 ${WORKDIR}/myboard.dts ${B}/arch/arm64/boot/dts/rockchip/
    grep -q 'myboard.dtb' ${B}/arch/arm64/boot/dts/rockchip/Makefile || \
        echo 'dtb-$(CONFIG_ARCH_ROCKCHIP) += myboard.dtb' >> ${B}/arch/arm64/boot/dts/rockchip/Makefile
}
```

板级 dts 少 include 时不要用 B 方案糊——那是上游 dts 的缺陷，做成 4 行 patch（方案 C）最省事，本层的 HDMI 使能就是这样修的（§12.19）。

### 7.5 「必须实测、不能照抄」的 8 条

|   |   |
| - | - |

1. `ls configs/ | grep rk35xx`——`rk3588_defconfig` 与 `evb-rk3588_defconfig` 到底有哪些。
2. `ls build/tmp/deploy/images/<machine>/` 里有没有 `trust.img`、有没有 `boot.img`。FIT 流程预期**无 trust**，照抄上游 wks 必失败。
3. `make.sh` 在 `destsuffix=rkbin` 布局下能否找到 `../rkbin/tools`（报 `ERROR: No ../rkbin repository` 就是这里）。  
   |  |  |  |  
   | --- | --- | --- |
4. `strings idblock.img | grep -iE 'ddr|^typ'`——实际进 loader 的 DDR bin 是哪一档。
5. `--offset 2M` 的 `uboot.img` 在 eMMC+GPT 下是否与分区表冲突（`sgdisk -v` 检查重叠）。
6. `ttyFIQ0` 上 systemd 是否自动拉起 `serial-getty@ttyFIQ0`。
7. `/chosen bootargs` 与 U-Boot `bootargs` 环境变量的合并优先级（Rockchip 有专门的 `env_update()` 按键名合并，不是简单覆盖）。
8. `uboot.img` 里 `cmd/dtfile.o` 是否编出——uEnv 的 `dtoverlay=` 全靠它（`strings` 判断不可靠，见 §8.4）。

### 7.6 设备树能不能动态切换？overlay 怎么配？

**结论**：`boot.img`（Rockchip 私有 FIT 单包）里只打一个 dtb，所以**一份 boot.img 换不了设备树**；`mkimg --dtb` 只接受一个 dtb。本仓库的做法是把 boot 分区改成 ext2 文件系统（extboot，第 14 章），dtb/dtbo/uEnv 都变成文件，运行时按需切换。

三条路线的取舍：

| 路线                        | 做法                                                                                                                                           | 换 dtb 的代价   | 现状                   |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ----------- | -------------------- |
| **A 多份 boot.img**         | 每份 dtb 编一个 `boot.img`，U-Boot 里 `ext4load` 选                                                                                                  | 换文件         | 未采用（同板不同外设配置时可用）     |
| **B extboot**（厂商做法，本仓库默认） | boot 分区 ext2 放 `Image` + `rk-kernel.dtb` + `dtb/` + `dtb/overlay/` + `uEnv/`，U-Boot 的 `distro_bootcmd` 扫 `boot.scr`，`dtfile` 应用 `dtoverlay=` | 替换分区里的文件    | **已实现并上板验证**，见第 14 章 |
| **C FIT 多 configuration** | 一个 FIT 里放多个 dtb + 多个 `conf-`，`bootm <addr>#conf-<name>`                                                                                      | 改 U-Boot 变量 | 不需要（B 已覆盖）           |

overlay 的两个前提：

| 前提                                                       | 状态 | 说明                                                                                               |
| -------------------------------------------------------- | -- | ------------------------------------------------------------------------------------------------ |
| 基础 dtb 带 `__symbols__`（`dtc -@`）                         | ✅  | Rockchip 用私有符号 `CONFIG_DTC_SYMBOLS=y` 打开 `DTC_FLAGS += -@`，已写进 `lubancat-family.cfg`             |
| U-Boot 能 `fdt apply`                                     | ✅  | `CONFIG_CMD_FDT=y` + `CONFIG_OF_LIBFDT_OVERLAY=y`，六族 cfg 都钉死了                                    |
| 运行期 configfs（`/sys/kernel/config/device-tree/overlays/`） | ❌  | `CONFIG_OF_OVERLAY` 未开，且这棵树没有 `drivers/of/configfs.c`。**不要指望热插拔式加载**，要么 U-Boot 阶段 apply，要么重编 dtb |

所以 overlay 的实际使用方式只有一种：**写进 `uEnv.txt` 的 `dtoverlay=` 行，U-Boot 启动时 apply**（§14.6）。想省掉 U-Boot 这一层就把差异写进板级 dts 的 `#include`（编译期合并，零运行时风险，代价是换配置要重打 boot 分区）。


### 7.7 无线网卡：芯片 → 驱动 → 固件 → 自动加载

M.2 位换卡很随意，同一套镜像要能认多颗芯片。先分清两条路线，混着调只会浪费时间：

| 路线       | 适用                           | 驱动在哪                                                 | 固件在哪                                |
| -------- | ---------------------------- | ---------------------------------------------------- | ----------------------------------- |
| vendor 树 | SDIO / USB 模组（8189FS、8821CU） | `drivers/net/wireless/rockchip_wlan/`                | meta-rockchip 的 `rkwifibt-firmware` |
| 内核主线     | PCIe（M.2）模组                  | `drivers/net/wireless/realtek/{rtlwifi,rtw88,rtw89}` | `linux-firmware`                    |

现场测的四颗**全是 PCIe**，走主线：

| 芯片        | 驱动             | 内核配置（`lubancat-family.cfg`）                | 模块名            | 固件文件                      | 固件包                      |
| --------- | -------------- | ------------------------------------------ | -------------- | ------------------------- | ------------------------ |
| RTL8188CE | `rtl8188ee`    | `CONFIG_RTL8188EE=m`                       | `rtl8188ee`    | `rtlwifi/rtl8188efw.bin`  | `linux-firmware-rtl8188` |
| RTL8822CE | `rtw88_8822ce` | `CONFIG_RTW88=m` + `CONFIG_RTW88_8822CE=m` | `rtw88_8822ce` | `rtw88/rtw8822c_fw.bin`   | `linux-firmware-rtl8822` |
| RTL8851BE | `rtw89_8851be` | `CONFIG_RTW89=m` + `CONFIG_RTW89_8851BE=m` | `rtw89_8851be` | `rtw89/rtw8851b_fw.bin`   | `linux-firmware-rtw89`   |
| RTL8852BE | `rtw89_8852be` | `CONFIG_RTW89=m` + `CONFIG_RTW89_8852BE=m` | `rtw89_8852be` | `rtw89/rtw8852b_fw-1.bin` | `linux-firmware-rtw89`   |

**为什么不走 vendor 树**：vendor 树里没有 8188CE / 8822CE 的驱动；8851BE / 8852BE 虽然有，但与主线 `rtw89` 抢同一个 PCI ID（`10ec:b852` 两个模块都声明），只能二选一，而且它要 Android 风格固件路径（`<CONFIG_FIRMWARE_PATH>/rtl8852b/RTL8852Bfw.bin`），linux-firmware 里没有。要用 vendor 版就把 cfg 里 `CONFIG_RTL8851BE=m` / `CONFIG_RTL8852BE=m` 打开、同时关掉对应 `RTW89_*`，再自己放固件。

**`rtw88` / `rtw89` 是 menuconfig**，子驱动在 `if RTW88` / `if RTW89` 里面。只写 `CONFIG_RTW89_8852BE=m` 不写 `CONFIG_RTW89=m`，`olddefconfig` 会把它清掉——这是最容易漏的一步。另外 `CONFIG_WL_ROCKCHIP=y` 要留着：它 select `CFG80211/MAC80211`，而主线 rtw88/rtw89 是 `depends on MAC80211`。

#### 7.7.1 固件包：别装主包，会拖进整棵固件树

`linux-firmware` 的 recipe 末尾是 `FILES:${PN} += "${nonarch_base_libdir}/firmware/*"`，意思是**没被任何子包认领的固件全部落进主包**（几百 MB）。poky 里已有 `-rtl8188`（`rtlwifi/rtl8188*.bin`）和 `-rtl8822`（`rtw88/rtw8822*.bin`），但**没有 rtw89**，所以本层补了一个：

```bitbake
# meta-lubancat/recipes-kernel/linux-firmware/linux-firmware_%.bbappend
PACKAGE_BEFORE_PN += "${PN}-rtw89"
LICENSE:${PN}-rtw89 = "Firmware-rtlwifi_firmware"
FILES:${PN}-rtw89 = "${nonarch_base_libdir}/firmware/rtw89/*.bin"
RDEPENDS:${PN}-rtw89 += "${PN}-rtl-license"
```

用 `PACKAGE_BEFORE_PN` 而不是 `PACKAGES =+`：后者会把新包排在 `${PN}` **之后**，而文件分配是「按 PACKAGES 顺序先匹配先得」，排在主包后面等于抢不过兜底规则。

#### 7.7.2 `KERNEL_MODULE_AUTOLOAD`：名字必须是 .ko 的 basename

写在**内核 recipe** 里（不是镜像、不是 packagegroup），由 `kernel-module-split` 消费：它在对应的 `kernel-module-<mod>` 包里生成 `<modules-load.d>/<mod>.conf`，所以只有该模块包被装进 rootfs 才生效。

```bitbake
KERNEL_MODULE_AUTOLOAD += "rtl8188ee rtw88_8822ce rtw89_8851be rtw89_8852be"
```

PCIe 卡靠 udev 的 modalias 本来也能自动加载，显式写出来是为了开机顺序确定、`journalctl` 里能看出是谁加载的。插着哪张卡就只 bind 哪张，其余模块加载后找不到设备会自己退出。

#### 7.7.3 模块包名：下划线会被换成短横线

`kernel-module-split` 生成包名时会取 `.ko` 的 basename，**把 `_` 全换成 `-`**，前面加 `kernel-module-`：

```
rtw88_8822ce.ko → kernel-module-rtw88-8822ce
rtw89_8852be.ko → kernel-module-rtw89-8852be
rtl8188ee.ko    → kernel-module-rtl8188ee     （本来没下划线，不变）
```

写 `kernel-module-rtw88_8822ce` 解析不到任何包，报错是：

```
Solver encountered 1 problem(s):
  - nothing provides kernel-module-rtw88_8822ce needed by packagegroup-lubancat-net-1.0-r0.all
```

**这个报错极易误判成「驱动没编出来」**——实际模块早已编好并拆分完成，只是名字对不上。快速区分：

```bash
ls tmp/work/*/linux-rockchip/*/packages-split | grep -E 'rtw8|rtl8' | sort
```

有 `kernel-module-rtw88-8822ce-6.1.99-lubancat` 就是名字问题；一个都没有才是配置问题（回去看 `CONFIG_RTW88_*`）。

两套名字故意不一样，别混：

| 场景                                               | 写法  | 例子                           |
| ------------------------------------------------ | --- | ---------------------------- |
| 包依赖（`RDEPENDS` / `RRECOMMENDS`）                  | 短横线 | `kernel-module-rtw88-8822ce` |
| 模块名（`KERNEL_MODULE_AUTOLOAD`、`modprobe`、`lsmod`） | 下划线 | `rtw88_8822ce`               |

模块之间的依赖（`rtw88-8822c` / `rtw88-pci` / `kernel`）由 `kernel-module-split` 按 `modinfo` 的 `depends` 自动写进 `RDEPENDS`，**只列最上层那个驱动就行**。

#### 7.7.4 上板验证顺序

```bash
# 1. 模组有没有被 PCI 枚举出来（没有就是供电/插槽/白名单问题，先别怪驱动）
lspci -nn | grep -i -E 'network|802\.11'

# 2. 模块加载了吗、固件读到了吗
lsmod | grep -E 'rtw89|rtw88|rtl8188'
dmesg | grep -i -E 'rtw89|rtw88|rtl8188|firmware'

# 3. 网络接口出来了吗（本层用 .link 钉回 wlan0，见 7.7.5）
ip link | grep -E '^[0-9]+: wl'

# 4. 固件到底在不在（路径要和驱动请求的完全一致）
modinfo -F firmware rtw89_8852be
ls -l /lib/firmware/rtw89/
```

| 现象                                                        | 原因                        | 处置                                                           |
| --------------------------------------------------------- | ------------------------- | ------------------------------------------------------------ |
| `Direct firmware load for rtw89/rtw8852b_fw-1.bin failed` | 固件包没装，或文件名对不上（`-1` 后缀不能省） | 装 `linux-firmware-rtw89`，用 `modinfo -F firmware` 对照          |
| `ip link` 里没有 `wlan0`，但 `lsmod` 有驱动                       | 固件没加载成功，驱动 probe 后退出      | 看 `dmesg` 里紧跟 `fw failed` 的那几行                               |
| 只有 2.4G 能扫到，5G 空                                          | 没设监管域                     | `iw reg set CN`，或装 `wireless-regdb-static` 后 `iw reg get` 确认 |

改了 cfg 或 bbappend 之后内核会重编，但 `.ko` 要等 `do_compile_kernelmodules`；只想验证驱动能不能编，用 §12.17 的 `make -C $S O=$B drivers/net/wireless/realtek/`，几分钟，不用等整个镜像。

#### 7.7.5 节点名不是 `wlan0`、也没有 `lspci`：两件容易误判成「驱动坏了」的事

实测一块插着 RTL8822CE 的板子：

```bash
$ lspci -nn | grep 802.11
-sh: lspci: not found                      # ① 早期镜像没装 pciutils

$ ip link | grep wlan
$ ls /sys/class/net
dummy0  end1  lo  wlP4p65s0                # ② 节点在，只是不叫 wlan0
```

内核日志其实一切正常：

```
rtw_8822ce 0004:41:00.0: enabling device (0000 -> 0003)
rtw_8822ce 0004:41:00.0: Firmware version 9.9.15, H2C version 15
rtw_8822ce 0004:41:00.0 wlP4p65s0: renamed from wlan0      ← 名字是被 udev 改的
```

**① 没有 `lspci` 时怎么确认卡片枚举出来了**——`sysfs` 就是数据源：

```bash
for d in /sys/bus/pci/devices/*; do
  n=$(basename $d)
  echo "$n $(cat $d/vendor):$(cat $d/device) class=$(cat $d/class) \
        driver=$(basename $(readlink $d/driver 2>/dev/null) 2>/dev/null)"
done
# 0004:41:00.0 0x10ec:0xc822 class=0x028000 driver=rtw_8822ce
#                            ^ 0x028000 = 网络控制器   ^ 驱动已绑定
```

`0x028000` 是 PCI class code 里的 network controller，`driver=` 非空就说明驱动 probe 过了。

**② 为什么名字是 `wlP4p65s0`**：systemd-udevd 默认按「可预测网络接口名」改名。本层用 `.link` 文件钉回 `wlan0`：

```ini
# /etc/systemd/network/10-lubancat-wlan.link（配方 lubancat-netconfig）
[Match]
Type=wlan

[Link]
Name=wlan0
```

用 `Type=wlan` 而不是网上常见的 `OriginalName=wlan0`，理由是实测出来的：

| `[Match]` 写法         | 结果                                                        |
| -------------------- | --------------------------------------------------------- |
| `OriginalName=wlan0` | 只有 `99-default.link` 生效，`ID_NET_NAME=wlP4p65s0`（**没匹配上**） |
| `Driver=rtw_*`       | 命中，`ID_NET_NAME=wlan0`，但只覆盖主线 rtw88/rtw89                 |
| `Type=wlan`          | 命中，`ID_NET_NAME=wlan0`，且与驱动无关（SDIO/USB 模组同样适用）            |

`OriginalName` 匹配的是 udev 改名**之前**的内核名，设备一旦被改过名这个键就不成立了；`Type` 读的是 uevent 里的 `DEVTYPE=wlan`。改这类规则先用 `udevadm test-builtin net_setup_link /sys/class/net/<if>` 验证，不用反复烧板。

**③ 能扫 SSID、能连网还缺什么**：`packagegroup-lubancat-net` 已补上最小工具集 `pciutils` / `iw` / `wpa-supplicant` / `wireless-regdb-static`。监管域要装 `-static` 子包（主包只放 crda 用的旧格式 `regulatory.bin`），否则内核只能用 world 域，5GHz 大部分信道不可用——`dmesg` 里那句 `Direct firmware load for regulatory.db failed` 就是它。

#### 7.7.6 连上 wifi 却上不了网：metric 撞车把默认路由吞掉了

现象：`iw dev` 显示已关联、`ip addr` 有地址、`ping` 网关通，但访问外网一律失败，`ip route show default` 里**只有有线那一条**。

**根因不在无线**。有线 `end1` 由 `/usr/lib/systemd/network/80-wired.network` 管理，它写着 `RouteMetric=10`；而手工用 busybox `udhcpc` 配无线时，`/etc/udhcpc.d/50default` 里的 metric 是**写死的 10**：

```sh
metric=10
for i in $router ; do
    /usr/sbin/ip route add default via $i metric $metric dev $interface
    metric=$(($metric + 1))
done
```

同一 `(dst=default, metric)` 在内核里只能有一个 nexthop，于是这句必然失败：`RTNETLINK answers: File exists`。错误被 udhcpc 吞掉（脚本 stderr 不落日志），最终表现是「wlan0 有 IP、却没默认路由」：有线在时全部流量走有线（看起来「wifi 不通」），拔掉网线则一条默认路由都不剩。

**一眼确认**：

```bash
ip route show default
# 只有 end1 那条 → 就是这个问题

ip route add default via <AP网关> dev wlan0 metric 10   # RTNETLINK answers: File exists
ip route add default via <AP网关> dev wlan0 metric 20   # 成功
```

顺带一个常被带偏的细节：**网关要看 DHCP 下发的，不是网段里的 .1**。实测某 AP 的 DHCP 服务器是 `10.169.169.254`，而 `.1` 是另一台带 Web 管理页的设备——往 `.1` 发数据一样出不去，很容易误判成「被强制门户拦了」。

**本层的修法**：无线不再用 udhcpc，交给 systemd-networkd，和有线同一套机制。`lubancat-netconfig` 安装：

```ini
# /etc/systemd/network/50-lubancat-wlan.network
[Match]
Type=wlan

[Network]
DHCP=yes

[DHCPv4]
RouteMetric=100        # 比有线的 10 大 → 有线优先，拔线自动切 wifi
```

外加 `wpa_supplicant@wlan0.service` 的启用和凭据文件 `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`（0600，属 `CONFFILES`，升级镜像不覆盖用户填的 SSID）。

> **别再用 `udhcpc -i wlan0` 手工配**。两个 DHCP 客户端同时在线会互相抢地址；而且它加的默认路由注定装不上。看状态用 `networkctl status wlan0`。

**另一件容易白查半天的事**：凭据文件只写 `ssid` 不写 `psk`，加密网络会被 wpa_supplicant 直接判为无效：

```
wlan0: No enabled networks (1 disabled networks)
wlan0: State: DISCONNECTED -> INACTIVE
```

此时 `systemctl status wpa_supplicant@wlan0` 是 **active**、`iw dev wlan0 scan` 也能扫到十几个 AP，但 `iw dev wlan0 link` 永远是 Not connected——很像「信号弱/驱动不认这个 AP」。加 `-dd` 跑一次才看得见上面那句。

想让 wifi 优先于有线，把 `RouteMetric` 改成比 10 小的值（例如 5）；想两条链路负载分担要配 multipath，别指望改 metric 就自动分流。

### 7.8 PREEMPT_RT 内核（`meta-realtime`）

`meta-realtime` 是可选的第二层，把内核从 `lbc-develop-6.1` 换成 `lbc-develop-6.1-rt36`，**不新增镜像 recipe**，镜像还是那三份。

```bash
KAS_BUILD_DIR=$PWD/build-rt kas build kas/lubancat.yml:kas/realtime.yml

# 换机器 / 换镜像
KAS_MACHINE=lubancat-rk3568 KAS_BUILD_DIR=$PWD/build-rt \
  kas build kas/lubancat.yml:kas/realtime.yml
KAS_TARGET="lubancat-image-net extboot-image" KAS_BUILD_DIR=$PWD/build-rt \
  kas build kas/lubancat.yml:kas/realtime.yml
```

实现方式是**只改两个弱赋值变量**，不重写 `SRC_URI`（否则 `lubancat-family.cfg` 与两个补丁会一起丢）：

```conf
# meta-realtime/recipes-kernel/linux/linux-rockchip_6.1.bbappend
LUBANCAT_KERNEL_BRANCH = "lbc-develop-6.1-rt36"
LUBANCAT_KERNEL_SRCREV = "3d027a80ff4023e4ee6dba24db140a2eab2c1f28"
SRC_URI:remove = "file://0002-wifi-out-of-tree-paths.patch"
SRC_URI += "file://lubancat-realtime.cfg"
```

四条硬约束：

- **`KAS_BUILD_DIR` 不能省**。RT 与非 RT 的 `Image`、`boot-ext2.img`、`dtb/` 在 `deploy/images/<machine>/` 下同名，共用 build 目录会互相覆盖，表现是「刷了 RT 镜像但 `uname -r` 里没有 `-rt36`」。overlay 里 `DL_DIR` / `SSTATE_DIR` 指回主构建共用，只隔离 `TMPDIR`。
- **层优先级必须 15**（> lubancat 的 10）：bbappend 按优先级从低到高应用，且 `lubancat-realtime.cfg` 必须排在 `lubancat-family.cfg` **之后**（kernel-yocto 按 SRC_URI 顺序 merge，最后一份生效）。
- `0002-wifi-out-of-tree-paths.patch` 在 RT 分支打不上（那批 vendor 驱动在 RT 分支没有对应文件），所以 `SRC_URI:remove` 掉；代价是 vendor 树的 SDIO/USB 驱动（8189FS / 8821CU）不可用。主线 `rtw88` / `rtw89` 不受影响，PCIe 卡照常。
- `lubancat-rk3528` 的 defconfig 没有 `PREEMPT_RT`，叠加 overlay 会在 kernel 配置阶段直接 `bb.fatal`。

上板验收与延迟实测、风险与回退见 [`realtime.md`](realtime.md)。最快的两条：

```bash
uname -r                  # 6.1.99-rt36-lubancat
cat /sys/kernel/realtime  # 1
```

`lubancat-realtime.cfg` 里容易踩的两点（细节见 realtime.md §5）：`CONFIG_HZ_PERIODIC=n` 与 `CONFIG_NO_HZ_IDLE=y` 必须**成对**写（二者是 Kconfig choice，只写一行会被 defconfig 的旧值顶回去）；关项一律写 `CONFIG_X=n`，写 `# CONFIG_X is not set` 会被 `merge_config.sh` 当注释删掉。

---

## 8. U-Boot 与 rkbin

### 8.1 `make.sh` 链路与产物

`u-boot-rockchip.bb` 不是标准 `u-boot.inc` 流程，`do_compile` 里会执行 `./make.sh <cfg>`（`cfg` 来自 `LUBANCAT_UBOOT_CFG`，即 `RK_SOC_FAMILY`）。产物与去向：

| 产物            | 内容                                                | 落到哪里                                      |
| ------------- | ------------------------------------------------- | ----------------------------------------- |
| `idblock.img` | DDR bin + SPL（新式 IDB，`CONFIG_ROCKCHIP_NEW_IDB=y`） | wic `--align 32`，即 sector 64（32 KiB）      |
| `uboot.img`   | U-Boot proper（FIT，内含 BL31）                        | wic `--offset 2M`；rkfw 里在 `0x4000`（8 MiB） |
| `loader.bin`  | 软链到 `*_loader*.bin`，MaskROM 下载用                   | `make-updateimg.sh` 的 `MiniLoaderAll.bin` |
| `trust.img`   | 仅非 FIT 流程产出                                       | **本流程没有**（所以 wks 里不写它）                    |

> `make.sh` 里硬编码了 `RKBIN_TOOLS=../rkbin/tools`。recipe 用 `destsuffix=rkbin` 把 rkbin 拉到 `${WORKDIR}/rkbin`，`${S}` 是 `${WORKDIR}/git`，所以 `../rkbin` 正好成立。**改 destsuffix 会直接找不到 rkbin。**

### 8.2 换源

```conf
SRC_URI = " \
    git://github.com/LubanCat/u-boot.git;protocol=https;branch=main \
    git://github.com/LubanCat/rkbin.git;protocol=https;branch=master;name=rkbin;destsuffix=rkbin \
"
SRCREV = "a564b1d927aa6032520819536a5b8c450e8141c4"
SRCREV_rkbin = "74213af1e952c4683d2e35952507133b61394862"
SRCREV_FORMAT = "default_rkbin"
```

`SRCREV_FORMAT` 不能漏：两个 git 源时 bitbake 需要知道哪个 `SRCREV` 对应哪个 URI，`default` 对应没有 `name=` 的那个。

### 8.3 `rk3588_defconfig` 已经替你做好了什么（实测）

| 配置                                                                                | 值                                 | 含义                                |
| --------------------------------------------------------------------------------- | --------------------------------- | --------------------------------- |
| `CONFIG_BAUDRATE`                                                                 | `1500000`                         | 与 LubanCat 一致，**不需要**改成 115200    |
| `CONFIG_DEBUG_UART_BASE`                                                          | `0xFEB50000`                      | UART2，早期调试口直接对                    |
| `CONFIG_SPL_FIT_IMAGE_KB`                                                         | `4096`                            | 已大于曾翻车的 2048                      |
| `CONFIG_ROCKCHIP_FIT_IMAGE_PACK`                                                  | `y`                               | BL31 进 `uboot.img`，不产 `trust.img` |
| `CONFIG_ROCKCHIP_NEW_IDB`                                                         | `y`                               | idblock 新式布局                      |
| `CONFIG_OF_U_BOOT_REMOVE_PROPS`                                                   | 含 `pinctrl-0 … assigned-clocks …` | **坑仍在**（见 8.5）                    |
| `CONFIG_USING_KERNEL_DTB_V2`                                                      | `y`                               | **坑仍在**（见 8.6）                    |
| `CONFIG_DISTRO_DEFAULTS` / `CMD_{PART,EXT2,EXT4,FDT,DTIMG}` / `OF_LIBFDT_OVERLAY` | `y`                               | extboot 的前提，六族 cfg 里都显式钉死了        |

### 8.4 配置片段的正确落地方式

`make.sh` 内部还会 `make <defconfig>`，所以**只改 `${B}/.config` 会被冲掉**。正确做法是把增量追加到源码树的 defconfig 末尾（Kconfig 后者覆盖前者）。

但**不要用 `do_configure:prepend()` 写这段**：`u-boot-rockchip.bb` 已经有一个同名函数体（做 python2→python3 的 sed 与删 make.sh 里的 `make` 行），bbappend 里再定义一次会把上游那份**整段替换掉**，结果 python2 检查回来了、编译直接失败。正确做法是插独立任务：

```python
do_lubancat_uboot_defconfig() {
    cfg="${WORKDIR}/${LUBANCAT_FAMILY}-lubancat.cfg"
    defcfg="${S}/configs/${UBOOT_MACHINE}"

    # 用 marker 去重：同一个 ${S} 上可能多次执行，无脑 cat >> 会越堆越多
    grep -q "LUBANCAT-CFG-BEGIN" "$defcfg" && return 0

    # 1) 官方片段先并入（rk3566.config：CONFIG_BASE_DEFCONFIG / CONFIG_LOADER_INI）
    if [ -n "${LUBANCAT_UBOOT_FRAGMENT}" ]; then
        cat "${S}/configs/${LUBANCAT_UBOOT_FRAGMENT}" >> "$defcfg"
    fi
    # 2) 本族的增量（后写者覆盖前写者，LOADER_INI 在这里改）
    cat "$cfg" >> "$defcfg"
}
addtask lubancat_uboot_defconfig after do_patch before do_configure
```

两个细节不能省：marker 去重；`addtask … before do_configure` 保证它在上游 sed 之后、`make <defconfig>` 之前跑。

|                                                                                                                                                                                                             |                                                                  |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| 另外 `do_compile:append` 里有一条**编译后断言**：uEnv 的 `dtoverlay=` 依赖 Rockchip 私有命令 `dtfile`（挂在 `CONFIG_CMD_FDT` 下，没有独立 Kconfig 符号），判据是 `cmd/dtfile.o` 是否存在 + `.config` 里 `CONFIG_CMD_FDT=y`。**不要**用 \`strings u-boot | grep dtfile`——命令表里的字符串在 ELF 里不一定以独立可打印串出现，而 `uboot.img\` 又是打包过的。 |

### 8.5 坑：`OF_U_BOOT_REMOVE_PROPS` 删掉了 `assigned-clocks`

**症状**：U-Boot 里 `ping` 不通 / `Net: eth1: ethernet@fe1c0000` 之后没下文，串口**一行报错都没有**。

**根因**：该选项会在 U-Boot 自己的设备树里删掉 `pinctrl-0 pinctrl-names clock-names interrupt-parent assigned-clocks assigned-clock-rates assigned-clock-parents`。`assigned-clocks` 没了 → `clk_set_defaults` 不会把 `CLK_GMAC1` 的父时钟切到能整除出 125 MHz 的档位（默认父时钟大概率是 GPLL 1188 MHz）→ `clk_set_rate(125M)` 拿不到精确频率 → 驱动返回 `-EINVAL`，且不打日志。

**修复**：只在真的需要在 U-Boot 用网口（TFTP 拉内核、NFS 调试）时，把 `CONFIG_OF_U_BOOT_REMOVE_PROPS=""` 加进 `rk3588-lubancat.cfg`（默认注释掉）。代价是 U-Boot 设备树变大，注意 SPL FIT 体积。

**附带坑**：`rk3588s-pinctrl.dtsi` 里没有任何 `u-boot,dm` 标签，gmac1 的 5 个 pin 组（`gmac1_miim / tx_bus2 / rx_bus2 / rgmii_clk / rgmii_bus`）会在 fdtgrep 阶段被裁掉。补法二选一：给 dtsi 打补丁加 `u-boot,dm-pre-reloc`，或在 U-Boot 自己的 `rk3588-u-boot.dtsi` 里补标签（推荐后者，补丁面更小、升级冲突更少）。

### 8.6 坑：`USING_KERNEL_DTB_V2` 让两份 DTB 不同源

`USING_KERNEL_DTB`（V2 模式）开启时，U-Boot 运行时的设备树**不是你编译的那份 u-boot dts**，而是从启动介质上读出来的「内核 dtb」。只有串口和 eMMC 用你编译的 u-boot dts，其余外设（含以太网）的节点来自介质上的内核 dtb。后果：你在 `arch/arm/dts/rk3588-*.dts` 里改的网口配置不生效；反过来内核 dtb 一改，U-Boot 行为跟着变。

选择：走正常启动（extboot 从 boot 分区读 `rk-kernel.dtb`），**保持默认**，不必开 U-Boot 网口；要走 TFTP+NFS 调试通道，就关掉 `USING_KERNEL_DTB` + `OF_U_BOOT_REMOVE_PROPS=""`，并保证 U-Boot 用的 dtb 与传给内核的 dtb 同源。

### 8.7 rkbin 与 DDR bin

`LubanCat/rkbin` master 的 `RKBOOT/RK3588MINIALL.ini` 原始内容（**未**被本层改写时）：

```ini
[CODE471_OPTION] Path1=bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.19.bin
[CODE472_OPTION] Path1=bin/rk35/rk3588_usbplug_v1.11.bin
[LOADER_OPTION]  FlashData=…ddr…_v1.19.bin   FlashBoot=…rk3588_spl_v1.13.bin
[OUTPUT]         PATH=rk3588_spl_loader_v1.19.113.bin   NEWIDB=true
```

DDR bin 在 ini 里出现**两次**：`[CODE471_OPTION]` 的 `Path1`（boot_merger 的选项描述）和 `[LOADER_OPTION]` 的 `FlashData`（真正打进 loader 的那份）。只改前者会得到「ini 看着对、loader 里还是旧 bin」的结果，而且不报错——这是本节最值得记住的一条。

本层按 machine 要求的档位改写这两处（`do_compile:prepend`，改名后再断言 bin 文件存在）。各芯片的频点基线：

| SoC            | DDR 频点  | rkbin 里的 bin                                                               |
| -------------- | ------- | -------------------------------------------------------------------------- |
| RK3588 / 3588S | 1848MHz | `rk3588_ddr_lp4_1848MHz_lp5_2112MHz_v1.19.bin`（本层改写；rkbin 默认是 2112/2400 档） |
| RK3576         | 1560MHz | `rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.09.bin`（rkbin 没有 1560 档的 bin）       |
| RK3568         | 1560MHz | `rk3568_ddr_1560MHz_v1.23.bin`                                             |
| RK3566         | 1056MHz | `rk3566_ddr_1056MHz_v1.23.bin`                                             |
| RK3562         | 1332MHz | `rk3562_ddr_1332MHz_v1.07.bin`                                             |
| RK3528         | 1056MHz | `rk3528_ddr_1056MHz_v1.11.bin`                                             |

注意 bin 文件名里的频率是 **bin 内含的最高档位**（LPDDR4x / LPDDR5 两套），不等于内核运行时实际频点；运行时频点由 kernel 的 dmc devfreq 协商，`/sys/class/devfreq/dmc/available_frequencies` 能看到本板支持的全部档位（rk3576 实测 `528 / 1068 / 1560 / 2112 MHz`）。

改档后串口应打印 `DDR Version V1.19` + `LPDDR4X, 1848MHz`。历史上工作区日志是 `V1.08` + `2112MHz`，那是旧档位配置的产物，不要拿它当基线。

排查手段：

```bash
# 1848 档 bin 的 typ 时间戳是 25/04/21，2112 档是 25/03/13（两份 v1.19 的 fw hash 前缀相同，
# 只能靠时间戳区分）
strings build/tmp/deploy/images/lubancat-4-v1/idblock.img | grep -iE 'ddr|^typ|20[0-9]{6}'
```

idblock.img 里没有文件名，只能看到 DDR 初始化的版本串与 typ 时间戳；要确认实际运行频点最终还得看串口打印的 `LPDDR4X, 1848MHz`。

> 验证状态：1848 档只做到「编译期改写生效 + idblock 内 DDR 固件时间戳与 1848 档 bin 一致」（`bitbake -c compile -f -v u-boot-rockchip` 后比对 `strings idblock.img`），**未在 RK3588 板上实测串口输出**。上板请确认频点与整机稳定性（DDR 训练失败的表现是一行都不打印）。

回退路径：把 `LUBANCAT_DDR_BIN` 改回 `rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.19.bin`（ini 会被自动改回），重编 u-boot；或把 `SRCREV_rkbin` 退到 SDK 同源的提交。

---

## 9. 镜像与包组

### 9.1 三个镜像，一条递进线

| 镜像                       | 基于                   | 加了什么                                                                                                                | 判定                       |
| ------------------------ | -------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `lubancat-image-minimal` | `core-image-minimal` | `packagegroup-lubancat-base`、dropbear、`debug-tweaks`                                                                | 串口 `login:`              |
| `lubancat-image-net`     | 同上                   | `packagegroup-lubancat-net`（tcpdump / tftp / curl + pciutils / iw / wpa-supplicant + 四个无线模块与固件 + netconfig）、openssh | `1000Mb/s Full` + ping 通 |
| `lubancat-image-full`    | `core-image-weston`  | 上面两个 group + `rockchip-libmali` + `rockchip-librga` + `rockchip-npu` + `kmscube`，`hwcodecs`                         | `kmscube` 出画面            |

```bash
bitbake lubancat-image-minimal extboot-image
bitbake lubancat-image-net     extboot-image
bitbake lubancat-image-full    extboot-image
```

`extboot-image` **不是镜像**，它生成 boot 分区那份 128 MiB 的 `boot-ext2.img`。target 里不带它，`make-updateimg.sh` 会找不到 boot 分区。

两点提醒：

- `lubancat-image-full` 需要 `DISTRO_FEATURES` 里有 `pam`（systemd + weston 强制要求），`kas/lubancat.yml` 与 `local.conf.sample` 都已带上。
- `rockchip-npu` 是给**外挂 PCIe NPU** 用的工具集，内置 RK3588 NPU 真正需要的是 `librknnrt.so`，默认镜像里没有（§12.19）。

### 9.2 packagegroup 分层原则

`base`（能登录、能挂载、能看设备、带首启服务）／`net`（抓包、测速、无线工具链）两层，镜像只做组合，**不重复定义 `IMAGE_INSTALL` 列表**。`lubancat-image.bbclass` 里刻意不写 `IMAGE_INSTALL`——写了所有镜像就都被绑死。

`packagegroup-lubancat-base` 的实际内容（注意这两个坑已避开）：

| 包                                                                                | 说明                                                                                                      |
| -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `systemd`                                                                        | **不要写 `systemd-networkd` / `systemd-resolved`**：scarthgap 的 systemd 255 不拆这两个包，写它会报 `Nothing RPROVIDES` |
| `ethtool` `iproute2` `iputils` `i2c-tools`                                       | 现场排查最小集                                                                                                 |
| `e2fsprogs-mke2fs` `e2fsprogs-resize2fs` `dosfstools` `util-linux-{mount,blkid}` | 首启扩容与挂载                                                                                                 |
| `lubancat-firstboot`                                                             | 扩容 + 切板两个 oneshot 服务（§14.11 / §14.12）                                                                   |

### 9.3 变量联动关系（这是最容易拧巴的一处）

extboot 布局下（默认）：

```
KERNEL_DEVICETREE=rockchip/xxx.dtb
        │  (linux-rockchip.inc)
        ▼
KERNEL_IMAGETYPE_FOR_MAKE=xxx.img ──► boot.img（**只给 wic / EXTBOOT=0 用**）

virtual/kernel:do_deploy ──► deploy/Image + deploy/dtb/{*.dtb,overlay/*.dtbo}
                                        │
                       extboot-image ───┴──► boot-ext2.img（boot.scr + Image + rk-kernel.dtb
                                              + dtb/ + dtb/overlay/ + uEnv/）
                                        │
                    make-updateimg.sh ──┴──► update.img（rkfw，首选烧写形态）
IMAGE_FSTYPES 含 wic ──► WKS_FILE=lubancat-gptdisk.wks.in ──► .wic / .wic.gz（整盘，逃生路径）
```

三处必须同时对：`KERNEL_DEVICETREE` 的 `rockchip/` 前缀（决定 `boot.img` 是否生成）、`LUBANCAT_DTB`（决定 `/rk-kernel.dtb` 是哪份）、`do_image_wic` 的依赖（bbclass 已补 `virtual/{kernel,bootloader}:do_deploy`，否则 wic 会抢在 u-boot 之前跑，报 `no such file: idblock.img`）。

---

## 10. 分区、打包与烧录

### 10.1 wks 逐行（wic 布局）

```
bootloader --ptable gpt

part idblock --source rawcopy --sourceparams="file=idblock.img" --align 32 --no-table
part uboot   --source rawcopy --sourceparams="file=uboot.img"   --offset 2M
part boot    --source rawcopy --sourceparams="file=boot.img"    --align 4
part rootfs  --source rootfs --fstype ext4 --label rootfs --align 8192 --uuid 614e0000-0000-4000-8000-000000000000
```

| 行                               | 含义                                          | 与上游的差异                                           |
| ------------------------------- | ------------------------------------------- | ------------------------------------------------ |
| `idblock --align 32 --no-table` | 32 KiB 对齐（= sector 64，BootROM 硬约束），不占分区表项   | 相同                                               |
| `uboot --offset 2M`             | uboot.img 固定在 2 MiB                         | 相同；**但 Rockchip `parameter.txt` 是 8 MiB，两套不可混用** |
| `boot`                          | Rockchip 风格 `boot.img`（kernel+dtb+resource） | 相同                                               |
| `rootfs … --uuid 614e…`         | 固定 PARTUUID                                 | **本层新增**                                         |
| ~~`trust`~~                     | 上游有，本层**删掉**                                | FIT 流程不产 `trust.img`，留着会 `rawcopy` 失败            |

### 10.2 root= 的三种写法

| 写法                                                   | 稳健性   | 说明                                                           |
| ---------------------------------------------------- | ----- | ------------------------------------------------------------ |
| `root=/dev/mmcblk0p3`                                | 中     | extboot 的 `boot.cmd` 就是这么传的（boot 分区是 p2、rootfs 是 p3，顺序固定）    |
| `root=PARTUUID=614e0000-0000-4000-8000-000000000000` | **好** | wic 布局用；与 wks `--uuid` 严格对应，也是 Rockchip 内核 dtsi 的默认 bootargs |
| `root=LABEL=rootfs`                                  | 中     | 依赖 `--label` 与 initramfs/udev 支持                             |

为什么 wic 必须固定 GUID：Rockchip 的 U-Boot 里 `env_update()` 是**按键名合并**——dtb 里有 `root=`，就用 dtb 的值覆盖命令行。所以你在 U-Boot 里 `setenv bootargs root=/dev/nfs` 会被 `rk3588-linux.dtsi` 的 `root=PARTUUID=614e0000-…` 干掉（历史现象：`Waiting for root device PARTUUID=614e0000-0000…` 卡死）。固定 GUID 之后「默认 bootargs 恰好正确」。

### 10.3 烧写

**首选 `update.img`**（一条命令、Windows 图形工具也能刷、失败重插即可）：

```bash
# 板子进 loader 模式：按住 REC 再上电；或系统里 `reboot loader`
sudo upgrade_tool uf /path/to/update.img
# Windows：RKDevTool → 「升级固件」→ 选 update.img → 执行
```

**wic 整盘**（完全脱离厂商工具，适合 CI）：

```bash
rkdeveloptool ld                       # 确认识别
rkdeveloptool db rk3588_spl_loader_v1.19.113.bin   # MaskROM 冷启动才需要；loader 模式可跳过
rkdeveloptool wl 0 disk.wic
rkdeveloptool rd
# 或：sudo ./scripts/flash-emmc.sh build/tmp/deploy/images/<machine>/*.wic.gz [--loader <bin>]
```

两套布局的偏移不可互换（uboot 2 MiB vs 8 MiB），刷错的表现是「U-Boot 都不打印」或「打印后找不到内核」。

### 10.4 首次上电的判定顺序

1. DDR 训练打印（`DDR Version V1.xx` + `LPDDR4X, xxxxMHz`）——没有？DDR bin / 供电问题，先别看后面。
2. `U-Boot 2017.09-…` 横幅——没有？idblock 偏移或 loader 没写进去。
3. `DTB(Distro): rk-kernel.dtb`——早期 dtb 取自 boot 分区，说明 ext2 布局生效。
4. `Found U-Boot script /boot.scr`——`distro_bootcmd` 命中。
5. `Starting kernel …` 后**立刻**有内核日志——没有？FIQ console 没编进去（§7.3）。
6. `login:`——没有？getty 端口不对（§12.1）。
7. 起来后 `cat /proc/cmdline` 应含 `console=ttyFIQ0,1500000n8 root=/dev/mmcblk0p3 boot_part=2`。

族镜像第一次启动会**自动重启一次**（在切 dtb），属正常行为；板级别名 `lubancat-4-v1` 不会重启。起来后确认三件事：

```bash
journalctl -u lubancat-board-detect | tail     # 认板与切 dtb 的日志
cat /sys/firmware/devicetree/base/model
systemctl status lubancat-resize-rootfs; df -h /
```

### 10.5 打包成 rkfw（`update.img`）

`scripts/make-updateimg.sh`，工具随仓库提供（`tools/rkpack/` 里的 `afptool` 2.29 + `rkImageMaker`），**不需要装 Rockchip SDK**。

```bash
./scripts/make-updateimg.sh
# ==> 芯片型号: RK3588（由 loader.bin 偏移 21 的 4 字节反序推断）
# ==> build/updateimg/update.img
```

| 变量                | 默认值                                                    | 说明                                                      |
| ----------------- | ------------------------------------------------------ | ------------------------------------------------------- |
| `MACHINE`         | `lubancat-4-v1`                                        | 决定从哪个 deploy 目录取文件                                      |
| `IMAGE`           | 最新修改的 `*.rootfs.ext4`                                  | 多份 rootfs 并存时指定，如 `IMAGE=lubancat-image-full`           |
| `ROOTFS`          | 无                                                      | 直接给绝对路径，优先级最高                                           |
| `EXTBOOT`         | `1`                                                    | 设为 `0` 回退旧 FIT 布局（boot 64 MiB + rootfs 固定 448 MiB），逃生路径 |
| `DEPLOY` / `WORK` | `build/tmp/deploy/images/$MACHINE` / `build/updateimg` | 自定义路径；**多 machine 并存时每族一个 WORK**，脚本会先 `rm -rf $WORK`    |
| `PACK`            | `tools/rkpack`                                         | 指向自备 SDK 的 `.../Linux_Pack_Firmware/rockdev`            |

脚本替你做掉的四件事，都是踩过的坑：

1. **芯片型号自动推断**：loader.bin 偏移 21 存的是反序 4 位芯片号（RK3588 → `8853`），`rev` 一下就得到 `RK3588`。一条脚本覆盖六族（rk3566 的 loader 声明的是 `3568`，这是正常现象，见 §6.5）。
2. **parameter.txt 自己写**：SDK 模板的 `uuid:rootfs` 是 `614e…4b53…`，与本层内核 dtsi 的 `614e0000-0000-4000-8000-000000000000` 不一致，照抄会卡 `Waiting for root device`。  
   |  |  |  
   | --- | --- |
3. **rootfs 按 mtime 取最新**：`ls -1 | head -1` 是字母序，`lubancat-image-full` 永远排在 `lubancat-image-minimal` 前面——重编了 minimal，包里塞的还是几天前的 full。脚本改为 `ls -1t`，并在多份并存时打印选了哪份。
4. **尺寸断言**：extboot 下 `boot-ext2.img` 必须**恰好** 128 MiB（与 parameter 的 `0x40000` 扇区严格相等），且真是 ext2；否则 `afptool` 会写越界或留空。

extboot 的几何（与 wic 完全不同）：

```
0x4000  uboot   (8 MiB)
0x8000  boot    (0x40000 扇区 = 128 MiB, bootable)
0x48000 rootfs  (grow 到盘尾)
```

rootfs 变成 grow 之后，`lubancat-image-full` 曾经「超过 448 MiB 就打不进去」的问题随之消失；文件系统本身由首启的 `lubancat-resize-rootfs` 扩（§14.11）。

校验与拆包（`afptool` 不能直接解 `update.img`，它是 rkfw 容器，要先脱壳）：

```bash
head -c 4 build/updateimg/update.img | xxd      # 52 4b 46 57 = "RKFW"
tools/rkpack/rkImageMaker -unpack build/updateimg/update.img /tmp/u
tools/rkpack/afptool -unpack /tmp/u/firmware.img /tmp/out
grep CMDLINE /tmp/out/parameter.txt
file /tmp/out/boot.img                          # 应为 ext2, 134217728 字节
```

实测产物（rk3566 族，full）：`update.img` 798 MB（836,223,562 B），md5 `3e5411e2…`；其中 boot 128 MiB、rootfs 661 MB、`uboot.img` 8 MiB。

### 10.6 三种产物对照

`boot-ext2.img`、`*.wic.gz`、`update.img` 对应两套互不兼容的布局，区别、约束与校验方法见 [`boot-artifacts.md`](boot-artifacts.md)。判断手上跑的是哪套，看内核命令行就够：

```bash
cat /proc/cmdline
# rkfw + extboot: root=/dev/mmcblk0p3 boot_part=2 …（boot.cmd 写入）
# wic:            root=PARTUUID=614e0000-0000-4000-8000-000000000000
```

---

## 11. SDK / eSDK / devtool

### 11.1 标准 SDK

```bash
bitbake lubancat-image-minimal -c populate_sdk
# 产物：tmp/deploy/sdk/poky-glibc-x86_64-lubancat-image-minimal-cortexa76-cortexa55-*.sh
./poky-….sh -d /opt/lubancat-sdk
source /opt/lubancat-sdk/environment-setup-cortexa76cortexa55-poky-linux
$CC --version
```

适用：纯用户态应用（C/C++/Qt），不涉及内核模块。

### 11.2 eSDK + devtool

```bash
bitbake lubancat-image-minimal -c populate_sdk_ext
./poky-…-ext.sh -d /opt/lubancat-esdk
source /opt/lubancat-esdk/environment-setup-…

devtool modify virtual/kernel      # 把内核源码展开到 workspace
devtool build virtual/kernel
devtool deploy-target <pkg> root@<board>
devtool finish virtual/kernel ../meta-lubancat   # 改动落成 patch 进层
```

两个坑：

- eSDK 首次 `devtool modify` 要 sstate 命中，否则现场重编，极慢。**在同一台机器上先完整构建一次再打包 eSDK**。
- `rm_work` 与 `devtool` 冲突：`devtool modify` 期间临时 `INHERIT:remove = "rm_work"`。

### 11.3 与既有 buildroot 工具链共存

两套 SDK 都会改 `PATH`、`CC`、`CROSS_COMPILE`。建议各自一个干净 shell：

```bash
env -i HOME=$HOME TERM=$TERM bash --noprofile --norc
source /opt/lubancat-sdk/environment-setup-…
```

---

## 12. 故障排查手册

格式固定：**症状 → 根因 → 验证 → 修复 → 回归判据**。

### 12.0 速查表（症状 → 根因 → 处置）

下表按出现频率排序，细节与验证命令见对应小节。

| #  | 症状                                                                              | 根因                                                                         | 处置                                                                          |
| -- | ------------------------------------------------------------------------------- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| 1  | 串口全黑，但能 ping / ssh                                                              | `uEnv.txt` 的 `cmdline=` 覆盖了 dts，且 `console=ttyFIQ0` 没带波特率                  | 改成 `console=ttyFIQ0,1500000n8`，重跑 `bitbake extboot-image`                   |
| 2  | 卡 `Waiting for root device PARTUUID=...`                                        | rootfs 的 PARTUUID 与内核 dtsi 默认值不一致（抄了厂商 parameter 模板）                       | 用 `make-updateimg.sh`（自带 `614e0000-…-000000000000`）                         |
| 3  | `No rule to make target 'rockchip/xxx.dtb'`                                     | `KERNEL_DEVICETREE` 少了 `rockchip/` 前缀，或自研 dts 没注册进 Makefile                | 写全前缀；方案 B 见 §7.4                                                            |
| 4  | `Nothing RPROVIDES 'systemd-networkd'`                                          | scarthgap 的 systemd 255 不拆这个包                                              | `RDEPENDS` 写 `systemd`                                                      |
| 5  | `Nothing RPROVIDES 'weston-xwayland'` + `missing required distro feature 'pam'` | systemd + weston 强制要求 `pam`                                                | `DISTRO_FEATURES:append = " pam"`（会触发全量重签名）                                 |
| 6  | `WARNING: The free inode ... is running low` + `No new tasks ... STOPTASKS`     | `BB_DISKMON_DIRS` 第二列是千个 inode，写成 `1G` 等于要求 10 亿个                          | 用 `...,2G,100K`；`HALT,...,500M,10K`                                         |
| 7  | `No recipes ... for: u-boot-rockchip_%.bbappend`                                | 该 recipe 文件名无版本号（PV 在文件内部）                                                 | bbappend 命名成 `u-boot-rockchip.bbappend`                                     |
| 8  | `Error, you have '..' in your TMPDIR directory path`                            | sanity checker 禁止                                                          | `TMPDIR = "${TOPDIR}/tmp"`                                                  |
| 9  | `unparsed line: 'INHERIT += "rm_work"  # ...'`                                  | bitbake 的 conf 不支持行尾注释                                                     | 注释单独成行                                                                      |
| 10 | 内核配置片段写了不生效（关不掉某个驱动）                                                            | `.cfg` 走 `merge_config.sh`，`# CONFIG_X is not set` 会被当注释删掉                 | 写 `CONFIG_X=n`                                                              |
| 11 | `Error: file not found: drivers/gpu/arm/bifrost/mali_csffw.bin`                 | 驱动用 `.incbin` 相对汇编器 cwd，Yocto 是 out-of-tree 构建                             | 编译前把 bin 复制到 `${B}` 同名路径（bbappend 已做）                                       |
| 12 | `rtl8821cu/core/rtw_cmd.c: fatal error: drv_types.h`（后面还跟着 `aes.h` / `mlmeext`） | vendor 驱动用 `-I$(src)/` 和 `DRV_PATH=$(src)`，`O=${B}` 下 `$(src)` 是相对源码树的路径   | 已由 `0002-wifi-out-of-tree-paths.patch` 修掉（§12.17）                           |
| 13 | `make: *** No rule to make target 'dtbs'`                                       | bitbake 任务 cwd 是 `${WORKDIR}`                                              | `oe_runmake -C ${S} O=${B} dtbs`                                            |
| 14 | 构建成功但 deploy 里没有 `boot-ext2.img`                                                | 只 `inherit deploy` 时 `do_build` 没串 `do_deploy`                             | `addtask deploy after do_compile before do_build`                           |
| 15 | 重编了 minimal，烧进去却没有新包                                                            | 打包脚本按字母序取了 `lubancat-image-full`                                           | 已改按 mtime；必要时 `IMAGE=` / `ROOTFS=` 指定                                       |
| 16 | 首启没切板，还是 generic dtb                                                            | `LUBANCAT_FIRSTBOOT_SWITCH=0` / 内核没使能 saradc / `board_id` 不在 `board-table` | `journalctl -u lubancat-board-detect`；对着日志里的 `adc ch2/ch3` 改表               |
| 17 | 首启后容量还是镜像大小                                                                     | 分区没 grow（用了 `EXTBOOT=0` 或 wic 路径）                                          | `growpart /dev/mmcblk0 3 && resize2fs /dev/mmcblk0p3`，或改用 extboot           |
| 18 | `shallow mismatch` / 下载只有 30 KB/s                                               | 之前全量拉过同仓 / 没开浅克隆与代理                                                        | 删对应 `build/downloads/git2/<repo>`；`source scripts/setup-mirror.sh`          |
| 19 | `afptool: cannot execute binary file`                                           | `tools/rkpack` 是 x86-64 ELF（ARM 主机/macOS 跑不了）；或 exec 位丢了                   | 换 x86-64 Linux，或 `PACK=` 指自备 SDK；`chmod +x tools/rkpack/*`                  |
| 20 | `pip install kas` 报 `No matching distribution found`                            | 国内 pip 镜像没同步 kas                                                           | `pip install -i https://pypi.org/simple kas`                                |
| 21 | `Direct firmware load for rtw89/… failed` / 有驱动没 `wlan0`                        | 固件包没装；rtw89 的固件没被 poky 切成子包                                                | 装 `linux-firmware-rtw89`（本层 bbappend 提供），见 §7.7                             |
| 22 | wifi 已关联、有 IP、网关能 ping，但上不了外网                                                   | udhcpc 的 metric 写死 10，与有线 `RouteMetric=10` 撞车                              | 无线交给 systemd-networkd（`lubancat-netconfig`），别再手工跑 `udhcpc`，见 §7.7.6         |
| 23 | `weston.service` 开机 `status=1/FAILURE`，journal 无线索                              | 首次启动时 DRM 主控还没就绪（实测手动 `weston --backend=drm-backend.so` 可正常显示）             | 先 `systemctl reset-failed weston && systemctl start weston`，或手动起 weston 看日志 |
| 24 | `uname -r` 里没有 `-rt36`                                                          | RT 与非 RT 共用了一个 `TMPDIR`，deploy 产物互相覆盖                                      | 必须 `KAS_BUILD_DIR=$PWD/build-rt`，见 §7.8                                     |

### 12.1 串口无 `login:`，但内核日志正常

- **根因**：getty 起在 `ttyS2` 上，而控制台是 `ttyFIQ0`。  
  |  |  |  
  | --- | --- |
- **验证**：`systemctl status serial-getty@ttyFIQ0` 应为 active；`ps | grep getty` 看实际端口。
- **修复**：`SERIAL_CONSOLES = "1500000;ttyFIQ0"`（本层已写死）+ `SERIAL_CONSOLES_CHECK`。
- **回归**：重启后 10 秒内出现 `login:`。

### 12.2 U-Boot 里网口不工作，且无任何报错

- **根因**：`OF_U_BOOT_REMOVE_PROPS` 删掉 `assigned-clocks` → `clk_set_rate(125M)` 不精确 → `-EINVAL`，驱动不打日志。
- **验证**：对比开/关该选项两次构建的 U-Boot 行为最快（读寄存器没有意义）。
- **修复**：`CONFIG_OF_U_BOOT_REMOVE_PROPS=""`（仅调试期）。
- **回归**：`ping` 网关通。

### 12.3 pin 组在 U-Boot 里「不存在」

- **根因**：`rk3588s-pinctrl.dtsi` 无 `u-boot,dm` 标签，fdtgrep 裁剪时把 gmac1 的 pin 组裁掉。
- **验证**：`fdtget` 看 U-Boot 运行时 dtb 里 gmac1 节点下有没有 `pinctrl-0`。
- **修复**：U-Boot 的 `rk3588-u-boot.dtsi` 里补 `u-boot,dm-pre-reloc`。

### 12.4 FIT 体积超限

- **症状**：`fit/uboot.itb actual: N bytes, max limit: 2097152 bytes`
- **根因**：`SPL_FIT_IMAGE_KB` 太小（历史默认 2048）。当前 defconfig 是 4096，一般不触发；开 `USING_KERNEL_DTB` 后可能触发。
- **修复**：`CONFIG_SPL_FIT_IMAGE_KB=6144` + `CONFIG_SPL_FIT_IMAGE_MULTIPLE=1`。
- **回归**：`uboot.img` 生成且大小 < 限额。

### 12.5 卡在 `Waiting for root device PARTUUID=614e0000-0000…`

- **根因**：dtb 里的 `/chosen bootargs` 覆盖了命令行；或 wic 的 rootfs GUID 与该值不一致。
- **验证**：`fdtget dtb /chosen bootargs`；能进 initramfs 的话看 `/proc/cmdline`。
- **修复**：wks 固定 `--uuid 614e0000-0000-4000-8000-000000000000`（本层已做）；应急可 `fdt rm /chosen bootargs`。
- **回归**：`findmnt /` 的 `PARTUUID` 与之一致。

### 12.6 `No rule to make target 'rockchip/xxx.dtb'`

- **根因**：自研 dts 没注册进 `arch/arm64/boot/dts/rockchip/Makefile`。
- **修复**：见 §7.4 方案 B。
- **回归**：`boot.img` 生成，`dtc -I dtb -O dts` 能反解出该 dtb。

### 12.7 `ERROR: No ../rkbin repository`

- **根因**：`make.sh` 里写死 `RKBIN_TOOLS=../rkbin/tools`，rkbin 没落在 `${WORKDIR}/rkbin`。
- **修复**：`SRC_URI` 里 rkbin 那条必须带 `;name=rkbin;destsuffix=rkbin`，且 `SRCREV_FORMAT` 含 `default_rkbin`。

### 12.8 `No python2`

- **根因**：`make.sh` 末行 `make PYTHON=python2`。
- **修复**：不要自己重写流程，用上游 recipe——它的 `do_configure:prepend` 已删掉 make.sh 里的 `make` 行并把脚本 shebang 改成 python3。

### 12.9 wic 报 `rawcopy: no such file: trust.img`

- **根因**：FIT 流程不产 `trust.img`，而 wks 里写了 trust 分区。
- **修复**：用本层的 `lubancat-gptdisk.wks.in`（已去掉 trust）。  
  |  |  |  |  |  
  | --- | --- | --- | --- |
- **回归**：`ls deploy/images/*/ | grep -E 'idblock|uboot|boot\.img'` 三个都在。

### 12.10 `boot.img` 没生成 / boot 分区为空

- **根因**：`KERNEL_DEVICETREE` 少了 `rockchip/` 前缀，`KERNEL_IMAGETYPE_FOR_MAKE` 推导错。  
  |  |  |  
  | --- | --- |
- **验证**：`bitbake -e virtual/kernel | grep KERNEL_IMAGETYPE_FOR_MAKE`
- **修复**：改回 `rockchip/xxx.dtb`。extboot 布局不吃 `boot.img`，所以这个问题只在 wic / `EXTBOOT=0` 时暴露。

### 12.11 `Nothing PROVIDES 'linux-rockchip'` / `no candidate for PREFERRED_VERSION`

- **根因**：`PREFERRED_VERSION_linux-rockchip` 与实际 recipe PV 不匹配；或 bbappend 文件名版本号写错（`linux-rockchip_6.1.bbappend` 只能 append 到 `PV=6.1` 的 recipe）。
- **验证**：`bitbake-layers show-recipes linux-rockchip`
- **修复**：`PREFERRED_VERSION_linux-rockchip = "6.1%"`，bbappend 文件名与 recipe 版本严格一致。

### 12.12 `LAYERSERIES_COMPAT` 报错

- **根因**：混用 kirkstone 的层到 scarthgap 工程（或反之）。
- **修复**：所有层统一到 `scarthgap`；不要用 `LAYERSERIES_COMPAT` 强行放行。

### 12.13 上游层特有：`patch-status` QA 被 remove

|                                                                                                                                                                                  |                                      |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| `meta-rockchip` 的 `rockchip-common.inc` 里有 `ERROR_QA:remove = "patch-status patch-fuzz"`——上游自己的补丁也不合规，所以别指望 QA 帮你拦自建补丁的 `Upstream-Status`。自己写的补丁仍按规范填（\`Upstream-Status: Pending | Inappropriate\`），否则将来升级 Yocto 会成片报错。 |

### 12.15 层与配置的「第一次解析」必踩清单（全部在真实机器上撞过）

以下 9 条是从首次 `bitbake -p` 到首次 `bitbake` 之间按顺序爆出来的。**先跑 `bitbake -p`（只解析，约 1 分钟），再 `bitbake -n <image>`（只排任务图，约 2 分钟），最后才真编。**

| # | 报错原文                                                                                                  | 根因                                                                            | 修法                                                        |
| - | ----------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | --------------------------------------------------------- |
| 1 | `ParseError at conf/local.conf:54: unparsed line: 'INHERIT += "rm_work"   # ...'`                     | **bitbake 不支持行尾注释**                                                           | 注释单独成行                                                    |
| 2 | `Error, you have '..' in your TMPDIR directory path`                                                  | sanity checker 禁止 `TMPDIR` 含 `..`（`DL_DIR`/`SSTATE_DIR` 不受限）                  | `TMPDIR = "${TOPDIR}/tmp"`                                |
| 3 | `Could not include required file recipes-core/images/core-image-weston.bb`                            | 文件在 `recipes-graphics/images/`                                                | `require recipes-graphics/images/core-image-weston.bb`    |
| 4 | `No recipes in default available for: …/u-boot-rockchip_%.bbappend`                                   | `u-boot-rockchip.bb` 文件名没有版本号                                                 | bbappend 必须叫 `u-boot-rockchip.bbappend`                   |
| 5 | （不报错，但行为错）`KBUILD_DEFCONFIG` 显示 `rk3588_linux_defconfig`                                              | 板级 include 没覆盖上游赋值                                                            | 显式 `KBUILD_DEFCONFIG = "lubancat_linux_rk3588_defconfig"` |
| 6 | （不报错，但编译期会挂）`KERNEL_FEATURES=" cfg/fs/vfat.scc"`                                                      | `MACHINE_FEATURES` 里有 `vfat` 时 poky 追加该 scc，而 `linux-rockchip` 不是 linux-yocto | 去掉 `vfat`                                                 |
| 7 | `Nothing RPROVIDES 'systemd-networkd'`                                                                | scarthgap 的 systemd 255 不拆这两个包                                                | `RDEPENDS` 写 `systemd`                                    |
| 8 | `Nothing RPROVIDES 'weston-xwayland'` + `weston … was skipped: missing required distro feature 'pam'` | systemd + weston 强制要 pam，poky 默认不含                                            | `DISTRO_FEATURES:append = " pam"`                         |
| 9 | `WARNING: The free inode … is running low` + `STOPTASKS`                                              | `BB_DISKMON_DIRS` 第二列单位是 K（千个 inode）                                          | `STOPTASKS,${TMPDIR},2G,100K`                             |

第 5、6 条最值得记：**它们不报错**，只把问题推迟到编译阶段，然后以一句「找不到 xxx」的形式出现。判断手段是一条命令：

```bash
bitbake -p && bitbake -e virtual/kernel | grep -E '^(KBUILD_DEFCONFIG|KERNEL_FEATURES|KERNEL_IMAGETYPE_FOR_MAKE)='
```

期望输出（实测值）：

```
KBUILD_DEFCONFIG="lubancat_linux_rk3588_defconfig"
KERNEL_FEATURES="   "
KERNEL_IMAGETYPE_FOR_MAKE=" rk3588s-lubancat-4-v1.img"
```

`KERNEL_IMAGETYPE_FOR_MAKE` 里出现 `<dts>.img` 说明 `KERNEL_DEVICETREE` 与 `.img` 规则对上了。

### 12.16 内核编译期：`Error: file not found: drivers/gpu/arm/bifrost/mali_csffw.bin`

**症状**（`linux-rockchip` 的 `do_compile`，编到 GPU 驱动阶段就挂）：

```
/tmp/ccXXX.s:102: Error: file not found: drivers/gpu/arm/bifrost/mali_csffw.bin
make[6]: *** [scripts/Makefile.build:250: drivers/gpu/arm/bifrost/csf/mali_kbase_csf_firmware.o] Error 1
```

**根因**：Rockchip BSP 的 bifrost 驱动在 `csf/mali_kbase_csf_firmware.c` 里用

```c
asm(".incbin \"drivers/gpu/arm/bifrost/mali_csffw.bin\"");
```

这是**相对汇编器当前工作目录**的路径。SDK 是 in-tree 构建（`S == B`），路径自然对得上；Yocto 用 `O=${B}` 做 out-of-tree 构建，汇编时 cwd 是构建树，而 `mali_csffw.bin` 只在源码树，于是找不到。文件本身是有的（278 KB，就在 `$S/drivers/gpu/arm/bifrost/`），**不是仓库缺文件**。

**修法**：编译前把 bin 复制到 `${B}` 的同名相对路径下，别去关 GPU 驱动也别改内核源码：

```python
do_lubancat_mali_fw() {
    fw="${S}/drivers/gpu/arm/bifrost/mali_csffw.bin"
    [ -f "$fw" ] || { bbwarn "mali_csffw.bin 不在 ${S}，跳过"; return 0; }
    install -d "${B}/drivers/gpu/arm/bifrost"
    install -m 0644 "$fw" "${B}/drivers/gpu/arm/bifrost/"
}
addtask lubancat_mali_fw after do_configure before do_compile
```

仍然用独立任务而不是 `do_compile:prepend()`，理由同 §8.4：避免和 class 里的同名 prepend 互相覆盖。

**验证**：`do_compile` 通过后会出现 `do_compile_kernelmodules: Started`（模块编译是 `do_compile` 的下一阶段，走到这里说明主 Image 已经编完）。

**同类问题排查**：`grep -rn '\.incbin' $S --include=*.c`。另外两处 `kernel/configs.c`、`kernel/kheaders.c` 的 `.incbin` 路径由 kbuild 在 `${B}` 里生成，不受影响。

### 12.17 内核模块编译期：vendor wifi 驱动找不到头文件（已修复）

**症状**（`do_compile` 通过，卡在 `do_compile_kernelmodules`），而且会一站一站往下走：

```
第一站：drivers/net/wireless/rockchip_wlan/rtl8821cu/core/rtw_cmd.c:17:10:
        fatal error: drv_types.h: No such file or directory
第二站：rtl8852be/core/rtw_swcrypto.c:16:10: fatal error: aes.h: No such file or directory
第三站：ioctl_cfg80211.c:4948:32: error: 'struct _ADAPTER_LINK' has no member named 'mlmeext'
        ioctl_cfg80211.h:432:60: error: implicit declaration of function 'cfg80211_send_rx_assoc'
```

**根因只有一个：`O=${B}` 的 out-of-tree 构建。** 这批 vendor 驱动只在 `S == B` 的拓扑下验证过，Yocto 把源码树（`S`）与构建树（`B`）分开后，`$(src)` 变成「相对源码树的路径」，而编译器 cwd 是构建树，于是：

| 坑 | 具体写法                                                                  | 后果                                   |
| - | --------------------------------------------------------------------- | ------------------------------------ |
| 1 | `EXTRA_CFLAGS += -I$(src)/include` 等                                  | `-I` 指向不存在的目录 → 第一、二站                |
| 2 | `DRV_PATH = $(src)` + `include $(wildcard $(DRV_PATH)/platform/*.mk)` | 通配为空，`platform/arm_rk.mk` 没读进来 → 第三站 |

第 2 个坑最阴：`platform/arm_rk.mk` 负责补 `-DCONFIG_IOCTL_CFG80211 -DRTW_USE_CFG80211_STA_EVENT`，少了这两个宏，代码就退回 6.1 已删掉的 `cfg80211_send_rx_assoc()` / `cfg80211_send_disassoc()`，还按老结构体访问 `_ADAPTER_LINK.mlmeext`——报出来的错误跟 include 路径毫无关系，很容易误判成「驱动不兼容内核 6.1」。

**为什么有的 `$(src)` 又能用？** kbuild 顶层 Makefile 里有 `MAKEFLAGS += --include-dir=$(abs_srctree)`，所以 `include $(src)/common.mk` 这种相对路径的 include 指令被搜索路径兜住了，只有 `-I` 参数和 `$(wildcard ...)` 不会被兜住。排错时按这个区分。

**修法**：`0002-wifi-out-of-tree-paths.patch`，在每个 Makefile 开头把 `src` 解析成绝对路径：

```make
LUBANCAT_WIFI_SRC := $(if $(filter /%,$(src)),$(src),$(srctree)/$(src))
EXTRA_CFLAGS += -I$(LUBANCAT_WIFI_SRC)/include
```

`$(if $(filter /%,...))` 是为了 `make M=...` 的外部模块构建——那种场景 `src` 本来就是绝对路径，不能再拼 `$(srctree)`。覆盖 5 个驱动（rtl8189fs / rtl8821cu / rtl8851be / rtl8852be / aic8800_usb）共 11 个文件。

**验证**（只编驱动目录，几分钟）：

```bash
S=build/tmp/work-shared/lubancat-rk3568/kernel-source
B=build/tmp/work/lubancat_rk3568-poky-linux/linux-rockchip/6.1/linux-lubancat_rk3568-standard-build
cd $S && ./scripts/config --file $B/.config -m RTL8852BE -m RTL8851BE -m RTL8821CU -m RTL8189FS
make -C $S O=$B olddefconfig
make -C $S O=$B -j$(nproc) drivers/net/wireless/rockchip_wlan/
```

通过标准是四个目录分别产出非 0 个 `.o`。注意 `make drivers/.../` 只做到 `LD [M] xxx.o`，`.ko` 要等 `make modules`，别拿 `.ko` 是否存在判断成败。

**只想要有线**：在 `lubancat-family.cfg` 里把四个改回 `=n` 即可，`CONFIG_WL_ROCKCHIP=y` 保留（它牵着 `CFG80211/MAC80211`）。本层默认是 `=m`。

**通用坑（值得单列）**：`.cfg` 片段走 `scripts/kconfig/merge_config.sh`，它先 `sed -e '/^#/d'` 把注释行全删掉，再 `s/^CONFIG_X=n$/# CONFIG_X is not set/`。所以：

| 写法                        | 结果                                 |
| ------------------------- | ---------------------------------- |
| `# CONFIG_FOO is not set` | **无效**，整行被当注释删掉                    |
| `CONFIG_FOO=n`            | 有效，被自动转成 `# CONFIG_FOO is not set` |
| `CONFIG_FOO=y`            | 有效                                 |

验证别看编译日志，直接看生成的 `.config`：

```bash
B=build/tmp/work/lubancat_rk3568-poky-linux/linux-rockchip/6.1/linux-lubancat_rk3568-standard-build
grep -E 'RTL8821CU|WL_ROCKCHIP|CFG80211' $B/.config
```

注意 `B` 不是 `work-shared/kernel-build-artifacts`，而是上面这个 `*-standard-build` 目录。

### 12.18 流水线式定位手段

```bash
bitbake -e virtual/kernel | grep -E '^(SRC_URI|SRCREV|KBUILD_DEFCONFIG|KERNEL_DEVICETREE|KERNEL_FEATURES)='
bitbake -e u-boot-rockchip | grep -E '^(UBOOT_MACHINE|LUBANCAT_|RK_UBOOT_CFG)'
bitbake -c devshell virtual/kernel        # 进到解开的源码里手动 make
bitbake -c cleansstate virtual/kernel && bitbake lubancat-image-minimal
bitbake-layers show-layers                # 层顺序与优先级
bitbake-layers show-appends u-boot-rockchip
oe-pkgdata-util list-pkg-files <pkg>      # 某包到底装了什么
```

### 12.19 上板后：HDMI 不亮、GPU/NPU 怎么验

**证据链**（LubanCat-4 V1 + 本层镜像实测）：

```
rockchip-vop2 fdd90000.vop: [drm:vop2_bind] *ERROR* No crtc register, please check dts config
rockchip-drm display-subsystem: failed to bind fdd90000.vop (ops …): -19
rockchip-drm display-subsystem: adev bind failed: -19
```

后果是**没有任何显示 DRM 设备**。此时 `/dev/dri/card0` 存在，但它属于 NPU：

```
$ readlink -f /sys/class/drm/card0
/sys/devices/platform/fdab0000.npu/drm/card0        ← 不是显示卡！
```

所以「有 `/dev/dri`」「有 `/dev/mali0`」≠ 显示正常。`/sys/class/drm/` 里没有 `card0-HDMI-A-1` 这种 connector，就是显示子系统没绑上。

**根因**：板级 dts `rk3588s-lubancat-4-v1.dts` 只 include 了 `rk3588s-lubancat-4.dts`，**没有 include 厂商自带的显示路由片段** `rk3588s-lubancat-4-hdmi0-vp0.dtsi`。于是 `&hdmi0` 与 `hdmi0_in_vp0/vp1/vp2` 全部保持 disabled，VOP2 找不到任何使能输出。

**修复**：一行 include（本层做成 patch `0001-arm64-dts-lubancat-4-v1-enable-hdmi0-vp0.patch`）：

```dts
#include "rk3588s-lubancat-4.dts"
#include "rk3588s-lubancat-4-hdmi0-vp0.dtsi"   /* 新增 */
```

该 dtsi 里已写好 `enable-gpios = <&gpio4 RK_PB6>`、`&route_hdmi0 { connect = <&vp0_out_hdmi0>; }`、`&hdptxphy_hdmi0`、`hdmi0_sound`，与硬件使能脚对齐，不要自己另写。它和 overlay 里的 `rk3588s-lubancat-4-hdmi0-vp0-overlay.dtbo` 是同一份 fragment 的两种投递方式（§14.13）。

**修好后按这个顺序验**：

```bash
# 1) 显示子系统绑上了没
dmesg | grep -E 'vop2|display-subsystem|dw-hdmi'   # 不应再有 No crtc register
ls /sys/class/drm/                                  # 应出现 card0-HDMI-A-1
cat /sys/class/drm/card0-HDMI-A-1/status            # connected（插着线时）

# 2) GPU（Mali-G610）
cat /sys/class/misc/mali0/device/gpuinfo            # Mali-G610 4 cores r0p0
ls /dev/mali0
kmscube                                             # 直接出旋转立方体：EGL+GBM+DRM 全通
cat /sys/class/devfreq/fb000000.gpu/cur_freq        # 跑的时候会升频

# 2b) Wayland 路径（weston 13.0.1 + weston-examples 在 full 镜像里）
weston --backend=drm-backend.so &
WAYLAND_DISPLAY=wayland-0 weston-simple-egl         # 有输出说明 GL 走通

# 3) NPU（RKNPU）
dmesg | grep -i rknpu                               # RKNPU driver: v0.9.8
ls /sys/class/devfreq/ | grep npu
ls /sys/kernel/debug/rknpu/                         # version / freq / load / power
```

关键判据：

| 现象                                                       | 说明                                   |
| -------------------------------------------------------- | ------------------------------------ |
| `/dev/mali0` 存在 + `gpuinfo` 可读                           | GPU **内核驱动**正常                       |
| `kmscube` 能出画面                                           | GPU **用户态**（libmali EGL/GBM）与显示链路都正常 |
| 只有 `/dev/mali0` 但 `kmscube` 报打不开 DRM                     | 显示子系统没绑上，先修 HDMI                     |
| `dmesg` 有 `Initialized rknpu` + devfreq 有 `fdab0000.npu` | NPU 内核侧正常                            |
| 没有 `librknnrt.so`                                        | NPU **用户态**缺失，需自备（见 12.20）           |

### 12.20 NPU 验证记录（LubanCat-4 V1，历史实测）

> 这一节是 2026-11-06 在 rk3588 板上用**手工部署**的 runtime 做的验证，镜像里并没有这些文件；测试环境事后已清理。留作「应该看到什么」的参照，不是镜像功能承诺。

| 层      | 验证点                                                                                                                  | 结果 |
| ------ | -------------------------------------------------------------------------------------------------------------------- | -- |
| 内核驱动   | `dmesg` 出现 `Initialized rknpu 0.9.8`，devfreq 有 `fdab0000.npu`，`/sys/kernel/debug/rknpu/{version,freq,load,power}` 可读 | ✅  |
| 用户态运行时 | `/usr/lib/librknnrt.so`（v2.3.0，来自 `rknpu2/runtime/Linux/librknn_api/aarch64/`），ctypes 调 `rknn_init` 返回 0             | ✅  |
| 真实推理   | `rknn_hello <model>.rknn 3`：`rknn_init` 32.6 ms，3 次 `rknn_run` 每次 4.4 ms，输出 1001 维且三次求和一致                            | ✅  |

`rknn_server`（同目录 `runtime/Linux/rknn_server/aarch64/usr/bin/`）放 `/usr/bin` 后直接启动，日志 `start rknn server, version:2.3.0` + `NPUTransfer server`；它由 PC 端工具经 adb/网络转发触发，重复启动会报 `Address already in use`（先 `killall rknn_server`）。

**注意区分两个名字相近的东西**：

- `rockchip-npu`（meta-rockchip recipe，`lubancat-image-full` 里装的就是它）→ 给**外挂 PCIe NPU**（RK1808 场景）用的，init 脚本会把 MiniLoaderAll/boot/uboot 烧到 PCIe EP，还带 `npu_transfer_proxy`。**内置 RK3588 NPU 不需要它**，需要的是 `librknnrt.so`（+ 需要 PC 端工具时再加 `rknn_server`）。
- `librknnrt` 是推理运行时，`rknn_server` 是 PC 工具链（adb/网络）转发服务。

模型转换（onnx → rknn）依赖 `rknn-toolkit2`，在 x86 主机上装，且它对 `torch` / `scipy` / `onnx` 有硬依赖——这是整条链最花时间的一步，与 BSP 无关。想跳过转换就直接用官方 model zoo 里已转好的 `.rknn`。

---

## 13. CHTUZKI/yocto-rk3588-core 仓库评估

### 13.1 它是干什么的

`https://github.com/CHTUZKI/yocto-rk3588-core`：面向 **Vanxak HD-RK3588-CORE 核心板**（RK3588J，8GB LPDDR4x + eMMC）的 scarthgap 工程。结构：

```
poky / meta-openembedded / meta-arm / meta-rockchip   # 全部 git submodule
meta-rockchip-updateimg                               # 自研：打包 update.img
meta-rk3588-custom                                    # 机器配置 + dts + 补丁 + 镜像
build/                                                # 含 conf 快照
参考文件/                                              # 厂家 update.img、parameter.txt、串口 cfg
构建命令.txt / 构建日志.txt / 启动日志.txt / 诊断报告.txt
```

特征：**没有 `kas.yml`、没有 `.wks` 文件**，走 Rockchip 原生 `update.img` + `parameter.txt` 路线；U-Boot 用预编译 `MiniLoaderAll.bin`（不从 rkbin 构建）。README 记录板子串口是 **115200**，并明确写「勿用 1500000」。

### 13.2 逐文件「可用性」判定

| 文件/目录                                                                  | 判定           | 说明                                                                                                                                             |
| ---------------------------------------------------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `conf/machine/hd-rk3588-core.conf`                                     | **需改（结构可学）** | `require conf/machine/include/rk3588.inc` 的写法正确；`SERIAL_CONSOLES=115200`、`UBOOT_MACHINE=evb-rk3588_defconfig`、`KERNEL_DEVICETREE` 三处都要换        |
| `classes/rk3588-image.bbclass`                                         | **可直接用（思路）** | 只做 `latest` 软链，职责单一，本层采纳了同类做法                                                                                                                  |
| `recipes-kernel/linux/linux-rockchip_6.1.bb`                           | **不可用**      | `SRC_URI` 指向 `JeffyCN/mirrors:kernel-6.1-2024_04_14`，那棵树没有 LubanCat 的 defconfig/dts；`KBUILD_DEFCONFIG=rockchip_linux_defconfig` 会丢 FIQ console |
| `recipes-kernel/linux/linux-yocto_%.bbappend` + `files/mainline/*.dts` | **不可用**      | 主线内核路线，HDMI/NPU/GPU 全丢                                                                                                                         |
| `files/0001-stmmac-resume-PHY-before-DMA-soft-reset.patch`             | **值得读**      | stmmac 休眠唤醒补丁，思路可借鉴（是否适用于 6.1.99 需实测）                                                                                                          |
| `files/0002-dwmac-rk-enable-clk-mac-and-default-rgmii-1g.patch`        | **值得读**      | 与「clk-mac 未使能导致 RGMII 不通」相关，和本板的坑同源                                                                                                            |
| `files/0003-dw-hdmi-rockchip-drive-enable-gpio-high-at-probe.patch`    | **需改**       | 板级 GPIO 依赖，LubanCat 的 HDMI 使能脚不同                                                                                                               |
| `files/hd-rk3588-core.dts`                                             | **不可用**      | include 了 `rk3588-evb4-lp4.dtsi`，构建日志已实证 DTB 编译失败（phandle 引用缺失），见 13.4                                                                         |
| `recipes-bsp/rkbin/…` + `MiniLoaderAll.bin`                            | **不可用**      | 预编译 loader 与 rkbin ini 脱钩，DDR 版本不可追溯；本书改为从 rkbin 源码树构建                                                                                         |
| `recipes-bsp/u-boot/*.cfg`（115200.cfg、emmc-boot.cfg）                   | **不可用**      | 波特率前提就错了；`mmc0` 启动补丁假设了设备序号                                                                                                                    |
| `recipes-connectivity/hd-rk3588-netconfig`                             | **可直接用**     | systemd-networkd 的 `20-wired.network` + preset，本层按同思路重写                                                                                        |
| `packagegroup-rk3588-tools.bb`                                         | **可参考**      | 工具包清单可直接抄                                                                                                                                      |
| `meta-rockchip-updateimg`                                              | **不适用**      | 它的 `update.img` 布局与我们的 extboot 不同（它的 boot 是 FIT 单包）                                                                                            |
| `参考文件/ImageUbuntu_…/parameter.txt`                                     | **仅参考**      | uboot@`0x4000`（8 MiB），**不能**套到 wic 的 `--offset 2M` 上                                                                                           |

### 13.3 与 LubanCat 平台的 7 处结构性差异

| # | 维度        | CHTUZKI                              | LubanCat-4 V1                                            |
| - | --------- | ------------------------------------ | -------------------------------------------------------- |
| 1 | SoC       | RK3588J（全功能）                         | **RK3588S**（裁掉一路 GMAC，`gmac1` 落在 `fe1c0000`）             |
| 2 | 调试串口      | **115200**，`ttyFIQ0`                 | **1500000**，`ttyFIQ0`                                    |
| 3 | 以太网       | 板载（补丁围绕 stmmac/dwmac 通用问题）           | GMAC1 + **RTL8211F**，`rgmii-rxid`，reset `gpio3 PB2`      |
| 4 | 镜像路线      | `update.img` + FIT boot（uboot 8 MiB） | extboot（boot 是 ext2）+ wic（uboot 2 MiB，idblock sector 64） |
| 5 | Loader 来源 | 预编译 `MiniLoaderAll.bin`              | 从 `LubanCat/rkbin master` 的 ini + SPL 现场打包               |
| 6 | dts 供应链   | 自研 dts（且当前编不过）                       | 内核树自带 `rk3588s-lubancat-4-v1.dts`                        |
| 7 | 层抽象       | 无 `conf/machine/include/*.inc`，单板硬写  | `lubancat-<soc>.inc` + 板级 conf，可扩展到六族                    |

### 13.4 它的构建日志暴露的真实失败（很有参考价值）

```
ERROR (phandle_references): /i2c@feca0000/fusb302@22/connector/ports/port@0/endpoint:
  Reference to non-existent node or label "dwc3_0_role_switch"
ERROR (phandle_references): /pcie@fe150000: Reference to non-existent node or label "pcie30x4_clkreqn_m1"
ERROR: Input tree has errors, aborting (use -f to force output)
make[2]: *** […/hd-rk3588-core.dtb] Error 2
```

**教训**：自研 dts `#include "rk3588-evb4-lp4.dtsi"` 是危险的——那个 dtsi 引用了大量 EVB 专有的 label（Type-C role switch、USBDP orientation、PCIe clkreqn），你的板子没有对应节点时 phandle 解析直接失败。

**对 LubanCat 的指导**：工作区里自研的 dts 刻意不 include EVB dtsi（避免带入 EVB 外设与重复定义 `vcc5v0_sys`），这个决定继续坚持。

### 13.5 结论

**定位：配方参考，不是起点仓库。**

- 可借鉴：machine conf 的 `require` 结构、bbclass 只做软链的单一职责、bbappend 钉 `SRCREV`、systemd-networkd 网络配置、stmmac/dwmac 补丁方向、那 4 条 phandle 报错的教训。
- 不可直接用：任何与串口波特率、DDR/loader 来源、分区偏移、dts 相关的具体值。
- 真要拿它当起点，最小改造清单：换 `SERIAL_CONSOLES`、`UBOOT_MACHINE`（实查）、`KERNEL_DEVICETREE`、三处换源、把 FIT boot 换成 extboot + 自建 wks、删掉自带 `MiniLoaderAll.bin` 改从 rkbin 构建。

---

## 14. extboot：设备树切换 / dtbo / uEnv 的全系方案

§7.6 讲过「FIT 单 dtb 限制」和「overlay 的三种投递方式」，§10.5 讲过 rkfw 打包。本章把两者合成一套覆盖 39 块 LubanCat 板卡的机制：**boot 分区从 FIT 单包改成 ext2 文件系统**，dtb、dtbo、内核参数全部变成介质上的文件，用户在板上改文件即可换设备树、开 overlay，不需要重新打包。

### 14.1 为什么这套机制与 SoC 无关

厂商 extboot 的本质只有三件事，都不涉及芯片：

| 组成               | 实现                                                                                   | 是否随 SoC 变 |
| ---------------- | ------------------------------------------------------------------------------------ | --------- |
| boot 分区是**文件系统** | ext2，label=`boot`，parameter 里写 `(boot:bootable)`                                     | 不变        |
| U-Boot 能找到它      | GPT `legacy_bios_bootable` 位 → `part list -bootable` → `distro_bootcmd` 扫 `boot.scr` | 不变        |
| U-Boot 用哪份 dtb   | `CONFIG_ROCKCHIP_EARLY_DISTRO_DTB` 从该分区根读 `rk-kernel.dtb`                            | 不变        |

实测三族（rk3566_rk3568 / rk3576 / rk3588）的 `parameter-extboot.txt`，CMDLINE **逐字节相同**：

```
mtdparts=:0x00004000@0x00004000(uboot),0x00040000@0x00008000(boot:bootable),-@0x00048000(rootfs:grow)
```

`0x40000` 扇区 = 128 MiB，正好是 boot 分区大小（见 14.4 的尺寸断言）。连 `rkImageMaker` 的芯片参数都能自动推断（§10.5），所以打包脚本一条覆盖全系。

### 14.2 六族矩阵

一份镜像服务一族，族内所有板共用（dtb 在 boot 分区里，运行时选）：

| MACHINE           | SoC          | U-Boot 配置                            | 内核 defconfig                      | 默认 dtb                        | uEnv 模板                      | dtb | dtbo |
| ----------------- | ------------ | ------------------------------------ | --------------------------------- | ----------------------------- | ---------------------------- | --- | ---- |
| `lubancat-rk3588` | RK3588/3588S | `rk3588_defconfig`                   | `lubancat_linux_rk3588_defconfig` | `rk3588-lubancat-generic.dtb` | `rk3588/uEnvLubanCat.txt`    | 12  | 278  |
| `lubancat-rk3576` | RK3576       | `rk3576_defconfig`                   | `lubancat_linux_rk3576_defconfig` | `rk3576-lubancat-generic.dtb` | `rk3576/uEnvLubanCat3.txt`   | 6   | 78   |
| `lubancat-rk3568` | RK3568       | `rk3568_defconfig`                   | `lubancat_linux_rk356x_defconfig` | `rk356x-lubancat-generic.dtb` | `rk356x/uEnvLubanCat2.txt`   | 10  | 33   |
| `lubancat-rk3566` | RK3566       | `rk3568_defconfig` + `rk3566.config` | `lubancat_linux_rk356x_defconfig` | `rk356x-lubancat-generic.dtb` | `rk356x/uEnvLubanCat1.txt`   | 6   | 33   |
| `lubancat-rk3562` | RK3562       | `rk3562_defconfig`                   | `lubancat_linux_rk3562_defconfig` | `rk3562-lubancat-generic.dtb` | `rk3562/uEnvLubanCat1HS.txt` | 3   | 42   |
| `lubancat-rk3528` | RK3528       | `rk3528_defconfig`                   | `lubancat_linux_rk3528_defconfig` | `rk3528-lubancat-generic.dtb` | `rk3528/uEnvLubanCatQ1.txt`  | 3   | 15   |

加上板级别名 `lubancat-4-v1`（= rk3588 族 + 钉死 4-V1 的 dtb/uEnv），共 6 族 7 个 machine。

> dtb/dtbo 两列是**该族自己**的产物数（`ls deploy/dtb/<prefix>-*`）。boot 分区里放的是 `deploy/dtb/` 全量，所以 rk356x 两族的 boot 分区各有 **16 份 dtb / 109 份 dtbo**（9+6+generic，33+33+43）——实测数据。

三个容易踩的差异（细节见 §6.5）：RK3566 没有 `rk3566_defconfig`；没有 `CONFIG_CPU_RK3566`（两族挂同一个符号）；`rk3568_defconfig` 的 `CONFIG_LOADER_INI` 是 `RK3566MINIALL.ini`，做 rk3568 必须覆盖。另外 meta-rockchip 没有 `rk3528.inc`，本层自拼一份。

### 14.3 层结构与变量

```
meta-lubancat/
├── conf/machine/include/lubancat-rk{3528,3562,3566,3568,3576,3588}.inc   # 族公共
├── conf/machine/lubancat-rk{3528,3562,3566,3568,3576,3588}.conf          # 族 machine
├── conf/machine/lubancat-4-v1.conf                                       # 板级别名
├── recipes-kernel/linux/linux-rockchip_6.1.bbappend                      # dtbs 任务 + deploy
├── recipes-bsp/u-boot/{u-boot-rockchip.bbappend, files/rk*-lubancat.cfg}  # 片段 + 逐族增量
└── recipes-bsp/extboot/extboot-image.bb                                  # boot-ext2.img
```

族 inc 里与 extboot 相关的变量见 §6.3 的表；板级 conf 只覆盖 `LUBANCAT_DTB` / `LUBANCAT_UENV_DIR` / `LUBANCAT_UENV`。

`boot.cmd` 与 30 份 `uEnvLubanCat*.txt` **不复制进层**，构建时从 `${STAGING_KERNEL_DIR}/arch/arm64/boot/dts/rockchip/uEnv/` 取。厂商版本已正确处理「无 initrd」：`booti ${kernel_addr_r} - ${fdt_addr_r}`。复制一份进层的唯一后果是内核升级后漂移。

dtbo 的编译链本身是齐的（`dts/rockchip/Makefile` 里 `subdir-y := … overlay`，`Makefile.lib` 有 `%.dtbo: %.dts` 规则），缺的只是「没人触发」：`do_compile` 走 `arch/arm64/Makefile` 的 `%.img` 规则，只点名单个 dtb，**从不进 overlay 目录**。所以 bbappend 里补一个任务把 `make dtbs` 跑一次，再整目录 deploy 到 `${DEPLOYDIR}/dtb/`：

```python
do_lubancat_dtbs() {
    sym="CONFIG_CPU_${LUBANCAT_CPU_SYMBOL}"
    grep -q "^${sym}=y" "${B}/.config" || bbfatal "${sym} 未开，overlay 编不出 dtbo"
    oe_runmake -C ${S} O=${B} dtbs            # 必须显式 -C / O，见 §14.9 第 1 条
    bbnote "dtbs: $(ls ${B}/arch/arm64/boot/dts/rockchip/*.dtb | wc -l) dtb, \
$(ls ${B}/arch/arm64/boot/dts/rockchip/overlay/*.dtbo | wc -l) dtbo"
}
addtask lubancat_dtbs after do_compile before do_deploy
```

### 14.4 boot 分区内容与尺寸

```
/                 ext2, label=boot, 128 MiB, GPT bootable
├── boot.scr      mkimage -T script（源：内核树 uEnv/boot.cmd）
├── Image         deploy 的裸内核（boot.cmd 先 load /Image，再回退 /Image-${uname_r}）
├── rk-kernel.dtb ← LUBANCAT_DTB 副本；U-Boot 早期 DTB 与内核 DTB 同源
├── dtb/*.dtb     族内全量（换板 = cp dtb/xxx.dtb rk-kernel.dtb）
├── dtb/overlay/*.dtbo  族内全量（uEnv 里写死的路径就是 /dtb/overlay/）
└── uEnv/uEnv.txt + uEnv/uEnvLubanCat*.txt   当前生效的那份 + 全族模板
```

尺寸核算：单族 dtb 2~3 MiB（实测均值 291 KiB/个）+ dtbo ≤ 0.5 MiB（均值 1.97 KiB/个）+ Image 42 MiB（rk3566 实测 42,213,888 B），128 MiB 余量充足。`make-updateimg.sh` 会断言 `boot-ext2.img` 恰好等于 `0x40000 × 512` 字节，不等就报错——因为 afptool 按参数表的分区大小写。

顺带解决一个老问题：extboot 的 rootfs 是 `-@0x48000(rootfs:grow)`，不再是固定 448 MiB，`lubancat-image-full` 超限的历史问题随之消失。

### 14.5 构建与验证判据

```bash
cd yocto-meta-lubancat
source poky/oe-init-build-env build
ulimit -n 65536
bitbake extboot-image          # 会带出 virtual/kernel 与 virtual/bootloader
./scripts/make-updateimg.sh
```

构建期必须逐项过（大部分写进了 recipe 断言，失败即 `bbfatal`）：

| 检查        | 命令                                                                                                                                                         | 期望                                          |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| U-Boot 能力 | `grep -E 'CMD_(PART\|EXT2\|EXT4\|IMPORTENV\|SOURCE\|BOOTI\|FDT\|DTIMG)\|OF_LIBFDT_OVERLAY\|EARLY_DISTRO' build/tmp/work/*/u-boot-rockchip/*/build/.config` | 全部 `=y`                                     |
| dtfile 编入 | `ls build/tmp/work/*/u-boot-rockchip/*/build/cmd/dtfile.o`                                                                                                 | 存在（**不要**用 `strings u-boot \| grep dtfile`） |
| dtbo 数量   | `ls build/tmp/deploy/images/<machine>/dtb/overlay/*.dtbo \| wc -l`                                                                                         | 与 14.2 表一致                                  |
| boot 内容   | `debugfs -R "ls -l /" …/boot-ext2.img`                                                                                                                     | 有 `boot.scr` / `rk-kernel.dtb` / `uEnv`     |
| cmdline   | `debugfs -R "cat /uEnv/uEnv.txt" …`                                                                                                                        | 含 `console=ttyFIQ0,1500000n8`               |
| 打包几何      | `afptool -unpack` 后的 `parameter.txt`                                                                                                                       | boot 为 `0x40000@0x8000(boot:bootable)`      |

上板后串口按顺序应看到：

```
DTB(Distro): rk-kernel.dtb          ← 早期 dtb 命中 boot 分区
Found U-Boot script /boot.scr       ← distro_bootcmd 扫到脚本
[boot.cmd] run boot.cmd scripts …   ← 模板里的 echo
（无 fdt apply 报错）
```

起来后 `cat /proc/cmdline` 应含 `console=ttyFIQ0,1500000n8 root=/dev/mmcblk0p3`。

### 14.6 用户操作卡（板上改，不用重新打包）

```bash
# 0) 找 boot 分区（extboot 布局：p1=uboot, p2=boot, p3=rootfs）
mount /dev/disk/by-partlabel/boot /mnt     # 或 /dev/mmcblk0p2

# 1) 换设备树：把 dtb/ 里任意一份拷成 rk-kernel.dtb，重启即生效
cp /mnt/dtb/rk3588s-lubancat-4.dtb /mnt/rk-kernel.dtb.new
mv /mnt/rk-kernel.dtb.new /mnt/rk-kernel.dtb      # 先写临时文件再 mv，防掉电留半截
sync && umount /mnt && reboot

# 2) 开 overlay：编辑 uEnv/uEnv.txt，把对应行的 # 去掉
vi /mnt/uEnv/uEnv.txt
#   enable_uboot_overlays=1          （必须为 1，否则整段不解析）
#   #overlay_start
#   dtoverlay=/dtb/overlay/rk3588s-lubancat-4-hdmi0-vp0-overlay.dtbo
#   #overlay_end
# 一行一个 dtbo；带参数写 dtoverlay=xxx.dtbo,param=value
# 验证：dmesg 里出现该设备，或 ls /proc/device-tree 看新节点

# 3) 改内核参数：改 uEnv.txt 的 cmdline= 行（每行都要是 KEY=VALUE）
#    console 必须带波特率，写错表现为「串口全黑但系统起来了」

# 4) 想试一个不在 uEnv 候选列表里的 dtbo：把它放进 /dtb/overlay/ 再加一行即可

# 5) 让切板脚本重新认一次（换了 dtb 后想复位）
rm -f /mnt/.board-detected
```

`uEnv.txt` 里的 `size=0x1000000` 是 `dtfile` 读文本时的 malloc 上限，不要删。

### 14.7 边界：SG200x 不在本机制内

LubanCat 内核树里搜不到任何 `sg200` / `cvitek` 内容（`arch/arm64/boot/dts/allwinner` 只有 sun50i 系列），SDK 的 `device/`、`tools/`、`build.sh` 里也没有 cvi 打包链。SG200x 走的是 fsbl + opensbi + `fip.bin`，与 rkbin / afptool / rkfw 完全无关，需要独立内核树与独立 meta 层。**本机制只覆盖 Rockchip 六族。**

### 14.8 本章相关的排查条目

| 症状                                   | 根因                                                                        | 处置                                                              |
| ------------------------------------ | ------------------------------------------------------------------------- | --------------------------------------------------------------- |
| 串口全黑，但网口/HDMI 正常                     | uEnv 的 `cmdline=` 覆盖了 dts bootargs，且没带波特率                                 | 改成 `console=ttyFIQ0,1500000n8`；`debugfs cat` 复核                 |
| `Found U-Boot script` 之后停在 `booti` 前 | `/Image` 不在分区根，或 `uname_r` 写错导致两次 load 都失败                                | `debugfs ls /` 看文件名；`uname_r` 留空走 `/Image`                      |
| overlay 写了但没生效                       | `enable_uboot_overlays=0`，或 U-Boot 没编进 `dtfile`，或 dtbo 不在 `/dtb/overlay/` | 串口看 `[boot.cmd] dtoverlay from /uEnv/uEnv.txt`；查 `cmd/dtfile.o` |
| `fdt apply` 报 `FDT_ERR_NOTFOUND`     | 基 dtb 没带 `__symbols__`（缺 `CONFIG_DTC_SYMBOLS=y`）                          | 检查 `.config`，重编内核                                               |
| 刷完卡在 `Waiting for root device`       | 用了 `EXTBOOT=0` 的旧参数表却没配对 boot.img，或 rootfs 分区起点不对                         | 确认 `CMDLINE` 里 rootfs 是 `-@0x48000(rootfs:grow)`                |
| boot 写不下 / `afptool` 报越界             | `boot-ext2.img` 与 parameter 的 boot 大小不一致                                  | 脚本已断言 128 MiB 相等，改一处必须改另一处                                      |

### 14.9 首次构建实测记录（只有跑起来才会暴露的坑）

这一节是把整套机制从零跑通时踩到的，都已写进 recipe 做了防护。

| # | 现象                                                         | 根因                                                                                                                        | 处置                                                                                           |
| - | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| 1 | `make: *** No rule to make target 'dtbs'`                  | bitbake 任务默认 cwd 是 `${WORKDIR}`，而 kernel-yocto 的 `do_compile` 自己会 `cd ${B}`；`dtbs` 任务没 cd，`O=` 构建目录的 Makefile 是 include 桩 | `oe_runmake -C ${S} O=${B} dtbs`（已内置）                                                        |
| 2 | `bitbake extboot-image` 成功，但 `deploy/` 里没有 `boot-ext2.img` | 只 `inherit deploy` 时 `do_build` 没串 `do_deploy`（`listtasks` 里只有 `do_deploy_setscene`）                                      | `addtask deploy after do_compile before do_build`                                            |
| 3 | boot 分区里 0 个 dtb（只有 `rk-kernel.dtb`）                       | `LUBANCAT_FAMILY_ALL_DTBS` 只写在族 machine conf 里，板级别名没继承到                                                                   | recipe 里补 `?= "1"` 兜底                                                                        |
| 4 | 主机装了 `u-boot-tools` 仍报「需要 mkimage」                         | bitbake 任务的 PATH 只有 hosttools + sysroot-native                                                                            | 按绝对路径逐个试（`${STAGING_BINDIR_NATIVE}` → `/usr/bin` → `/usr/local/bin`），并 `bbwarn` 说明非 hermetic |
| 5 | `$'\r': command not found`                                 | 在 Windows 上编辑过的 `.sh`/`.bb` 带 CRLF                                                                                        | 上传前 `sed -i 's/\r$//'` 或 `dos2unix`                                                          |
| 6 | 重编了 minimal，烧进去却没有新包                                       | 打包脚本按**字母序**取 rootfs，`lubancat-image-full` 永远在前                                                                           | 改成 `ls -1t`（按 mtime）并打印选了哪份；支持 `IMAGE=` / `ROOTFS=`                                          |

另外两个**不要**踩的：

- **别把 `u-boot-tools-native` 加进 DEPENDS**。poky 的 u-boot-tools 只从 `source.denx.de` 拉，实测 25 KB/s，浅克隆要一小时；它唯一提供的就是 `mkimage` 一个命令。要完全复现再单独 `bitbake u-boot-tools-native`。
- **给 `source.denx.de` 加 `PREMIRRORS` 改写到 gh-proxy 会产出坏包**（`gzip: stdin: not in gzip format`）。git 协议的镜像重写不要走 http 代理前缀。

### 14.10 一次完整的验证输出（rk3588s，实测）

```
$ ls -lh build/tmp/deploy/images/lubancat-4-v1/boot-ext2.img
-rw-r--r-- 1 dev dev 128M ... boot-ext2.img
$ file boot-ext2.img
Linux rev 1.0 ext2 filesystem data, UUID=..., volume name "boot" (large files)

$ debugfs -R "ls -l /" boot-ext2.img
 12  100644  43760128  Image
 13  100644      4640  boot.scr
 14   40755      1024  dtb
295  100644    265177  rk-kernel.dtb
296   40755      1024  uEnv
$ debugfs -R "ls /dtb" | grep -c dtb            → 12
$ debugfs -R "ls /dtb/overlay" | grep -c dtbo   → 278
$ debugfs -R "cat /uEnv/uEnv.txt"
cmdline="earlyprintk console=ttyFIQ0,1500000n8 console=tty1 consoleblank=0 loglevel=7 rootwait rw rootfstype=ext4"

$ ./make-updateimg.sh
==> 芯片型号: RK3588（由 loader.bin 头部推断）
rootfs,Add file: ./Image/rootfs.img done,offset=0x847a000,size=0x28211800,flash_address=0x00048000
==> rkImageMaker -RK3588
-rw-r--r-- 1 dev dev 776M update.img
魔数检查（应为 RKFW）: RKFW

$ afptool -unpack 后
CMDLINE: mtdparts=:0x00004000@0x00004000(uboot),0x00040000@0x00008000(boot:bootable),-@0x00048000(rootfs:grow)
boot.img: Linux rev 1.0 ext2 filesystem data, volume name "boot"   size=0x8000000 (128 MiB)
uboot.img: size=0x400000 (4 MiB)
```

### 14.11 首次启动自动扩容（已实现）

`parameter.txt` 里 rootfs 是 `-@0x00048000(rootfs:grow)`，afptool 刷写时**分区**已经拉到磁盘末尾；缺的只是 ext4 **文件系统**没扩（厂商 debian 的 `resize-disk.sh` 也只做文件系统扩容）。

本层 `recipes-core/lubancat-firstboot/`：

| 文件                               | 作用                                                                                                           |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `lubancat-resize-rootfs.sh`      | 从 `/proc/mounts` 取根设备 → `/sys/class/block/*/partition` 取分区号 → `resize2fs`（分区没到末尾时打日志并尝试 `growpart`，镜像里没装就跳过） |
| `lubancat-resize-rootfs.service` | oneshot，`ConditionPathExists=!/var/lib/lubancat/.rootfs-resized`                                             |
| `lubancat-firstboot.bb`          | 装脚本 + 启用 unit；`RDEPENDS = e2fsprogs-resize2fs`                                                               |

已并入 `packagegroup-lubancat-base`，三个镜像都会带上。脚本刻意只用 `resize2fs`，信息全部从 `/proc/mounts` 与 `/sys/class/block` 读，不依赖 `lsblk`/`findmnt`/`parted`。

验证（板子上）：

```bash
systemctl status lubancat-resize-rootfs     # 首次启动后应为 active (exited)
journalctl -u lubancat-resize-rootfs | tail
df -h /                                      # 应接近 eMMC 容量
ls -l /var/lib/lubancat/.rootfs-resized      # 幂等标记
# 分区是否真的 grow 了（决定脚本只需 resize2fs 还是还要 growpart）：
cat /sys/class/block/mmcblk0p3/start /sys/class/block/mmcblk0p3/size /sys/class/block/mmcblk0/size
```

### 14.12 族镜像：generic dtb 启动 + 首启切板（已实现）

厂商 `boot_init.sh` 的做法：**generic dtb 先起来 → 认板 → 换 dtb/uEnv → 重启**。不是「运行时切」，因为 dtb 是内核启动参数，U-Boot 只在启动瞬间读一次。本层按同一思路实现，两处刻意不同：

|           | 厂商 Debian                              | 本实现                       | 原因                                                                                            |
| --------- | -------------------------------------- | ------------------------- | --------------------------------------------------------------------------------------------- |
| 换 dtb 的方式 | `ln -sf dtb/x.dtb /boot/rk-kernel.dtb` | `cp` 覆盖 + `mv` 原子替换       | U-Boot 2017.09 里有 `ext4fs_read_symlink`（`fs/ext4/ext4_common.c:2177`），但无法在硬件上验证它跟随软链的行为；拷贝零风险 |
| 触发条件      | 首次启动无条件执行                              | 先 `cmp` 目标文件，内容一致就只打标记不重启 | 板级别名镜像本来就是对的那份，不该白重启一次                                                                        |

**实现**：

| 文件                              | 作用                                                                                                                                                                                                             |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lubancat-board-detect.sh`      | `compatible` 取 SoC → 归并 family（rk3566/3568→rk356x，rk3588/3588s→rk3588，rk3528a→rk3528）→ 找 **saradc** 的 iio 设备（不假设 `iio:device0`）→ 读 ch2/ch3 raw → 按阈值表转 0~7 → 拼 4 位 board_id → 查表 → 拷 dtb 与 uEnv → 打标记 → reboot |
| `lubancat-board-detect.service` | oneshot，`After=local-fs.target`、`Before=multi-user.target`；幂等判断在脚本内（要看 boot 分区上的标记，unit 的 `ConditionPathExists` 在挂载前不可靠）                                                                                       |
| `board-table`                   | 40 条映射（rk3528 3 / rk3562 4 / rk356x 21 / rk3576 3 / rk3588 9），由厂商 `board_info()` **机械转换**（rk3128 剔除），装到 `/usr/share/lubancat/board-table`                                                                      |

ADC 阈值表与厂商一致（12bit：916/1376/1840/2380/2928/3432/3900/4096；10bit 是其 1/4），位数用 `in_voltage_scale` 的整数位判断（`1.7578125`→10bit，`0.439453125`→12bit），不依赖 `bc`/`awk` 做浮点。

**默认值**：六个族 machine 的 `LUBANCAT_DTB` 都是 `*-generic.dtb`，`LUBANCAT_UENV` 用 generic 模板（`enable_uboot_overlays=0`；切到板级 dtb 时连 uEnv 一起换，overlay 才生效）。`lubancat-4-v1` 这个板级别名仍钉死 `rk3588s-lubancat-4-v1.dtb`。

**boot 分区里现在有什么**（rk3588 族）：

```
/rk-kernel.dtb                 ← 由 LUBANCAT_DTB 决定（族镜像=generic，板级=对应板）
/dtb/*.dtb                     12 份（族内全量，切板脚本从这里拷）
/dtb/overlay/*.dtbo            278 份
/uEnv/uEnv.txt                 当前生效的那份（cmdline 已改成 1500000n8）
/uEnv/uEnvLubanCat*.txt        全族板级模板（**全部**已 patch cmdline，可直接被拷成 uEnv.txt）
/uEnv/uEnvLubanCat.txt         generic 模板（enable_uboot_overlays=0）
```

**上板验证**：

```bash
# 1) 编族镜像：MACHINE 选族级（例如 lubancat-rk3568），target 带上 extboot-image
bitbake lubancat-image-full extboot-image
./scripts/make-updateimg.sh

# 2) 烧写后第一次启动应看到（串口 + journal）
#    DTB(Distro): rk-kernel.dtb            ← 此时是 generic 那份
#    lubancat-board: compatible=rockchip,rk3588s-lubancat soc=rk3588s family=rk3588
#    lubancat-board: adc ch2=01 ch3=02 board_id=0102
#    lubancat-board: 识别为 LubanCat-4 v1 -> dtb=rk3588s-lubancat-4-v1.dtb uEnv=uEnvLubanCat4-V1.txt
#    lubancat-board: 已切换到 LubanCat-4 v1，重启生效

# 3) 自动重启一次后：
cat /sys/firmware/devicetree/base/model        # LubanCat-4 V1
cat /proc/cmdline                              # 仍含 console=ttyFIQ0,1500000n8
systemctl status lubancat-board-detect         # active (exited)
ls /run/lubancat-boot 2>/dev/null              # 已卸载，标记在 boot 分区：.board-detected
```

**回退**：`mount /dev/disk/by-partlabel/boot /mnt && cp /mnt/dtb/<正确的>.dtb /mnt/rk-kernel.dtb && rm -f /mnt/.board-detected && reboot`。标记文件在 boot 分区，重刷镜像即复位；只重装 rootfs 不会误判。

**首启没切板的排查顺序**：

1. `systemctl status lubancat-board-detect` 没有这个 unit → **rootfs 里没有包**，先确认烧的 `update.img` 装的是哪份 rootfs（`make-updateimg.sh` 会打印选了最新的一份）。
2. unit 在但没切 → `journalctl -u lubancat-board-detect` 看是「找不到 boot 分区」还是「board_id 不在表里」。前者说明 `/dev/disk/by-partlabel/boot` 不存在（脚本会退到 `/proc/cmdline` 的 `root=` + `boot_part=` 推导）；后者把日志里的 `adc ch2/ch3` 发出来对阈值。
3. 切了但重启后还是老 dtb → 看 boot 分区里 `.board-detected` 是否生成、`rk-kernel.dtb` 的 md5 是否变成目标 dtb。

**已知边界**：

- `board-table` 里个别 dtb/uEnv 在本内核树里不存在（如 `rk3566-lubancat-cm4` 缺对应 uEnv），脚本先判断文件存在，不存在就保持当前 dtb 并打日志，不会把板子写死。
- 板子上必须有 saradc 的 iio 设备；generic dtb 与板级 dtb 都使能了 `&saradc`。某族 generic dtb 没使能时脚本会打「没有 saradc」并保持 generic（仍能启动）。

### 14.13 HDMI 那个补丁还要不要

`0001-arm64-dts-lubancat-4-v1-enable-hdmi0-vp0.patch` 做的事（给 `rk3588s-lubancat-4-v1.dts` 加一行 `#include "rk3588s-lubancat-4-hdmi0-vp0.dtsi"`）**厂商已经用 overlay 做了一遍**：

- `boot 分区/dtb/overlay/rk3588s-lubancat-4-hdmi0-vp0-overlay.dtbo` 与该 dtsi 的 fragment 一一对应（hdmi0 状态 + `enable-gpios`、route_hdmi0→vp0、hdmi0_in_vp0、hdptxphy、关 vp1/vp2、hdmi0_sound、i2s5_8ch）；
- 而且 `uEnvLubanCat4-V1.txt` 里这行**默认是打开的**。

所以：

| 场景                                     | 没有补丁会怎样   |
| -------------------------------------- | --------- |
| extboot（默认，uEnv 开着这条 overlay）          | 正常，HDMI 亮 |
| 用户把 `enable_uboot_overlays` 改成 0       | HDMI 黑    |
| `EXTBOOT=0`（回到 boot.img 的逃生路径）         | HDMI 黑    |
| `fdt apply` 失败（基 dtb 丢了 `__symbols__`） | HDMI 黑    |

结论：**现在别删**。它是「overlay 机制不可用时的兜底」，成本只有 4 行，且与 overlay 同时生效是幂等的（两边都设 `status=okay` + 同一组 gpio）。等 extboot 在板上稳定跑过一轮（含故意关 overlay 的对照实验）之后，再删掉、把 HDMI 的唯一来源收敛到 overlay——那时才符合「基 dtb 保持中性」的多板架构。删的时候记得同步给 `EXTBOOT=0` 加一句说明。

---

## 附录 A 变量速查表

**机器与层**

| 变量                                    | 取值                                           | 来源                       | 备注                     |
| ------------------------------------- | -------------------------------------------- | ------------------------ | ---------------------- |
| `MACHINE`                             | `lubancat-4-v1` / `lubancat-rk35xx`          | local.conf / kas         | 不含下划线                  |
| `DISTRO`                              | `poky`                                       | local.conf               |                        |
| `MACHINEOVERRIDES`                    | `lubancat:lubancat-rk3588:lubancat-rk3588s:` | 本层 inc                   | 不动 `SOC_FAMILY`        |
| `BBFILE_PRIORITY_lubancat`            | `10`                                         | layer.conf               |                        |
| `BBFILE_PRIORITY_realtime`            | `15`                                         | meta-realtime/layer.conf | 必须高于 lubancat          |
| `LAYERVERSION_lubancat` / `_realtime` | `0.1`                                        | layer.conf               | 与 tag 的 MAJOR.MINOR 一致 |

**内核 / U-Boot**

| 变量                                   | 取值                                                 | 来源              | 备注                              |
| ------------------------------------ | -------------------------------------------------- | --------------- | ------------------------------- |
| `KERNEL_DEVICETREE`                  | `rockchip/<board>.dtb`                             | 板级 conf         | 前缀必须 `rockchip/`                |
| `LUBANCAT_DTB`                       | `*-generic.dtb` / 板级 dtb                           | 族 / 板级 conf     | 决定 `/rk-kernel.dtb`             |
| `KBUILD_DEFCONFIG`                   | `lubancat_linux_<soc>_defconfig`                   | 本层 inc          | 含 FIQ console                   |
| `KERNEL_FEATURES`                    | `""`（forcevariable）                                | kernel bbappend | 必须 force                        |
| `LUBANCAT_KERNEL_BRANCH` / `_SRCREV` | `lbc-develop-6.1` / `a0c67234…`                    | kernel bbappend | RT 层强赋值覆盖                       |
| `KERNEL_MODULE_AUTOLOAD`             | `rtl8188ee rtw88_8822ce rtw89_8851be rtw89_8852be` | kernel bbappend | 名字是 `.ko` basename              |
| `SERIAL_CONSOLES` / `_CHECK`         | `1500000;ttyFIQ0`                                  | 本层 inc          | 不能写 `ttyS2`                     |
| `UBOOT_MACHINE`                      | `rk3588_defconfig` 等                               | 板级 conf         | 以实查为准                           |
| `LUBANCAT_UBOOT_FRAGMENT`            | `""` / `rk3566.config`                             | 族 inc           | 只有 rk3566 非空                    |
| `LUBANCAT_RKBIN_INI`                 | `RK3588MINIALL.ini` 等                              | 族 inc           | 决定 loader ini                   |
| `LUBANCAT_DDR_BIN`                   | `rk3588_ddr_lp4_1848MHz_lp5_2112MHz_v1.19.bin` 等   | 族 inc           | 改写 ini 两处 + 断言                  |
| `SRCREV` / `SRCREV_rkbin`            | `a564b1d9…` / `74213af1…`                          | u-boot bbappend | 需 `SRCREV_FORMAT=default_rkbin` |

**镜像 / 分区**

| 变量                            | 取值                                | 来源               | 备注                             |
| ----------------------------- | --------------------------------- | ---------------- | ------------------------------ |
| `WKS_FILE`                    | `lubancat-gptdisk.wks.in`         | 本层 inc           | 无 trust 分区                     |
| `IMAGE_FSTYPES`               | `wic.gz ext4 tar`                 | 本层 inc           |                                |
| `LUBANCAT_CMDLINE`            | 含 `console=ttyFIQ0,1500000n8`     | 族 inc            | uEnv 的 `cmdline=`              |
| `LUBANCAT_UENV_DIR` / `_UENV` | `rk3588` / `uEnvLubanCat4-V1.txt` | 板级 conf          | 取内核树模板                         |
| `LUBANCAT_FAMILY_ALL_DTBS`    | `1`                               | 族 machine        | 全族 dtb 进 boot 分区               |
| `EXTBOOT_SIZE_MB`             | `128`                             | extboot-image.bb | 必须与 parameter 的 `0x40000` 扇区相等 |
| `LUBANCAT_FIRSTBOOT_SWITCH`   | `1`                               | firstboot bb     | 0 则只装扩容服务                      |
| `INIT_MANAGER`                | `systemd`                         | local.conf       |                                |
| `PACKAGE_CLASSES`             | `package_ipk`                     | local.conf       |                                |
| `DISTRO_FEATURES:append`      | ` pam`                            | local.conf       | weston 需要                      |

---

## 附录 B 验收清单

**构建期**

- [ ] `bitbake -p` 通过；`bitbake -e virtual/kernel` 的 `KBUILD_DEFCONFIG` / `KERNEL_IMAGETYPE_FOR_MAKE` 符合预期
- [ ] `deploy/images/<machine>/` 里有 `Image`、`dtb/*.dtb`、`dtb/overlay/*.dtbo`、`boot-ext2.img`、`loader.bin`、`uboot.img`
- [ ] `boot-ext2.img` 恰好 128 MiB，`debugfs ls /` 有 `boot.scr` / `rk-kernel.dtb` / `dtb/` / `uEnv/`
- [ ] `make-updateimg.sh` 打印的芯片型号正确，`head -c 4 update.img` 为 `RKFW`
- [ ] `tools/rkpack` 校验通过：`cd tools/rkpack && sha256sum -c SHA256SUMS`

**第一次上电（minimal）**

- [ ] 串口 1500000 看到 DDR → U-Boot → `DTB(Distro): rk-kernel.dtb` → `Found U-Boot script /boot.scr` → `Starting kernel`
- [ ] `uname -r` 含 `6.1.99` 与 `lubancat`（RT 为 `6.1.99-rt36-lubancat`）
- [ ] 出现 `login:`，`root` 可登录
- [ ] `cat /proc/cmdline` 含 `console=ttyFIQ0,1500000n8 root=/dev/mmcblk0p3 boot_part=2`
- [ ] `systemctl status lubancat-resize-rootfs` 为 `active (exited)`，`df -h /` 接近 eMMC 容量
- [ ] 族镜像：`journalctl -u lubancat-board-detect` 显示认板成功并重启过一次；板级别名不重启

**网络（net）**

- [ ] `ip -br link` 有 `end1`；`ethtool end1` 见 `1000Mb/s Full`
- [ ] `ping -c 3 <网关>` 通；`ip -s link show end1` 计数增长
- [ ] `ssh root@<ip>` 可登录
- [ ] 无线（插卡时）：`lsmod` 有对应驱动，`/lib/firmware/rtw89/` 有固件，`iw dev wlan0 link` 关联成功，`networkctl status wlan0` 有默认路由

**图形 / NPU（full）**

- [ ] `ls /sys/class/drm/` 有 `card0-HDMI-A-1`，`status` 为 `connected`
- [ ] `cat /sys/class/misc/mali0/device/gpuinfo` 可读；`kmscube` 出画面
- [ ] `weston --backend=drm-backend.so` + `weston-simple-egl` 有输出  
  |  |  |  
  | --- | --- |
- [ ] `dmesg | grep -i rknpu` 有 `Initialized rknpu`；`/sys/kernel/debug/rknpu/load` 可读
- [ ] （可选）自备 `librknnrt.so` 后跑一次 `rknn_init` / `rknn_run`，`/sys/kernel/debug/rknpu/load` 有变化

---

## 附录 C 命令卡

```bash
# ---- 环境 ----
cd $WS && source poky/oe-init-build-env build
export LANG=en_US.UTF-8; ulimit -n 65536
source ./scripts/setup-mirror.sh                  # 国内网络

# ---- 构建（kas）----
kas build kas/lubancat.yml                                            # 默认 4-v1 + minimal
KAS_MACHINE=lubancat-rk3568 kas build kas/lubancat.yml                # 换芯片
KAS_TARGET="lubancat-image-full extboot-image" kas build kas/lubancat.yml   # 换镜像
KAS_BUILD_DIR=$PWD/build-rt kas build kas/lubancat.yml:kas/realtime.yml     # RT 内核

# ---- 构建（手动）----
bitbake lubancat-image-minimal extboot-image
bitbake virtual/kernel -c cleansstate && bitbake lubancat-image-minimal
bitbake -c compile -f -v u-boot-rockchip          # 强制重跑，看 DDR 改写日志

# ---- 信息 ----
bitbake-layers show-layers
bitbake-layers show-recipes 'linux-*'
bitbake-layers show-appends u-boot-rockchip
bitbake -e | grep -E '^(MACHINE|SERIAL_CONSOLES|LUBANCAT_)'
bitbake -e virtual/kernel | grep -E '^(SRC_URI|SRCREV|KBUILD_DEFCONFIG|KERNEL_DEVICETREE)='
bitbake -e u-boot-rockchip | grep -E '^(UBOOT_MACHINE|RK_UBOOT_CFG|LUBANCAT_RKBIN_INI|LUBANCAT_DDR_BIN)'

# ---- 产物检查 ----
ls -l build/tmp/deploy/images/lubancat-4-v1/
debugfs -R "ls -l /" build/tmp/deploy/images/lubancat-4-v1/boot-ext2.img
debugfs -R "cat /uEnv/uEnv.txt" build/tmp/deploy/images/lubancat-4-v1/boot-ext2.img
strings build/tmp/deploy/images/lubancat-4-v1/idblock.img | grep -iE 'ddr|^typ'
sgdisk -v build/tmp/deploy/images/lubancat-4-v1/*.wic
dtc -I dtb -O dts -o /tmp/x.dts build/tmp/deploy/images/lubancat-4-v1/rk3588s-lubancat-4-v1.dtb
fdtget /tmp/x.dts /chosen bootargs

# ---- 打包与烧写 ----
./scripts/make-updateimg.sh
MACHINE=lubancat-rk3568 IMAGE=lubancat-image-full \
  DEPLOY=$PWD/build/tmp/deploy/images/lubancat-rk3568 \
  WORK=$PWD/build/updateimg-rk3568 ./scripts/make-updateimg.sh
sudo upgrade_tool uf build/updateimg/update.img
sudo ./scripts/flash-emmc.sh build/tmp/deploy/images/<machine>/*.wic.gz

# ---- 串口 ----
picocom -b 1500000 -d 8 -p n /dev/ttyUSB0

# ---- 板上 ----
cat /proc/cmdline; uname -r; findmnt /
ip -br link; ethtool end1; ip route show default
journalctl -u lubancat-board-detect -b | tail
systemctl status lubancat-resize-rootfs weston
ls /sys/class/drm/; cat /sys/class/misc/mali0/device/gpuinfo
dmesg | grep -iE 'vop2|rknpu|mali|rtw'
ls /sys/kernel/debug/rknpu/ && cat /sys/kernel/debug/rknpu/load
```

---

### 变更记录

| 日期         | 内容                                                                                                                                                                               |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-11-02 | 初版。U-Boot 源 `LubanCat/u-boot:main`，rkbin 源 `LubanCat/rkbin:master`，内核 `LubanCat/kernel:lbc-develop-6.1`；主线 = poky scarthgap + meta-rockchip + meta-lubancat                      |
| 2026-11-04 | 补 extboot（第 14 章）：boot 分区改 ext2、dtbo 全族构建、首启扩容与切板                                                                                                                                |
| 2026-11-05 | 补 PREEMPT_RT 层（§7.8）、镜像与包组更新、无线章节（§7.7）实测结论                                                                                                                                      |
| 2026-11-10 | 按当前仓库状态重写：六族机器配置（§6.5）、DDR 1848 档与 ini 双处改写（§8.7）、update.img 打包脚本行为（§10.5）、镜像与包组（§9）、验收口径改为按镜像分级（§1.2 / 附录 B），删除已不存在的 `lubancat-rk356x.inc` / `recipes-kernel/dto` / SDK 打包目录等内容 |
