# yocto-meta-lubancat

LubanCat（野火）Rockchip 系列开发板的 Yocto 构建环境，包含一个 BSP 层、一份 kas 描述和几个辅助脚本。
镜像支持在板上直接更换设备树与设备树插件，不必重新打包。

Yocto layer, kas project and helper scripts for LubanCat boards
(RK3588/3588S, RK3576, RK3568/3566, RK3562, RK3528).

```bash
git clone https://github.com/<your-org>/yocto-meta-lubancat.git && cd yocto-meta-lubancat
sudo ./scripts/host-deps.sh
kas build kas/lubancat.yml                # 拉 4 个上游层 + 编译 minimal 镜像 + boot 分区
./scripts/make-updateimg.sh               # 打成 rkfw update.img（工具已随仓库提供）
```

| 项 | 值 |
|---|---|
| Yocto 系列 | scarthgap (5.0)，poky + systemd |
| SoC | RK3588 / RK3588S / RK3576 / RK3568 / RK3566 / RK3562 / RK3528 |
| 板卡 | 6 个族级 MACHINE 覆盖 39 份板级 dtb，一族一份镜像 |
| 内核 / U-Boot | Linux 6.1（LubanCat `lbc-develop-6.1`）/ U-Boot 2017.09（LubanCat `main`） |
| 调试串口 | UART2，1500000 8N1，内核节点 `ttyFIQ0` |
| 许可 | 层与脚本为 MIT；`tools/rkpack/` 下的厂商工具不是 MIT，见 `THIRD-PARTY.md` |

SG200x（全志核）不在范围内。它走 fsbl + opensbi + fip.bin，需要另一套内核树和打包链。
仓库也不提供 Debian/Ubuntu 根文件系统、主线内核和 OTA。

## 1. 仓库构成

`meta-lubancat/` 是层本体：机器配置、kernel 与 U-Boot 的 bbappend、镜像 recipe、首启服务都在这里。
`kas/lubancat.yml` 描述上游四个层和 local.conf 的内容，同目录的 `lubancat.lock.yml` 把它们的
commit 钉死。`scripts/` 放主机依赖、拉层、打包和烧写脚本，`tools/rkpack/` 是两个 Rockchip 打包工具。

**三条必读警告**

1. **串口是 1500000 8N1，内核里叫 `ttyFIQ0`**。  
   而且 `uEnv.txt` 的 `cmdline=` 会**覆盖** dts 里的 bootargs——写成 `console=ttyFIQ0`（漏波特率）  
   的表现是"串口全黑，但系统其实起来了、能 ping 通"。
2. **磁盘 ≥ 300 GB，且必须是本地 ext4/xfs**。放在 NTFS / 9p / 网络盘上会慢 5~10 倍或直接报错。
3. `update.img` 需要的 `afptool` / `rkImageMaker` **已随仓库提供**（`tools/rkpack/`）

## 2. 支持范围

族镜像的做法是把全族的 dtb、dtbo 和 uEnv 都放进 boot 分区。首次启动时 `lubancat-board-detect`
读 SARADC 的板卡 ID，把 `rk-kernel.dtb` 与 `uEnv/uEnv.txt` 换成这块板对应的文件，重启一次生效。

| MACHINE | SoC | 板型 | 默认 dtb | 验证情况 |
|---|---|---|---|---|
| `lubancat-4-v1` | RK3588S | LubanCat-4 V1（板级别名，不切板） | `rk3588s-lubancat-4-v1.dtb` | 上板验证：串口、有线网、HDMI、GPU、NPU |
| `lubancat-rk3588` | RK3588 / 3588S | LubanCat-4 / 4IO / 5 / 5-V2 / 5IO / 5IOB / 5IOF / 5IOI / 5IO-AIBOX1 | `rk3588-lubancat-generic.dtb` | 编译级，12 dtb / 278 dtbo |
| `lubancat-rk3576` | RK3576 | LubanCat-3 / 3-V2 / 3IO / 3IO-test | `rk3576-lubancat-generic.dtb` | 编译级，6 / 78 |
| `lubancat-rk3568` | RK3568 | LubanCat-2 / 2-V1/V2/V3 / 2H / 2IO / 2N / 2N-V2/V3 | `rk356x-lubancat-generic.dtb` | 编译级，10 / 33 |
| `lubancat-rk3566` | RK3566 | LubanCat-1 / 1H / 1IO / 1N / 0 / CM4 | `rk356x-lubancat-generic.dtb` | 编译级，6 / 33 |
| `lubancat-rk3562` | RK3562 | LubanCat-1HS / 1HS-test | `rk3562-lubancat-generic.dtb` | 编译级，3 / 42 |
| `lubancat-rk3528` | RK3528 | LubanCat-Q1 / Q1IO | `rk3528-lubancat-generic.dtb` | 编译级，3 / 15 |

