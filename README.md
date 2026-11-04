# yocto-meta-lubancat

Yocto layer + kas project + helper scripts for **LubanCat** (野火) boards based on Rockchip SoCs.

Build a bootable image with one command, then switch device trees and device-tree overlays
**on the board** without repacking anything.

```bash
git clone https://github.com/<your-org>/yocto-meta-lubancat.git && cd yocto-meta-lubancat
sudo ./scripts/host-deps.sh
kas build kas/lubancat.yml                # 拉 4 个上游层 + 编译 minimal 镜像 + boot 分区
./scripts/make-updateimg.sh               # 打成 rkfw update.img（工具已随仓库提供）
```

| | |
|---|---|
| Yocto series | scarthgap (5.0), poky + systemd |
| SoCs | RK3588 / RK3588S / RK3576 / RK3568 / RK3566 / RK3562 / RK3528 |
| Boards | 39 board DTs across 6 family MACHINEs, one image per family |
| Kernel / U-Boot | Linux 6.1 (LubanCat `lbc-develop-6.1`) / U-Boot 2017.09 (LubanCat `main`) |
| Serial console | **UART2 @ 1500000 8N1**, kernel node `ttyFIQ0` |
| License | MIT (layer & scripts). Vendor binaries in `tools/rkpack/` are **not** MIT — see `THIRD-PARTY.md` |

> **Not** covered: SG200x (Allwinner core) — different boot chain (fsbl + opensbi + fip.bin),
> needs its own kernel tree and meta layer. No Debian/Ubuntu rootfs, no mainline kernel, no OTA.

---

## 1. 这是什么

三样东西合在一个仓库里：

| 部分 | 位置 | 说明 |
|---|---|---|
| Yocto 层 | `meta-lubancat/` | 机器配置、kernel/u-boot bbappend、镜像 recipe、首启服务 |
| kas 工程 | `kas/lubancat.yml` + `kas/lubancat.lock.yml` | 一条命令拉齐 poky / meta-arm / meta-openembedded / meta-rockchip 并按 commit 钉死 |
| 辅助脚本 | `scripts/` | 主机依赖、拉层、国内加速、打 `update.img`、烧 wic |

**三条必读警告**

1. **串口是 1500000 8N1，内核里叫 `ttyFIQ0`**（不是 `ttyS2`，不是 115200）。
   而且 `uEnv.txt` 的 `cmdline=` 会**覆盖** dts 里的 bootargs——写成 `console=ttyFIQ0`（漏波特率）
   的表现是"串口全黑，但系统其实起来了、能 ping 通"。
2. **磁盘 ≥ 300 GB，且必须是本地 ext4/xfs**。放在 NTFS / 9p / 网络盘上会慢 5~10 倍或直接报错。
3. `update.img` 需要的 `afptool` / `rkImageMaker` **已随仓库提供**（`tools/rkpack/`），
   不需要安装 Rockchip SDK；但它们是 x86-64 ELF，ARM 主机与 macOS 用不了（那种情况走 wic 路线）。

---

## 2. 支持范围

一份**族镜像**覆盖族内全部板卡：boot 分区里放全族 `dtb/`、`dtb/overlay/`、`uEnv/`，
首次启动由 `lubancat-board-detect` 读 SARADC 板卡 ID，把 `rk-kernel.dtb` 与 `uEnv/uEnv.txt`
换成这块板对应的那份，重启一次生效。

| MACHINE | SoC | 板型 | 默认 dtb | 验证级别 |
|---|---|---|---|---|
| `lubancat-4-v1` | RK3588S | LubanCat-4 V1（板级别名，不切板） | `rk3588s-lubancat-4-v1.dtb` | **真机上板**：串口 / 有线网 / HDMI / GPU / NPU 全部通过 |
| `lubancat-rk3588` | RK3588 / 3588S | LubanCat-4 / 4IO / 5 / 5-V2 / 5IO / 5IOB / 5IOF / 5IOI / 5IO-AIBOX1 | `rk3588-lubancat-generic.dtb` | 编译级（12 dtb / 278 dtbo） |
| `lubancat-rk3576` | RK3576 | LubanCat-3 / 3-V2 / 3IO / 3IO-test | `rk3576-lubancat-generic.dtb` | 编译级（6 / 78） |
| `lubancat-rk3568` | RK3568 | LubanCat-2 / 2-V1/V2/V3 / 2H / 2IO / 2N / 2N-V2/V3 | `rk356x-lubancat-generic.dtb` | 编译级（10 / 33） |
| `lubancat-rk3566` | RK3566 | LubanCat-1 / 1H / 1IO / 1N / 0 / CM4 | `rk356x-lubancat-generic.dtb` | 编译级（6 / 33） |
| `lubancat-rk3562` | RK3562 | LubanCat-1HS / 1HS-test | `rk3562-lubancat-generic.dtb` | 编译级（3 / 42） |
| `lubancat-rk3528` | RK3528 | LubanCat-Q1 / Q1IO | `rk3528-lubancat-generic.dtb` | 编译级（3 / 15） |

