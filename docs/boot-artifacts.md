# 三种镜像产物：boot-ext2.img、wic、update.img

同一份 Yocto 构建会产出三类"看起来都能烧"的文件，它们对应两套互不兼容的磁盘布局。
这一页说明各自装了什么、什么时候用哪个，以及怎么确认手里的文件是哪一套。

## 两套布局

```
A. wic 整盘（GPT）                          B. rkfw update.img（parameter 分区表）
   sector 64 : idblock.img                    0x4000  : uboot.img    (8 MiB)
   2 MiB     : uboot.img                      0x8000  : boot.img     (128 MiB, bootable)
   align 4   : boot.img  (FIT)                0x48000 : rootfs       (grow 到盘尾)
   align 8192: rootfs    (ext4)
   刷法：rkdeveloptool wl 0                    刷法：upgrade_tool uf / RKDevTool
```

两套布局的差别不只是偏移量，而是引导链不同：

- wic 走标准 GPT，BootROM 从 sector 64 读 idblock，U-Boot 从 2 MiB 起，boot 分区是一个 FIT 单包
  （内核 + 一份 dtb），根文件系统用固定 PARTUUID 定位。
- rkfw 走 Rockchip 自己的 parameter 分区表，`afptool` 按表把每个分区写进去，`rkImageMaker`
  再套一层 `RKFW` 头和芯片标记。它的 boot 分区在 8 MiB、大小 128 MiB。

## 三个文件分别是什么

| 文件 | 由谁生成 | 内容 | 用在哪 |
|---|---|---|---|
| `boot-ext2.img` | `meta-lubancat/recipes-bsp/extboot/extboot-image.bb` | 128 MiB ext2，label 为 `boot`：`boot.scr`、`Image`、`rk-kernel.dtb`、全族 `dtb/`、`dtb/overlay/`、`uEnv/` | 只作为 rkfw 布局里的 boot 分区内容，不能单独烧 |
| `*.wic.gz` | wic（`meta-lubancat/wic/lubancat-gptdisk.wks.in`） | 整盘 GPT：idblock + uboot + FIT boot + rootfs | `rkdeveloptool` 一次写整盘，不需要任何厂商工具 |
| `update.img` | `scripts/make-updateimg.sh` | `RKFW` 容器：loader + parameter.txt + uboot + boot + rootfs | `upgrade_tool uf` 或 Windows 的 RKDevTool |

`boot-ext2.img` 是 extboot 机制的核心：boot 分区是文件系统而不是单包，dtb、dtbo、uEnv
都是普通文件，所以才能在板上换设备树、开插件，不用重新打包。`EXTBOOT=1`（默认）时，
`make-updateimg.sh` 把 `boot-ext2.img` 原样当作 rkfw 布局的 boot 分区；`EXTBOOT=0` 时改用
FIT 的 `boot.img`，退回旧布局（rootfs 固定 448 MiB，full 镜像容易超，只作逃生路径）。

## 约束

| 项 | 约束 | 违反后的表现 |
|---|---|---|
| `boot-ext2.img` 大小 | 必须恰好 128 MiB（`0x40000` 扇区） | `afptool` 写分区时越界或留空，启动找不到 `/boot.scr` |
| 改 `EXTBOOT_SIZE_MB` | 必须同步改 `make-updateimg.sh` 里的 CMDLINE | 同上 |
| rootfs PARTUUID | `614e0000-0000-4000-8000-000000000000`，与内核 dtsi 的默认 `root=` 一致 | 卡在 `Waiting for root device PARTUUID=...` |
| wic 与 rkfw | 偏移不可互换（uboot 2 MiB vs 8 MiB） | 刷完 U-Boot 都不打印，或打印后找不到内核 |

rootfs 在 rkfw 布局里是 `-@0x48000(rootfs:grow)`，`afptool` 会把分区拉到磁盘末尾，
文件系统本身由首次启动的 `lubancat-resize-rootfs` 扩。wic 布局里 rootfs 是普通分区，
不自动 grow。

## 怎么确认手里的是哪一套

```bash
# update.img 会带 RKFW 魔数；wic 是 GPT，头部是分区表
head -c 4 build/updateimg/update.img | xxd          # 52 4b 46 57 = "RKFW"
file build/tmp/deploy/images/*/lubancat-image-*.wic.gz

# boot 分区到底装了什么
debugfs -R "ls -l /" build/tmp/deploy/images/<machine>/boot-ext2.img
debugfs -R "cat /uEnv/uEnv.txt" build/tmp/deploy/images/<machine>/boot-ext2.img | head -5

# 从 update.img 反解，核对参数表与 boot 类型
tools/rkpack/rkImageMaker -unpack build/updateimg/update.img /tmp/u
tools/rkpack/afptool -unpack /tmp/u/firmware.img /tmp/u/out
grep CMDLINE /tmp/u/out/parameter.txt
file /tmp/u/out/boot.img                            # 应为 ext2, 134217728 字节
```

上板之后判断当前跑的是哪套，看内核命令行就够：

```bash
cat /proc/cmdline
# rkfw + extboot: root=/dev/mmcblk0p3 boot_part=2 ...（boot.cmd 写入）
# wic:            root=PARTUUID=614e0000-0000-4000-8000-000000000000
```

## 选哪个

日常开发用 `update.img`：一条命令、RKDevTool 图形界面也能刷、失败后重新插线即可。
需要完全脱离厂商工具、或者在 CI 里批量产出时用 wic（`rkdeveloptool` 是开源实现）。
`boot-ext2.img` 一般不单独使用，除非你要手工组一个 parameter 打包目录。