"编译级"指 `bitbake -p` 通过、变量核对正确、dtb 与 dtbo 数量符合预期，没有上过板。
层 commit 与 BSP SRCREV 见 [`docs/VERSION-MATRIX.md`](docs/VERSION-MATRIX.md)。

边界：

- rootfs 只有 poky + systemd，不含 Ubuntu/Debian。
- 不做主线内核、OTA、双系统、安全启动。
- `lubancat-5-rk3588-pcie_defconfig` 关闭了 `EARLY_DISTRO_DTB`，不能用于 extboot，族机器固定用 `rk3588_defconfig`。

## 3. 宿主机

### 3.1 要求

| 项 | 要求 | 说明 |
|---|---|---|
| 发行版 | Ubuntu 22.04 / 24.04、Debian 12 | scarthgap 支持范围 |
| CPU | ≥ 8 核（推荐 16+） | 全量约 5000~9000 个任务 |
| 内存 | ≥ 16 GiB（推荐 32 GiB+） | 单个 gcc 或链接进程峰值 2~4 GiB |
| 磁盘 | ≥ 300 GB 空闲，本地 ext4/xfs | downloads 35~60G + sstate 45~80G + tmp 60~120G |
| 文件系统 | 支持硬链接，不能用 NTFS / exFAT / 9p / 网络盘 | 否则报 `Invalid cross-device link` 或慢 10 倍 |
| locale | `en_US.UTF-8` | 非 UTF-8 会在解析期抛 `UnicodeDecodeError` |
| 文件句柄 | `ulimit -n 65536` | 默认 1024，并发一上来就 `Too many open files` |
| 权限 | 构建用普通用户，装依赖时才 sudo | root 构建会把 sstate 的属主搞乱 |

### 3.2 一键安装

```bash
sudo ./scripts/host-deps.sh
```

脚本会装 Yocto 必需包、wic 与分区工具、`u-boot-tools`（提供 `mkimage`），然后以你的账号
`pip install --user kas`，最后检查 locale 并打印磁盘与内存。

### 3.3 手工安装依赖

不想跑脚本时，等价命令如下。

<details>
<summary>展开 apt 命令</summary>

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential chrpath cpio debianutils diffstat file gawk gcc git \
  iputils-ping libacl1 liblz4-tool locales python3 python3-git python3-jinja2 \
  python3-pexpect python3-pip python3-subunit python3-venv socat texinfo unzip wget xz-utils zstd \
  parted gdisk dosfstools mtools e2fsprogs device-tree-compiler u-boot-tools bmap-tools
sudo locale-gen en_US.UTF-8
```

</details>

不要装 `python3-wic`，Ubuntu 的 apt 源里没有这个包（wic 由 poky 自带），加上它会让整条
`apt-get install` 失败。

### 3.4 环境与自检

每个新 shell 都要设一次，建议写进 `~/.bashrc`；设完顺手确认环境：

```bash
export LANG=en_US.UTF-8
ulimit -n 65536
locale; ulimit -n; df -h .; nproc; free -g
```

这几项没配好时，报错都出现在不相干的地方：locale 不是 UTF-8 会在解析期抛 `UnicodeDecodeError`，
`ulimit -n` 太小会中途报 `Too many open files`，工作区放在 NTFS、9p 或网络盘上则先是
`Invalid cross-device link`，然后构建慢十倍。

## 4. 获取代码与上游层

### 方式 A：kas

```bash
git clone https://github.com/<your-org>/yocto-meta-lubancat.git
cd yocto-meta-lubancat