"编译级"= `bitbake -p` 通过、变量核对正确、dtb/dtbo 齐全，**没有上过板**。
完整版本矩阵（层 commit、BSP SRCREV）见 [`docs/VERSION-MATRIX.md`](docs/VERSION-MATRIX.md)。

**边界**

- SG200x：本内核树里没有任何 `sg200`/`cvitek` 内容，SDK 里也没有 cvi 打包链，不在范围内。
- 只提供 poky（systemd）rootfs；不提供 Ubuntu/Debian 根文件系统。
- 不做主线内核、OTA、双系统、安全启动。
- `lubancat-5-rk3588-pcie_defconfig` 关闭了 `EARLY_DISTRO_DTB`，不能用于 extboot；族机器固定用 `rk3588_defconfig`。

---

## 3. 宿主机

### 3.1 要求

| 项 | 要求 | 为什么 |
|---|---|---|
| 发行版 | Ubuntu 22.04 / 24.04、Debian 12 | scarthgap 官方支持范围 |
| CPU | ≥ 8 核（推荐 16+） | 全量约 5000~9000 个任务 |
| 内存 | ≥ 16 GiB（推荐 32 GiB+） | 单 gcc/链接进程峰值 2~4 GiB |
| 磁盘 | **≥ 300 GB 空闲**，本地 ext4/xfs | downloads 35~60G + sstate 45~80G + tmp 60~120G |
| 文件系统 | 支持硬链接；**不能**是 NTFS / exFAT / 9p / 网络盘 | 否则 `Invalid cross-device link` 或慢 10 倍 |
| locale | `en_US.UTF-8` | 非 UTF-8 会让 bitbake 解析期抛 `UnicodeDecodeError` |
| 文件句柄 | `ulimit -n 65536` | 默认 1024，并发一上来就 `Too many open files` |
| 权限 | **不要用 root 构建**（只有装依赖要 sudo） | root 构建会污染 sstate 权限 |

### 3.2 一键安装

```bash
sudo ./scripts/host-deps.sh
```

它会：装 Yocto 必需包（含 `chrpath cpio diffstat gawk lz4 locales python3-git/jinja2/pexpect/subunit`）
→ 装 wic/分区工具（`parted gdisk dosfstools mtools e2fsprogs dtc`，失败只告警）→ 装 `u-boot-tools`
（提供 `mkimage`）→ 以**你的账号**（不是 root）`pip install --user kas` → 检查 locale → 打印磁盘/内存。

### 3.3 手工等价命令（不想跑脚本时）

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential chrpath cpio debianutils diffstat file gawk gcc git \
  iputils-ping libacl1 liblz4-tool locales python3 python3-git python3-jinja2 \
  python3-pexpect python3-pip python3-subunit python3-venv socat texinfo unzip wget xz-utils zstd \
  parted gdisk dosfstools mtools e2fsprogs device-tree-compiler u-boot-tools bmap-tools