# kas 装在 venv 里，避免污染系统 python（python3-venv 由 host-deps.sh 安装）
python3 -m venv .kas && . .kas/bin/activate && pip install kas
# 报 "No matching distribution found for kas" 时换官方源：
#   pip install -i https://pypi.org/simple kas

# 国内网络建议先 source 这个，只影响当前 shell 的 git
source ./scripts/setup-mirror.sh

kas build kas/lubancat.yml
```

`lubancat.lock.yml` 会被自动加载，把 poky、meta-arm、meta-openembedded、meta-rockchip 钉到具体
commit；只有升级上游时才需要 `kas lock --update kas/lubancat.yml`。

命令要在仓库根执行。kas 的 work dir 默认取当前目录，四个上游层会 clone 到 `./poky`、`./meta-arm`
等位置，`build/` 也建在仓库根，这些目录都已写进 `.gitignore`。

### 方式 B：手动 clone 加层

```bash
git clone https://github.com/<your-org>/yocto-meta-lubancat.git
cd yocto-meta-lubancat

./scripts/fetch-layers.sh            # 拉 4 个上游层到仓库根，并打印各自 commit
mkdir -p build/conf
cp build-conf/local.conf.sample build/conf/local.conf   # 按本机改 BB_NUMBER_THREADS / PARALLEL_MAKE

source poky/oe-init-build-env build
bitbake-layers add-layer ../meta-arm/meta-arm ../meta-arm/meta-arm-toolchain \
  ../meta-openembedded/meta-oe ../meta-openembedded/meta-python \
  ../meta-openembedded/meta-networking ../meta-openembedded/meta-filesystems \
  ../meta-rockchip ../meta-lubancat
bitbake-layers show-layers            # 11 个层

bitbake lubancat-image-minimal extboot-image
```

### 目录布局

```
yocto-meta-lubancat/          ← 仓库根，也是 kas 的 work dir
├── kas/  build-conf/  scripts/  tools/rkpack/  docs/  meta-lubancat/
├── poky/  meta-arm/  meta-openembedded/  meta-rockchip/   ← 拉下来的层，已忽略
└── build/                                                  ← 构建目录，已忽略
    ├── conf/local.conf
    └── tmp/deploy/images/<machine>/
```

### 复用已有的层克隆

已有 clone 时可以把它当只读参考目录，避免重复下载：

```bash
KAS_REPO_REF_DIR=$HOME/old-workspace kas build kas/lubancat.yml
```

也可以直接把旧目录移进仓库根（本来就被忽略），或者做软链：

```bash
ln -s /data/yocto-cache/poky poky
```

### 这一步常见的问题

| 现象 | 原因与处置 |
|---|---|
| `does not contain a layer.conf` | `add-layer` 指到了仓库根，层在 `meta-lubancat/` 子目录 |
| `Nothing PROVIDES 'linux-rockchip'` | 少加了 `meta-rockchip`，或分支不是 scarthgap |
| `LAYERSERIES_COMPAT_lubancat` 报错 | 层与 poky 不是同一系列 |
| `kas: command not found` | 没装 kas，或 `~/.local/bin` 不在 PATH |
| `path ... does not exist` | 不在仓库根执行 kas |

## 5. 选择 MACHINE 与镜像

```bash
# 默认，kas/lubancat.yml 里写的是 lubancat-4-v1
kas build kas/lubancat.yml

# 换族，不改文件
KAS_MACHINE=lubancat-rk3568 kas build kas/lubancat.yml

# 换镜像档位，注意把 extboot-image 带上
KAS_TARGET="lubancat-image-full extboot-image" kas build kas/lubancat.yml
```

手动方式改 `build/conf/local.conf` 里的 `MACHINE`。

在同一个 build 目录反复切 MACHINE，会让 kernel 这类与 MACHINE 相关的 recipe 重新签名，实测切一轮
回来内核会整编一次。常态多板建议各用独立 build 目录，共享 `DL_DIR` 与 `SSTATE_DIR`。

| 档 | recipe | 验收判据 | 额外内容 |
|---|---|---|---|
| L0 | `lubancat-image-minimal` | 串口出现 `login:`，root 可登录 | base 包组、dropbear、`debug-tweaks` |
| L1 | `lubancat-image-net` | `ethtool eth0` 显示 `1000Mb/s Full`，能 ping 通网关 | L0 加 net 包组（ethtool、iproute2、tcpdump、tftp） |
| L2 | `lubancat-image-full` | `systemctl status weston` 正常，`kmscube` 有画面 | L1 加 weston、libmali、librga、NPU 与 kmscube |

L2 需要 `DISTRO_FEATURES:append = " pam"`，systemd 与 weston 的组合强制要求它。`kas/lubancat.yml`
和 `local.conf.sample` 都已带上，代价是首次启用时所有 recipe 重新签名一次。

`debug-tweaks` 会给 root 空密码，只用于 bring-up，对外发布前记得去掉。

## 6. 编译

```bash
# kas
kas build kas/lubancat.yml