sudo locale-gen en_US.UTF-8
```

> 不要装 `python3-wic`：Ubuntu 的 apt 源里没有这个包（wic 由 poky 自带），装了会让整条
> `apt-get install` 失败。

### 3.4 每个 shell 都要设

```bash
export LANG=en_US.UTF-8
ulimit -n 65536
```

建议写进 `~/.bashrc`。

### 3.5 自检

```bash
locale                  # 能看到 en_US.UTF-8
ulimit -n               # 65536
df -h .                 # ≥ 300G 可用
nproc; free -g
```

**这步失败的典型现象**

| 现象 | 原因 |
|---|---|
| `UnicodeDecodeError` / 解析阶段莫名报错 | locale 不是 UTF-8 |
| 构建跑到一半 `Too many open files` | 没设 `ulimit -n` |
| `Invalid cross-device link`、构建慢 5~10 倍 | 工作区在 NTFS / 9p / 网络盘 |

---

## 4. 获取代码与上游层（二选一）

### 方式 A：kas（推荐，可复现）

```bash
git clone https://github.com/<your-org>/yocto-meta-lubancat.git
cd yocto-meta-lubancat

# kas 建议装在 venv 里，避免污染系统 python（需要 python3-venv，host-deps.sh 已装）
python3 -m venv .kas && . .kas/bin/activate && pip install kas
# 若报 "No matching distribution found for kas"，说明 pip 源没同步，换官方源：
#   pip install -i https://pypi.org/simple kas

# 国内网络建议先 source 这个（只影响当前 shell 的 git，不动 ~/.gitconfig）
source ./scripts/setup-mirror.sh

kas build kas/lubancat.yml
```

- `kas/lubancat.lock.yml` 会被**自动加载**，把 poky / meta-arm / meta-openembedded / meta-rockchip
  钉到具体 commit；想升级上游才跑 `kas lock --update kas/lubancat.yml`。
- **务必在仓库根执行**：kas 的 work dir 默认是当前目录，上游层会 clone 到 `./poky`、`./meta-arm`…，
  `build/` 也建在仓库根（都已在 `.gitignore` 里）。

### 方式 B：手动 clone + add-layer（不用 kas，或要改层）

```bash
git clone https://github.com/<your-org>/yocto-meta-lubancat.git
cd yocto-meta-lubancat

./scripts/fetch-layers.sh            # 把 4 个上游层 clone 到仓库根，并打印各自 commit
mkdir -p build/conf
cp build-conf/local.conf.sample build/conf/local.conf   # 按本机改 BB_NUMBER_THREADS / PARALLEL_MAKE

source poky/oe-init-build-env build
bitbake-layers add-layer ../meta-arm/meta-arm ../meta-arm/meta-arm-toolchain \
  ../meta-openembedded/meta-oe ../meta-openembedded/meta-python \
  ../meta-openembedded/meta-networking ../meta-openembedded/meta-filesystems \
  ../meta-rockchip ../meta-lubancat
bitbake-layers show-layers            # 应有 11 个层（poky 3 + arm 2 + oe 4 + rockchip + lubancat）

bitbake lubancat-image-minimal extboot-image
```

### 目录布局

```
yocto-meta-lubancat/          ← 仓库根 = kas work dir
├── kas/  build-conf/  scripts/  tools/rkpack/  docs/  meta-lubancat/
├── poky/  meta-arm/  meta-openembedded/  meta-rockchip/   ← kas/fetch-layers 拉的，已忽略
└── build/                                                  ← 构建目录，已忽略
    ├── conf/local.conf
    └── tmp/deploy/images/<machine>/
```

### 复用已有的层克隆（不想重新下载）

kas 支持一个「只读参考目录」，把已有 clone 当镜像用（不会改动它们）：

```bash
KAS_REPO_REF_DIR=$HOME/old-workspace kas build kas/lubancat.yml
```

也可以直接把旧目录 `mv` 进仓库根（它们本来就被忽略），或做软链：

```bash
ln -s /data/yocto-cache/poky poky
```

**这步失败的典型现象**

| 现象 | 原因 / 处置 |
|---|---|
| `does not contain a layer.conf` | `add-layer` 指到了仓库根；层在 `meta-lubancat/` 子目录 |
| `Nothing PROVIDES 'linux-rockchip'` | 少加了 `meta-rockchip`，或分支不是 scarthgap |
| `LAYERSERIES_COMPAT_lubancat ...` 报错 | 层与 poky 不是同一系列（都应是 scarthgap） |
| `kas: command not found` | 没装 kas，或用了 `pip install --user` 但 `~/.local/bin` 不在 PATH |
| `path ... does not exist` | 不在仓库根执行 kas |

---

## 5. 选 MACHINE、选镜像

```bash
# 默认（kas/lubancat.yml 里写的是 lubancat-4-v1）
kas build kas/lubancat.yml

# 换族：不要改文件，用环境变量覆盖
KAS_MACHINE=lubancat-rk3568 kas build kas/lubancat.yml

# 编别的档位：KAS_TARGET 覆盖 target 列表（空格分隔），记得把 extboot-image 带上
KAS_TARGET="lubancat-image-full extboot-image" kas build kas/lubancat.yml
```

手动方式：改 `build/conf/local.conf` 的 `MACHINE = "..."`。

> 同一个 build 目录反复切 MACHINE 会让 kernel 这类 MACHINE 相关 recipe 重新签名（实测切一轮
> 回来内核会整编一次）。常态多板请用独立 build 目录 + 共享 `DL_DIR`/`SSTATE_DIR`。

### 三档镜像

| 档 | recipe | 出口判据 | 额外内容 |
|---|---|---|---|
| L0 | `lubancat-image-minimal` | 串口出现 `login:`，root 可登录，`uname -a` 见 6.1.x | `packagegroup-lubancat-base` + dropbear + `debug-tweaks` |
| L1 | `lubancat-image-net` | `ethtool eth0` 见 `1000Mb/s Full`，`ping` 网关通 | L0 + `packagegroup-lubancat-net`（ethtool/iproute2/tcpdump/tftp 等） |
| L2 | `lubancat-image-full` | `systemctl status weston` 起来、`kmscube` 出画面 | L1 + weston + `rockchip-libmali` + `rockchip-librga` + `rockchip-npu` + kmscube |

L2 需要 `DISTRO_FEATURES:append = " pam"`（systemd + weston 强制要求），`kas/lubancat.yml` 与
`local.conf.sample` 都已带上；代价是首次带上它时所有 recipe 重新签名一次。

`debug-tweaks`（root 空密码）只为 bring-up，**对外发布前必须去掉**。

---

## 6. 编译

```bash
# kas 方式（推荐）
kas build kas/lubancat.yml