# 手动
source poky/oe-init-build-env build
bitbake lubancat-image-minimal extboot-image
```

首次构建含下载，8 核大约 6~10 小时，16 线程 3~5 小时，64 核开 16 线程实测 1.5~2 小时；增量构建
通常几分钟。

产物在 `build/tmp/deploy/images/<machine>/`：

| 文件 | 内容 |
|---|---|
| `Image` / `Image-6.1.99` | 裸内核 |
| `dtb/*.dtb` | 族内全量设备树，rk3588 有 12 份 |
| `dtb/overlay/*.dtbo` | 族内全量插件，rk3588 有 278 份 |
| `boot-ext2.img` | 128 MiB ext2，boot 分区内容 |
| `lubancat-image-*.rootfs.ext4` | 根文件系统 |
| `*.wic.gz` | 整盘镜像 |
| `loader.bin` / `uboot.img` / `boot.img` | U-Boot 与 FIT 的中间产物 |

清理：

```bash
bitbake -c cleansstate <recipe>     # 清 sstate，保留 downloads
bitbake -c cleanall <recipe>        # 连 downloads 一起清
rm -rf build/tmp                    # 最彻底；sstate-cache 留着，重建仍然快
```

`rm_work` 默认开启，否则 tmp 会涨到 200 GB 以上。

## 7. 打包与烧写

仓库会产出三类文件：boot 分区镜像、整盘 wic、rkfw 的 `update.img`。它们对应两套不同的布局，
区别、约束和校验方法见 [`docs/boot-artifacts.md`](docs/boot-artifacts.md)，这里只讲怎么用。

### 7.1 打 update.img

```bash
./scripts/make-updateimg.sh
# ==> 芯片型号: RK3588（由 loader.bin 偏移 21 自动推断）
# ==> build/updateimg/update.img
```

| 变量 | 默认值 | 说明 |
|---|---|---|
| `MACHINE` | `lubancat-4-v1` | 决定从哪个 deploy 目录取文件 |
| `IMAGE` | 最新修改的 `*.rootfs.ext4` | 多份 rootfs 并存时指定，如 `IMAGE=lubancat-image-full` |
| `ROOTFS` | 无 | 直接给绝对路径，优先级最高 |
| `EXTBOOT` | `1` | 设为 `0` 回退旧 FIT 布局，作逃生路径 |
| `PACK` | `tools/rkpack` | 指向自备 SDK 的 `.../Linux_Pack_Firmware/rockdev` |
| `DEPLOY` / `WORK` | `build/tmp/deploy/images/$MACHINE` / `build/updateimg` | 自定义路径 |

`tools/rkpack/` 里是 `afptool` 2.29 与 `rkImageMaker`，x86-64 静态二进制，可以校验一下：

```bash
cd tools/rkpack && sha256sum -c SHA256SUMS
```

### 7.2 烧写

| 路线 | 需要的文件 | 命令 |
|---|---|---|
| `upgrade_tool`（Linux） | `update.img` | `sudo upgrade_tool uf build/updateimg/update.img` |
| RKDevTool（Windows） | `update.img` | 「升级固件」选文件后执行 |
| `rkdeveloptool`（Linux） | `.wic.gz` | `sudo ./scripts/flash-emmc.sh build/tmp/deploy/images/lubancat-4-v1/lubancat-image-minimal-lubancat-4-v1.wic.gz` |

进 loader 模式可以按住 REC 再上电，或在系统里执行 `reboot loader`。maskrom 冷启动需要先下 loader：
`sudo ./scripts/flash-emmc.sh xxx.wic.gz --loader <path>/rk3588_spl_loader_*.bin`。

### 7.3 首次启动

串口用 `picocom -b 1500000 /dev/ttyUSB0`，8N1。

| 顺序 | 应看到 | 说明 |
|---|---|---|
| 1 | `DDR Version ...` | 没有输出说明 loader 或 DDR bin 不对 |
| 2 | `U-Boot 2017.09-...` | |
| 3 | `DTB(Distro): rk-kernel.dtb` | 早期 dtb 取自 boot 分区，说明 ext2 布局生效 |
| 4 | `Found U-Boot script /boot.scr` | distro_bootcmd 命中 |
| 5 | `Starting kernel ...` 加内核日志 | |
| 6 | `login:`，root 可登录 | L0 判据 |
| 7 | `/proc/cmdline` 含 `console=ttyFIQ0,1500000n8 root=/dev/mmcblk0p3 boot_part=2` | uEnv 生效 |

起来之后再确认三件事：

```bash
journalctl -u lubancat-board-detect | tail     # 认板与切 dtb 的日志
cat /sys/firmware/devicetree/base/model
systemctl status lubancat-resize-rootfs        # 首次启动扩容
df -h /
```

族镜像第一次启动会自动重启一次，这是在切换 dtb，属于正常行为。板级别名 `lubancat-4-v1` 不会重启，
脚本比对后发现 dtb 内容一致，只打标记。

## 8. 日常操作

```bash
mount /dev/disk/by-partlabel/boot /mnt     # extboot 布局里 boot 是 p2

# 换设备树（换板）
cp /mnt/dtb/rk3588s-lubancat-4.dtb /mnt/rk-kernel.dtb.new
mv /mnt/rk-kernel.dtb.new /mnt/rk-kernel.dtb     # 先写临时文件再 mv，防掉电留半截
sync && umount /mnt && reboot

# 开设备树插件
vi /mnt/uEnv/uEnv.txt
#   enable_uboot_overlays=1        ← 必须为 1，否则整段不解析
#   #overlay_start
#   dtoverlay=/dtb/overlay/rk3588s-lubancat-4-hdmi0-vp0-overlay.dtbo
#   #overlay_end
# 带参数写成 dtoverlay=xxx.dtbo,param=value

# 改内核参数，cmdline= 会覆盖 dts 里的 bootargs
# console 必须带波特率，漏了会串口全黑但系统已经启动
```

`uEnv.txt` 里的 `size=0x1000000` 是 `dtfile` 读文本时的 malloc 上限，不要删。

## 9. 版本、升级与许可

- 当前版本 `v0.1.1`，见 [`CHANGELOG.md`](CHANGELOG.md)
- 层 commit、BSP SRCREV 与各 MACHINE 的验证情况：[`docs/VERSION-MATRIX.md`](docs/VERSION-MATRIX.md)
- 为什么用 kas + lock、分支与 tag 规则：[`docs/repo-strategy.md`](docs/repo-strategy.md)
- 完整实施手册（14 章 + 3 个附录）与常见报错速查表（§12.0）：[`docs/manual.md`](docs/manual.md)

升级到新的 Yocto 系列：

1. 改 `kas/lubancat.yml` 里四处 `branch:`
2. 改 `meta-lubancat/conf/layer.conf` 的 `LAYERSERIES_COMPAT_lubancat`
3. 检查 bbappend 的 recipe 版本名，`linux-rockchip_6.1.bbappend` 在新系列可能不存在
4. `kas lock --update kas/lubancat.yml`，看一遍 lock 的 diff
5. 完整构建并上板验收，更新 `docs/VERSION-MATRIX.md`
6. 打 tag，在 `CHANGELOG.md` 记一条

本仓库的层、脚本和文档为 MIT，见 [`LICENSE`](LICENSE)。上游层、内核、U-Boot、rkbin 以及
`tools/rkpack/` 下的厂商工具各有自己的许可，见 [`THIRD-PARTY.md`](THIRD-PARTY.md)。

致谢：`meta-rockchip`（Rockchip / Jeffy Chen）、野火 LubanCat 的 kernel / u-boot / rkbin 与 SDK、
Yocto Project 与 OpenEmbedded。