# 手动方式
source poky/oe-init-build-env build
bitbake lubancat-image-minimal extboot-image
```

首次耗时（含下载）：8 核约 6~10 小时；16 线程约 3~5 小时；64 核 16 线程实测约 1.5~2 小时。
增量构建通常几分钟。

产物都在 `build/tmp/deploy/images/<machine>/`：

| 文件 | 说明 |
|---|---|
| `Image` / `Image-6.1.99` | 裸内核 |
| `dtb/*.dtb` | 族内全量设备树（12 份 for rk3588） |
| `dtb/overlay/*.dtbo` | 族内全量 overlay（278 份 for rk3588） |
| `boot-ext2.img` | **128 MiB ext2**，boot 分区内容（boot.scr / Image / rk-kernel.dtb / dtb/ / uEnv/） |
| `lubancat-image-*.rootfs.ext4` | rootfs |
| `*.wic.gz` | 整盘镜像（GPT） |
| `loader.bin` / `uboot.img` / `boot.img` | U-Boot 与 FIT 相关的中间产物 |

清理：

```bash
bitbake -c cleansstate <recipe>     # 清某个 recipe 的 sstate，保留 downloads
bitbake -c cleanall <recipe>        # 连 downloads 一起清
rm -rf build/tmp                    # 最彻底；sstate-cache 留着，重建仍然快
```

`rm_work` 已默认开启（`kas/lubancat.yml` 与 `local.conf.sample` 都有），否则 tmp 会涨到 200 GB+。

---

## 7. 打包与烧写

### 7.1 产物之间的关系（最容易混的一节）

```
A. wic 整盘（GPT，meta-lubancat/wic/lubancat-gptdisk.wks.in）
   sector 64 : idblock.img      （32 KiB 对齐，BootROM 硬约束）
   2 MiB     : uboot.img
   align 4   : boot.img         （FIT：内核 + 单个 dtb）
   align 8192: rootfs (ext4, PARTUUID=614e0000-0000-4000-8000-000000000000)
   烧写：rkdeveloptool wl 0

B. rkfw update.img（Rockchip parameter 分区表）
   0x4000  : uboot.img   (8 MiB)
   0x8000  : boot.img    (128 MiB, bootable)  ← EXTBOOT=1 时内容就是 boot-ext2.img
   0x48000 : rootfs      (grow 到盘尾)
   烧写：upgrade_tool uf / RKDevTool
```

| 产物 | 来源 | 用途 | 关键约束 |
|---|---|---|---|
| `boot-ext2.img` | `recipes-bsp/extboot/extboot-image.bb` | extboot 的 boot 分区 | **必须恰好 128 MiB**（`0x40000` 扇区）；改 `EXTBOOT_SIZE_MB` 必须同步改 `make-updateimg.sh` 的 CMDLINE |
| `*.wic.gz` | wic | 整盘刷 eMMC/TF，不依赖任何厂商工具 | 用 FIT `boot.img`，与 extboot 是**两套布局** |
| `update.img` | `scripts/make-updateimg.sh` | RKDevTool / `upgrade_tool uf` 一键刷 | extboot 布局；boot 项的文件实际是 ext2 镜像 |

**不要混用**：wic 的 uboot 在 2 MiB，parameter 的 uboot 在 8 MiB。

### 7.2 打 update.img（不需要 SDK）

```bash
./scripts/make-updateimg.sh
# ==> 芯片型号: RK3588（由 loader.bin 偏移 21 自动推断）
# ==> build/updateimg/update.img
```

| 变量 | 默认 | 说明 |
|---|---|---|
| `MACHINE` | `lubancat-4-v1` | 决定从哪个 deploy 目录取文件 |
| `IMAGE` | 最新 mtime 的 `*.rootfs.ext4` | 多份 rootfs 并存时用它指定，如 `IMAGE=lubancat-image-full` |
| `ROOTFS` | — | 直接给绝对路径，优先级最高 |
| `EXTBOOT` | `1` | `0` = 回退旧 FIT 单包布局（逃生路径，rootfs 固定 448 MiB） |
| `PACK` | `tools/rkpack` | 指向自备 SDK 的 `.../Linux_Pack_Firmware/rockdev` |
| `DEPLOY` / `WORK` | `build/tmp/deploy/images/$MACHINE` / `build/updateimg` | 自定义路径 |

`tools/rkpack/` 里是 `afptool`（v2.29）与 `rkImageMaker`，x86-64 静态二进制：

```bash
cd tools/rkpack && sha256sum -c SHA256SUMS
```

### 7.3 烧写三条路

| 路线 | 需要 | 命令 |
|---|---|---|
| `upgrade_tool`（Linux） | `update.img` | `sudo upgrade_tool uf build/updateimg/update.img` |
| RKDevTool（Windows） | `update.img` | 「升级固件」→ 选固件 → 执行 |
| `rkdeveloptool`（Linux） | `.wic.gz` | `sudo ./scripts/flash-emmc.sh build/tmp/deploy/images/lubancat-4-v1/lubancat-image-minimal-lubancat-4-v1.wic.gz` |

进 loader 模式：按住 REC 再上电，或系统里 `reboot loader`。maskrom 冷启动需要先下 loader：
`sudo ./scripts/flash-emmc.sh xxx.wic.gz --loader <path>/rk3588_spl_loader_*.bin`。

### 7.4 首次启动验收（按顺序，不通过就别往下走）

串口：`picocom -b 1500000 /dev/ttyUSB0`（8N1）

| # | 应看到 | 说明 |
|---|---|---|
| 1 | `DDR Version ...` | DDR 训练；这里没输出说明 loader/DDR bin 不对 |
| 2 | `U-Boot 2017.09-...` | |
| 3 | `DTB(Distro): rk-kernel.dtb` | 早期 DTB 来自 boot 分区，说明 ext2 布局生效 |
| 4 | `Found U-Boot script /boot.scr` | distro_bootcmd 命中 |
| 5 | `Starting kernel ...` + 内核日志 | |
| 6 | `login:`，root 可登录 | L0 判据 |
| 7 | `cat /proc/cmdline` 含 `console=ttyFIQ0,1500000n8 root=/dev/mmcblk0p3 boot_part=2` | uEnv 生效 |

起来之后：

```bash
journalctl -u lubancat-board-detect | tail     # 认板与切 dtb 的日志（族镜像第一次启动会自己重启一次）
cat /sys/firmware/devicetree/base/model
systemctl status lubancat-resize-rootfs        # 首次启动自动扩容
df -h /
```

**族镜像第一次启动重启一次是预期行为**，不是崩溃；板级别名 `lubancat-4-v1` 不会重启
（脚本 `cmp` 发现 dtb 内容一致，只打标记）。

---

## 8. 日常操作（不重新编译）

```bash
mount /dev/disk/by-partlabel/boot /mnt     # extboot 布局里 boot 是 p2

# 1) 换设备树（换板）
cp /mnt/dtb/rk3588s-lubancat-4.dtb /mnt/rk-kernel.dtb.new
mv /mnt/rk-kernel.dtb.new /mnt/rk-kernel.dtb     # 先写临时文件再 mv，防掉电留半截
sync && umount /mnt && reboot

# 2) 开设备树插件
vi /mnt/uEnv/uEnv.txt
#   enable_uboot_overlays=1        ← 必须为 1，否则整段不解析
#   #overlay_start
#   dtoverlay=/dtb/overlay/rk3588s-lubancat-4-hdmi0-vp0-overlay.dtbo
#   #overlay_end
# 带参数：dtoverlay=xxx.dtbo,param=value

# 3) 改内核参数（cmdline= 会覆盖 dts 里的 bootargs）
#    console 必须带波特率，写错表现为串口全黑但系统已启动
```

`uEnv.txt` 里的 `size=0x1000000` 是 `dtfile` 读文本的 malloc 上限，别删。

---

## 9. 常见问题

| # | 症状 | 根因 | 处置 |
|---|---|---|---|
| 1 | 串口全黑，但能 ping / ssh | `uEnv.txt` 的 `cmdline=` 覆盖了 dts，且 `console=ttyFIQ0` 没带波特率 | 改成 `console=ttyFIQ0,1500000n8`，重跑 `bitbake extboot-image` |
| 2 | 卡 `Waiting for root device PARTUUID=...` | rootfs 的 PARTUUID 与内核 dtsi 默认值不一致（抄了厂商 parameter 模板） | 用 `make-updateimg.sh` 自带的 uuid `614e0000-0000-4000-8000-000000000000` |
| 3 | `No rule to make target 'rockchip/xxx.dtb'` | `KERNEL_DEVICETREE` 少了 `rockchip/` 前缀 | 写全 `rockchip/xxx.dtb` |
| 4 | `Nothing RPROVIDES 'systemd-networkd'` | scarthgap 的 systemd 255 不拆这个包（networkd 在主包里） | `RDEPENDS` 写 `systemd` |
| 5 | `Nothing RPROVIDES 'weston-xwayland'` + `missing required distro feature 'pam'` | systemd + weston 强制要求 `pam` | `DISTRO_FEATURES:append = " pam"`（会触发一次全量重签名） |
| 6 | `WARNING: The free inode ... is running low` + `No new tasks ... STOPTASKS` | `BB_DISKMON_DIRS` 第二列是**千个 inode**，写成 `1G` 等于要求 10 亿个 | 用 `...,2G,100K`；`HALT,...,500M,10K` |
| 7 | `No recipes ... for: u-boot-rockchip_%.bbappend` | 该 recipe 文件名**无版本号**，`_%` 通配不匹配 | bbappend 命名成 `u-boot-rockchip.bbappend` |
| 8 | `Error, you have '..' in your TMPDIR directory path` | sanity checker 禁止 | `TMPDIR = "${TOPDIR}/tmp"` |
| 9 | `unparsed line: 'INHERIT += "rm_work"  # ...'` | bitbake 的 conf **不支持行尾注释** | 注释单独成行 |
| 10 | 内核配置片段写了不生效（如关不掉某个驱动） | `.cfg` 走 `merge_config.sh`，`# CONFIG_X is not set` 会被当注释删掉 | 写 `CONFIG_X=n` |
| 11 | `Error: file not found: drivers/gpu/arm/bifrost/mali_csffw.bin` | 驱动用 `.incbin` 相对汇编器 cwd，Yocto 是 out-of-tree 构建 | 编译前把 bin 复制到 `${B}` 同名路径（bbappend 已做） |
| 12 | `rtl8821cu/core/rtw_cmd.c: fatal error: drv_types.h` | vendor 驱动 Makefile 写 `-I$(src)/include`，进子目录后 `$(src)` 变了 | 不用这些驱动就 `CONFIG_RTL8821CU=n` 等（本层默认已关） |
| 13 | `make: *** No rule to make target 'dtbs'` | bitbake 任务 cwd 是 `${WORKDIR}`，而 `do_compile` 自己会 `cd ${B}` | `oe_runmake -C ${S} O=${B} dtbs` |
| 14 | 构建成功但 deploy 里没有 `boot-ext2.img` | 只 `inherit deploy` 时 `do_build` 没串 `do_deploy` | 显式 `addtask deploy after do_compile before do_build` |
| 15 | 重编了 minimal，烧进去却没有新包 | 打包脚本按字母序取了 `lubancat-image-full` | 已改成按 mtime 取最新，并支持 `IMAGE=` / `ROOTFS=` |
| 16 | 首启没切板，还是 generic dtb | `LUBANCAT_FIRSTBOOT_SWITCH=0` / 内核没使能 saradc / `board_id` 不在 `board-table` | `journalctl -u lubancat-board-detect`；对着日志里的 `adc ch2/ch3` 改表 |
| 17 | 首启后容量还是镜像大小 | 分区没 grow（用了 `EXTBOOT=0` 或 wic 路径） | `growpart /dev/mmcblk0 3 && resize2fs /dev/mmcblk0p3`，或改用 extboot 布局 |
| 18 | `shallow mismatch` / `PSI not supported` / 下载只有 30 KB/s | 之前全量拉过同仓 / 容器无 `/proc/pressure` / 没开浅克隆与代理 | 删对应 `build/downloads/git2/<repo>`；注释 `BB_PRESSURE_MAX_*`；`source scripts/setup-mirror.sh` |
| 19 | `afptool: cannot execute binary file` / `Permission denied` | `tools/rkpack` 是 x86-64 ELF（ARM 主机/macOS 不能跑）；或 exec 位丢了 | 换 x86-64 Linux，或用 `PACK=` 指自备 SDK；`chmod +x tools/rkpack/*` |
| 20 | `pip install kas` 报 `No matching distribution found for kas` | 国内 pip 镜像没同步 kas（实测清华源如此） | `pip install -i https://pypi.org/simple kas`；或 `pip download` 后离线安装 |

更细的排查步骤（症状 → 根因 → 验证命令 → 修复 → 回归判据）见
[`docs/manual.md` 第 12 章](docs/manual.md)。

---

## 10. 版本、升级与许可

- 当前版本：`v0.1.0`，见 [`CHANGELOG.md`](CHANGELOG.md)
- 版本矩阵（层 commit / BSP SRCREV / 各 MACHINE 验证级别）：[`docs/VERSION-MATRIX.md`](docs/VERSION-MATRIX.md)
- 仓库管理方式（为什么是 kas + lock、分支与 tag 规则）：[`docs/repo-strategy.md`](docs/repo-strategy.md)
- 完整实施手册（1819 行，14 章 + 3 附录）：[`docs/manual.md`](docs/manual.md)

**升级到新 Yocto 系列的六步**

1. 改 `kas/lubancat.yml` 的 4 处 `branch:`
2. 改 `meta-lubancat/conf/layer.conf` 的 `LAYERSERIES_COMPAT_lubancat`
3. 检查 bbappend 的 recipe 版本名（`linux-rockchip_6.1.bbappend` 在新系列可能不存在）
4. `kas lock --update kas/lubancat.yml`，review lock diff
5. 完整构建 + 上板验收，更新 `docs/VERSION-MATRIX.md`
6. 打 tag，`CHANGELOG.md` 记一条

**许可**：本仓库（层 / 脚本 / 文档）为 MIT，见 [`LICENSE`](LICENSE)。
上游层、内核、U-Boot、rkbin 与 `tools/rkpack/` 下的厂商工具各有自己的许可，见
[`THIRD-PARTY.md`](THIRD-PARTY.md)。

**致谢**：`meta-rockchip`（Rockchip / Jeffy Chen）、野火 LubanCat 的 kernel / u-boot / rkbin 与 SDK、
Yocto Project 与 OpenEmbedded。
