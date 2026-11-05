# PREEMPT_RT 内核（meta-realtime）

把 `virtual/kernel` 切到 LubanCat 的 PREEMPT_RT 分支，用与主构建完全相同的镜像、U-Boot、
boot 分区布局，只换内核。

- 分支：`lbc-develop-6.1-rt36`，内核 6.1.99，源码树带 `localversion-rt = "-rt36"`
- 实测 `uname -r`：`6.1.99-rt36-lubancat`（见下面「版本串是怎么拼出来的」）
- 一条命令：`KAS_BUILD_DIR=$PWD/build-rt kas build kas/lubancat.yml:kas/realtime.yml`

**版本串是怎么拼出来的**（实测，2026-11-05 在 `lubancat-4-v1` 上编出）：

```
6.1.99        -rt36            -lubancat
Makefile 版本  localversion-rt  CONFIG_LOCALVERSION
```

- `-rt36` 来自 RT 分支源码树里的 `localversion-rt` 文件（`scripts/setlocalversion` 读）；
- `-lubancat` 来自 `LINUX_VERSION_EXTENSION`：poky 的 `kernel-yocto.bbclass` 在
  `do_kernel_configme` 末尾把 `CONFIG_LOCALVERSION` 追加成 `"${LINUX_VERSION_EXTENSION}"`，
  **盖掉了 defconfig 里的 `CONFIG_LOCALVERSION="-rk3588"`**。所以非 RT 构建的
  `/lib/modules/` 目录也是 `6.1.99-lubancat` 而不是 `6.1.99-rk3588`。

由此：`uname -r` 的 RT 版是 `6.1.99-rt36-lubancat`，非 RT 版是 `6.1.99-lubancat`，
两者不同即可判定刷的是哪颗内核；`-lubancat` 后缀不是 RT 特有的。

---

## 1. 范围与前置

### 1.1 支持范围

| 族 | RT defconfig | 状态 |
|---|---|---|
| `lubancat-4-v1` / `lubancat-rk3588` | `lubancat_linux_rk3588_defconfig`（含 `CONFIG_PREEMPT_RT=y`） | 主要目标 |
| `lubancat-rk3576` | `lubancat_linux_rk3576_defconfig`（含） | 可编，未上板 |
| `lubancat-rk3568` / `lubancat-rk3566` | `lubancat_linux_rk356x_defconfig`（含） | 可编，未上板 |
| `lubancat-rk3562` | `lubancat_linux_rk3562_defconfig`（含） | 可编，未上板 |
| `lubancat-rk3528` | `lubancat_linux_rk3528_defconfig`（**没有** `PREEMPT_RT`） | 不支持，层里直接 fatal |

「可编」= 该族 defconfig 里确实有 `CONFIG_PREEMPT_RT=y`，理论上换分支即生效；**没有逐板上电验证**。

### 1.2 前置条件

1. 已经能用 `kas build kas/lubancat.yml` 编出可启动的非 RT 镜像（见 README 第 5、6 章）。
   RT 不动 U-Boot、不动 boot 分区布局、不动设备树切换逻辑，前提是那条链是通的。
2. 磁盘：`build-rt/` 的 `tmp` 与主构建同量级（内核 + 六个族共 5277 个 task 的一部分），
   再留 20~30 GB。`DL_DIR` / `SSTATE_DIR` 与主构建共享，不额外占。
3. 网络：首次会从 `github.com/LubanCat/kernel` 拉 RT 分支（与非 RT 同一个仓库，
   已有该裸仓时只增量取一个 commit）。国内建议先 `source ./scripts/setup-mirror.sh`。
4. `rk3528` 不要试：编出来不会报错，只会得到一颗**非 RT** 内核。

---

## 2. 设计取舍

### 2.1 为什么参数化 bbappend，而不是在 RT 层重写 SRC_URI

`meta-lubancat/recipes-kernel/linux/linux-rockchip_6.1.bbappend` 里是**整份替换**：

```bitbake
SRC_URI = "git://github.com/LubanCat/kernel.git;protocol=https;branch=lbc-develop-6.1"
...
SRC_URI += "file://lubancat-family.cfg"
SRC_URI += "file://0001-arm64-dts-lubancat-4-v1-enable-hdmi0-vp0.patch"
SRC_URI += "file://0002-wifi-out-of-tree-paths.patch"
```

如果 RT 层也写一句 `SRC_URI = "git://...;branch=lbc-develop-6.1-rt36"`，后应用的赋值会把
前三项一起冲掉，后果是：

| 丢的东西 | 表现 |
|---|---|
| `lubancat-family.cfg` | `CONFIG_FIQ_DEBUGGER*` 没了 → **串口全黑但系统起来了**；以太网/NFS root 相关项也没了 |
| `0001-...-hdmi0` | HDMI 不亮，`/sys/class/drm` 里没有 HDMI 的 card |
| `0002-...-wifi` | vendor 无线驱动编不过（本层已把 vendor 驱动关掉，这个反而要主动摘） |

所以 meta-lubancat 把「分支」和「commit」抽成两个弱赋值变量：

```bitbake
LUBANCAT_KERNEL_BRANCH ?= "lbc-develop-6.1"
LUBANCAT_KERNEL_SRCREV ?= "a0c672347152a0ea0713a043f1d1c4ec4323ff93"
SRC_URI = "git://github.com/LubanCat/kernel.git;protocol=https;branch=${LUBANCAT_KERNEL_BRANCH}"
SRCREV  = "${LUBANCAT_KERNEL_SRCREV}"
```

RT 层只写两行强赋值。不启用 RT 时展开结果与改造前逐字节相同，非 RT 构建不受影响
（唯一可能的影响是内核任务的变量依赖集合多了两个名字，若触发一次重编，产物相同）。

### 2.2 层优先级为什么是 15

bbappend 按 `BBFILE_PRIORITY` **从低到高**应用，高优先级后写、后生效。本层需要：

1. 用 `=` 覆盖 `LUBANCAT_KERNEL_*`（低优先级层里是 `?=`，谁后写谁赢）；
2. 让 `SRC_URI += file://lubancat-realtime.cfg` 排在 `family.cfg` 之后 ——
   kernel-yocto 按 `SRC_URI` 顺序把 `.cfg` 交给 `merge_config.sh`，**最后一份生效**。

`meta-lubancat` 是 10，本层取 15。同优先级下顺序不作保证，所以不留成"也是 10"。

---

## 3. 层结构

```
meta-realtime/
├── COPYING.MIT
├── README.md
├── conf/layer.conf                                    # BBFILE_PRIORITY_realtime = 15
└── recipes-kernel/linux/
    ├── linux-rockchip_6.1.bbappend                     # 换分支 / 摘 0002 / 加 cfg / 机器守卫
    └── files/lubancat-realtime.cfg                     # RT 配置片段
kas/realtime.yml                                        # overlay：追加层、共享 DL/sstate、防呆告警
```

层里**没有**镜像 recipe、没有 packagegroup：RT 复用 `lubancat-image-minimal` / `-net`。
原因是 `meta-openembedded` scarthgap 全树没有 `rt-tests`（cyclictest），专门做一个 RT 镜像
也装不进延迟测试工具，反而多一份没人验证的配方（延迟测量见第 8 章）。

---

## 4. 构建

### 4.1 触发

```bash
cd /path/to/yocto-meta-lubancat

# 标准 RT 构建（minimal + extboot）
KAS_BUILD_DIR=$PWD/build-rt kas build kas/lubancat.yml:kas/realtime.yml

# 换机器
KAS_MACHINE=lubancat-rk3568 KAS_BUILD_DIR=$PWD/build-rt \
  kas build kas/lubancat.yml:kas/realtime.yml

# 换镜像档
KAS_TARGET="lubancat-image-net extboot-image" KAS_BUILD_DIR=$PWD/build-rt \
  kas build kas/lubancat.yml:kas/realtime.yml
```

冒号语法等价于「后一个 include 覆盖前一个」，两个文件同仓库所以合法。`kas/lubancat.lock.yml`
照常生效（lock 对命令行文件与被 include 的文件都生效）；`kas/realtime.yml` 没有 lock 是正常的，
它不引入新 repo。

### 4.2 `KAS_BUILD_DIR` 不是可选项

RT 与非 RT 的 deploy 产物**同名**：`${DEPLOY_DIR_IMAGE}/{Image, boot-ext2.img, dtb/*.dtb}`。
共用 `build/` 时后编的那套会把前一套覆盖。最坏的表现不是构建报错，而是：

> 烧完机、串口正常、`systemctl` 正常，但 `uname -r` 没有 `-rt36`、`/sys/kernel/realtime` 不存在。

`KAS_BUILD_DIR=$PWD/build-rt` 把 `TOPDIR` 整体换掉，`TMPDIR`、`DEPLOY_DIR`、`latest/` 软链
全部跟着走。`DL_DIR` / `SSTATE_DIR` 在 `kas/realtime.yml` 里显式指回主构建：

```bitbake
DL_DIR     = "${TOPDIR}/../build/downloads"
SSTATE_DIR = "${TOPDIR}/../build/sstate-cache"
```

- **可以共享**：`DL_DIR` 按 URL+rev 内容寻址；`SSTATE_DIR` 的对象不可变、原子 rename，
  bitbake 自带文件锁。
- **不能共享**：`TMPDIR`。`work/`、`deploy/`、`pkgdata/` 全按它组织。
- 这里用 `..` 只对 DL/sstate 安全；`TMPDIR` 含 `..` 会被 sanity checker 直接拒。

忘设 `KAS_BUILD_DIR` 时 `kas/realtime.yml` 里的匿名函数会 `bb.warn` 一次（只告警不阻断）。

### 4.3 与非 RT 并存时的目录对照

| 路径 | 非 RT | RT |
|---|---|---|
| TOPDIR | `build/` | `build-rt/` |
| TMPDIR | `build/tmp` | `build-rt/tmp` |
| deploy | `build/tmp/deploy/images/<machine>` | `build-rt/tmp/deploy/images/<machine>` |
| `latest/` | `build/latest` | `build-rt/latest` |
| DL / sstate | `build/downloads`、`build/sstate-cache` | 同一份 |

`extboot-image` 通过 `[depends] virtual/kernel:do_deploy` 在**同一 TMPDIR** 内取 `Image` 与
`dtb/`，所以 RT 镜像的 boot 分区里装的必然是 RT 内核 —— 这是「隔离 TMPDIR」而不是
「只改一个 DEPLOY_DIR」的根本原因。

---

## 5. 配置解读（`lubancat-realtime.cfg`）

### 5.1 合并顺序与两个语法坑

```
lubancat_linux_rkXXXX_defconfig  →  lubancat-family.cfg  →  lubancat-realtime.cfg
（后者覆盖前者，靠 SRC_URI 顺序 + 层优先级 15 保证）
```

| 坑 | 说明 |
|---|---|
| `# CONFIG_X is not set` 无效 | `merge_config.sh` 把它当注释整行删掉。**关项必须写 `CONFIG_X=n`**。`family.cfg` 末尾那句 `# CONFIG_WERROR is not set` 就是死代码，WERROR 一直是 y |
| choice 成员 | 抢占模型、tick 模式都是 choice，语义上「选一个」，写 `=y` 那一个即可；但**旧的成员要显式 `=n`**，否则 `olddefconfig` 会保留 `.config` 里先出现的那个（见 5.3） |

### 5.2 抢占模型

```ini
CONFIG_PREEMPT_RT=y
```

`kernel/Kconfig.preempt` 里 `PREEMPT_RT depends on EXPERT && ARCH_SUPPORTS_RT`。arm64 满足后者；
前者由 defconfig 的 `CONFIG_EMBEDDED=y` 间接 `select EXPERT`（defconfig 里**没有** `CONFIG_EXPERT` 行，
不用去找）。如果哪天上游把 `EMBEDDED` 删了，这一项会被 `olddefconfig` 静默清掉 —— 所以验收只看
`.config` 与 `/sys/kernel/realtime`，不看「我写了」。

### 5.3 tick：RT 分支的 defconfig 其实把 tickless 关了

`lubancat_linux_rk3588_defconfig` 同时有：

```ini
CONFIG_HZ_PERIODIC=y
CONFIG_NO_HZ=y
```

`NO_HZ` 是被 `NO_HZ_IDLE` / `NO_HZ_FULL` **select 的隐藏符号**，不参与 choice；真正生效的
choice 成员是 `HZ_PERIODIC`（`kernel/time/Kconfig` 里 `choice "Timer tick handling"`）。
也就是说这颗「RT 内核」默认每个 tick 都打断 CPU，空闲核也不例外 —— 抖动的下限被抬高、功耗也高。

本层改成：

```ini
CONFIG_HZ_PERIODIC=n
CONFIG_NO_HZ_IDLE=y
CONFIG_HZ_1000=y
CONFIG_HIGH_RES_TIMERS=y
```

两行都写的理由：只写 `NO_HZ_IDLE=y` 时，`.config` 里 `CONFIG_HZ_PERIODIC=y` 还在，
`olddefconfig` 处理 choice 会保留先出现的那个，你的设置白写。

### 5.4 延迟相关

| 项 | 值 | 理由 |
|---|---|---|
| `CONFIG_RT_GROUP_SCHED` | `n` | 按 cgroup 给 RT 分时间配额（`rt_runtime_us`），对硬实时是纯负担 |
| `CONFIG_RCU_BOOST` | `y` | 缺了它，被抢占的 RCU 读临界区没有优先级继承，普通线程能把 RT 线程卡在 `synchronize_rcu()` 上几十毫秒 |
| `CONFIG_RCU_NOCB_CPU` | `y` | 配合 cmdline `rcu_nocbs=` 把回调移出 |
| `CONFIG_PROVE_LOCKING` / `CONFIG_DEBUG_PREEMPT` / `CONFIG_DEBUG_ATOMIC_SLEEP` / `CONFIG_LOCK_STAT` / `CONFIG_DEBUG_MUTEXES` / `CONFIG_DEBUG_SPINLOCK` | `n` | 单项就能把最坏延迟推到毫秒级；lockdep 在 RT 下还有一批已知误报 |

运行时的 `/proc/sys/kernel/sched_rt_runtime_us` 保持默认 `950000`，**不要**设 `-1`：
那会关掉「RT 线程饿死系统」的保护，用户态一次死循环就能锁死整机。

### 5.5 无线：vendor 全关，主线保留

```ini
CONFIG_RTL8189FS=n        # vendor，SDIO
CONFIG_RTL8821CU=n        # vendor，USB
CONFIG_RTL8851BE=n        # vendor，PCIe（与主线 rtw89 抢同一个 PCI ID）
CONFIG_RTL8852BE=n
CONFIG_AIC_WLAN_SDIO_SUPPORT=n
CONFIG_AIC_WLAN_USB_SUPPORT=n
CONFIG_AIC8800_SDIO_WLAN_SUPPORT=n
CONFIG_AIC8800_SDIO_BTLPM_SUPPORT=n
CONFIG_AIC8800_USB_WLAN_SUPPORT=n
CONFIG_AIC_USB_LOADFW_SUPPORT=n

CONFIG_WL_ROCKCHIP=y      # 不能关！它 select MAC80211，主线 rtw88/rtw89 depends on 它
CONFIG_RTL8188EE=m        # 主线：RTL8188CE
CONFIG_RTW88=m
CONFIG_RTW88_8822CE=m     # 主线：RTL8822CE
CONFIG_RTW89=m
CONFIG_RTW89_8851BE=m     # 主线：RTL8851BE
CONFIG_RTW89_8852BE=m     # 主线：RTL8852BE
```

关 vendor 的两个理由：

1. 它们在 `O=${B}` 构建下需要 `0002-wifi-out-of-tree-paths.patch` 才能编过，而这份补丁在 RT 分支
   **上下文不匹配**（RT 分支把 `rtl8821cu` 的三个 `.mk` 改写成了 `ccflags-y` 风格，非 RT 分支是
   `EXTRA_CFLAGS`）。层里直接把 0002 从 `SRC_URI` 摘掉，摘了就不能再开这些驱动。
2. **AIC8800 是必踩的坑**：RT 分支 defconfig 里 `CONFIG_AIC8800_USB_WLAN_SUPPORT=m`，而 0002 正好改过
   `aic8800_usb/aic8800_fdrv/Makefile`。不把它写成 `=n`，摘掉补丁后 `do_compile` 会失败。

现场在用的 RTL8822CE 走主线 `rtw88`，RT 下工作良好，不受影响。确实需要 SDIO/USB 模组时，
按第 10 章 R1 的做法给 RT 分支单独做一份补丁。

### 5.6 WERROR

```ini
CONFIG_WERROR=n
```

非 RT 构建里 `WERROR` 一直是 `y`（`family.cfg` 那句注释无效）。RT 补丁 + gcc 13 在 BSP 代码上
告警面更大，首版先关，避免「编译失败在一个从没改过的文件里」。CI 稳定后删掉这一行即回到 defconfig 的 `y`。

### 5.7 可选，首版不开

| 项 | 开启条件 |
|---|---|
| `CONFIG_NO_HZ_FULL=y` | 能同时给 `isolcpus=` / `nohz_full=` / 绑核。RK3588S 是 4×A76 + 4×A55，隔离核必须同 cluster，配错的表现是隔离核不再收 tick、但唤醒也上不去 |
| `CONFIG_SLUB_CPU_PARTIAL=n` | 只在 cyclictest 高负载用例里看到 `mm/slub` 相关抖动时试 |
| `CONFIG_FUNCTION_TRACER=y` | 只在要用第 8.3 节的 ftrace 方案时开（defconfig 未开） |

---

## 6. 产物与打包

```bash
DEPLOY=$PWD/build-rt/tmp/deploy/images/lubancat-4-v1 \
WORK=$PWD/build-rt/updateimg \
IMAGE=lubancat-image-minimal \
./scripts/make-updateimg.sh

sudo upgrade_tool uf build-rt/updateimg/update.img
```

两个变量都必须改：

- 只改 `DEPLOY` 不改 `WORK`：脚本开头 `rm -rf "$WORK"` 会删掉非 RT 的打包中间目录，
  两个 `update.img` 也会互相覆盖。
- `boot-ext2.img` 的 128 MiB 断言与非 RT 一致，RT 内核变大不影响（`Image` 只有几十 MB，
  分区里主要是全族 dtb/dtbo）。

打包前不上板也能确认 boot 分区里是哪颗内核：

```bash
debugfs -R "ls -l /" build-rt/tmp/deploy/images/lubancat-4-v1/boot-ext2.img
debugfs -R "dump /uEnv/uEnv.txt /dev/stdout" build-rt/tmp/deploy/images/lubancat-4-v1/boot-ext2.img | head -3
```

`/lib/modules/` 的目录名会变成 `6.1.99-rt36-lubancat`，与非 RT 的 `6.1.99-lubancat` 不同 ——
即使误把两套 rootfs 混装，模块也不会被错加载（`insmod` 会以 vermagic 不符拒绝）。

---

## 7. 验收

### 7.1 构建期（不必等上板，这是最强证据）

```bash
# ① 最终 SRC_URI：应为 git → family.cfg → 0001 → realtime.cfg，且不含 0002
KAS_BUILD_DIR=$PWD/build-rt kas shell kas/lubancat.yml:kas/realtime.yml -c \
  'bitbake -e virtual/kernel | grep -E "^(SRC_URI|SRCREV|KBUILD_DEFCONFIG)="'

# ② 层顺序：realtime 必须排在 lubancat 之后
KAS_BUILD_DIR=$PWD/build-rt kas shell kas/lubancat.yml:kas/realtime.yml -c \
  'bitbake-layers show-layers'

# ③ 只跑到 config，检查生成的 .config
KAS_BUILD_DIR=$PWD/build-rt kas shell kas/lubancat.yml:kas/realtime.yml -c \
  'bitbake -c kernel_configme virtual/kernel'

CFG=$(ls build-rt/tmp/work/*/linux-rockchip/*/build/.config | head -1)
grep -E '^CONFIG_(PREEMPT_RT|NO_HZ_IDLE|HZ_1000|RCU_BOOST|IKCONFIG_PROC|WL_ROCKCHIP)=' $CFG
grep -E '^CONFIG_(RTW88|RTW88_8822CE|RTW89|RTW89_8851BE|RTW89_8852BE|RTL8188EE)=' $CFG

# ④ 这些必须是 not set
grep -E 'HZ_PERIODIC|WERROR|RTL8189FS|RTL8821CU|AIC8800|PROVE_LOCKING' $CFG

# ⑤ 内核 release 串：期望 6.1.99-rt36-lubancat
cat build-rt/tmp/work/*/linux-rockchip/*/build/include/config/kernel.release
```

`kernel.release` 是构建机上能给的最强证据：它由源码树 `Makefile` + `CONFIG_LOCALVERSION`
+ `localversion-rt` 算出，`-rt36` 在就说明源码树确实是 RT 分支。

### 7.2 上板

```bash
uname -r                                   # 6.1.99-rt36-lubancat
cat /sys/kernel/realtime                   # 1 —— 只有 CONFIG_PREEMPT_RT 才会导出这个节点
zcat /proc/config.gz | grep -E 'CONFIG_(PREEMPT_RT|HZ=|NO_HZ_IDLE|RT_GROUP_SCHED|RCU_BOOST)'
cat /proc/sys/kernel/sched_rt_runtime_us   # 950000
ps -eLo comm | grep -c '^irq/'             # >0，说明中断已线程化
dmesg | grep -iE 'sleeping function|BUG:|scheduling while atomic'   # 期望无输出
ls /lib/modules/                           # 只应有 6.1.99-rt36-lubancat
```

`/sys/kernel/realtime` 比 `uname -r` 更可靠：前者由 `kernel/ksysfs.c` 在 `CONFIG_PREEMPT_RT`
下条件编译，源码树上贴了 `-rt36` 但配置没生效的情况（本层第 5.2 节说的那种）能被它抓出来。

### 7.3 失败定位

| 症状 | 先看这里 |
|---|---|
| `do_patch` failed，`rtl8821cu/hal/phydm/phydm.mk` | `log.do_patch` 里的 `Hunk #N FAILED`；说明 0002 没摘干净 |
| `aic8800_usb/...` 编译报头文件找不到 | 5.5 节的 AIC 六项没写或写错符号名 |
| `PREEMPT_RT` 没生效 | `grep PREEMPT_RT $CFG`、`grep -E 'EXPERT\|EMBEDDED' $CFG`、`bitbake -e virtual/kernel \| grep ^KBUILD_DEFCONFIG` |
| cfg 被覆盖 | `bitbake -e virtual/kernel \| grep ^SRC_URI` 看顺序；再 `bitbake -c kernel_configcheck -f virtual/kernel` |
| 能起但 `uname -r` 没 `-rt36` | 多半是 deploy 被非 RT 覆盖：`ls -l build/tmp/deploy/images/*/Image build-rt/tmp/deploy/images/*/Image` |
| `Unable to find revision ...` | `git ls-remote https://github.com/LubanCat/kernel.git refs/heads/lbc-develop-6.1-rt36` 与 bbappend 比对 |
| 想看 `.config` 但 work 目录空了 | `rm_work` 已删；打开 bbappend 最后的 `RM_WORK_EXCLUDE += "linux-rockchip"` 重编 |

---

## 8. 延迟实测

### 8.1 为什么镜像里没有 cyclictest

`meta-openembedded` scarthgap 全树没有 `rt-tests`（已 grep 验证），`opkg install rt-tests` 也拿不到。
本层刻意不塞一个没验证过的 recipe —— 首版的判据用第 7.2 节那组「RT 是否生效」，量化延迟用下面的办法。

### 8.2 SDK 交叉编译 rt-tests（能拿到标准指标）

```bash
# 用 RT 构建目录生成 SDK（复用已编好的工具链）
KAS_BUILD_DIR=$PWD/build-rt kas shell kas/lubancat.yml:kas/realtime.yml -c \
  'bitbake -c populate_sdk lubancat-image-minimal'

# 主机上装 SDK 后交叉编译。若报 libnuma 头文件缺失，加 NUMA=0 关掉 NUMA 支持
git clone https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
cd rt-tests && make CROSS_COMPILE=aarch64-poky-linux- NUMA=0
scp cyclictest root@<board>:/usr/bin/

# 板上：主线程优先级 80，周期 200us，跑 30 分钟，同时加背景负载
dd if=/dev/zero of=/tmp/x bs=1M count=2000 &
ping -f <gateway> &
cyclictest -m -Sp90 -i200 -h400 -D30m -q
```

### 8.3 ftrace `wakeup_rt`（零依赖，先看有没有尖刺）

```bash
mount -t debugfs none /sys/kernel/debug
cd /sys/kernel/debug/tracing
echo 0 > tracing_on; echo > trace
echo wakeup_rt > current_tracer
echo 1 > tracing_on; sleep 60; echo 0 > tracing_on
grep -o 'now=[0-9]*' trace | cut -d= -f2 | sort -n | tail -5   # 单位 us
```

前提是 `CONFIG_FUNCTION_TRACER=y`（defconfig 没开，要先在 cfg 的可选段打开）。

### 8.4 判据与尖刺来源

判据要按板实测标定，不要照抄别的板子。RK3588S 上 `-S -p90 -i200` 的 max 若稳定在 100 µs 以内
属健康；出现毫秒级 max 时按下表排查：

| 尖刺来源 | 特征 | 处置 |
|---|---|---|
| `fiq-debugger` 控制台 | 串口大量输出时出现，`loglevel=7` 加剧 | 生产镜像把 `LUBANCAT_CMDLINE` 的 `loglevel=7` 降到 4 |
| GPU / NPU 驱动 | 跑 kmscube / rknn 时出现，伴随 `scheduling while atomic` | RT 首版只出 minimal/net；需要时 A/B 关 `MALI_BIFROST` / `ROCKCHIP_RKNPU` |
| 存储后台 | `dd` 写 eMMC 时周期性抖 | 降低写压力，或把写线程放到低优先级核 |
| 未隔离的负载 | 负载核与测试核共用 | `isolcpus` + `nohz_full` + `taskset`（对应 5.7 节的可选项） |

---

## 9. 与非 RT 的差异

| 维度 | 非 RT（`kas/lubancat.yml`） | RT（`kas/lubancat.yml:kas/realtime.yml`） |
|---|---|---|
| 分支 / SRCREV | `lbc-develop-6.1` / `a0c6723` | `lbc-develop-6.1-rt36` / `3d027a8` |
| `uname -r` | `6.1.99-lubancat` | `6.1.99-rt36-lubancat` |
| 抢占模型 | `PREEMPT_VOLUNTARY`（defconfig 原值） | `PREEMPT_RT` |
| tick | tickless（无 `HZ_PERIODIC`） | `NO_HZ_IDLE` + `HZ_1000` |
| vendor 无线 | `RTL8189FS=m` / `RTL8821CU=m`，需要 0002 补丁 | 全 `n`，0002 从 SRC_URI 摘除 |
| AIC8800 | `=m`（0002 修过它的 Makefile） | 全 `n` |
| 主线无线 | rtw88/rtw89 `=m` | 不变 |
| `WERROR` | y（family.cfg 的关项是死代码） | n |
| 构建目录 | `build/` | `build-rt/`（TMPDIR 隔离） |
| DL / sstate | 各自默认 | 共享主构建那一份 |
| 打包 | 直接跑脚本 | 需 `DEPLOY=` / `WORK=` |
| 软件栈 | minimal / net / full | 首版只建议 minimal / net（libmali、rknpu 在 RT 下未验证） |
| 延迟测试工具 | 无 | 无（同上，需交叉编译） |

---

## 10. 风险与缓解

| # | 风险 | 症状 | 判断 | 缓解 |
|---|---|---|---|---|
| R1 | 0002 补丁残留 | `do_patch` failed | `log.do_patch` 里 `Hunk #N FAILED` | 本层已 `SRC_URI:remove`。确需 vendor 驱动时，按 RT 分支的 `ccflags-y` 版本重做一份 `0003-...-rt.patch` 放本层 `files/`，**不要**改 meta-lubancat 那份 |
| R2 | AIC8800 未关 | `aic8800_usb/aic8800_fdrv` 编译失败 | `log.do_compile` 里的头文件错误 | cfg 里六个 AIC 符号全 `=n` |
| R3 | deploy 同名覆盖 | 能起但 `uname -r` 无 `-rt36`；`/sys/kernel/realtime` 不存在 | 两套 deploy 下 `Image` 的 mtime | `KAS_BUILD_DIR=build-rt`；overlay 里的 warn |
| R4 | `HZ_PERIODIC` 残留 | 空闲仍有固定 tick，max 偏高 | `/proc/config.gz` 里应 not set | cfg 同时写 `HZ_PERIODIC=n` 与 `NO_HZ_IDLE=y` |
| R5 | libmali / rknpu 在 RT 下 | `sleeping function called from invalid context`、kbase/rknpu 超时 | `dmesg`；临时开 `DEBUG_ATOMIC_SLEEP` 复现 | 首版只出 minimal/net；需要时关 `MALI_BIFROST` / `ROCKCHIP_RKNPU` 做 A/B |
| R6 | `KBUILD_DEFCONFIG` 是强赋值 | 想换 defconfig 换不动 | `bitbake -e \| grep ^KBUILD_DEFCONFIG` | 首版不换（RT defconfig 自带 RT）；确需换用 `KBUILD_DEFCONFIG:lubancat-rk3588 = "..."` |
| R7 | rk3528 假 RT | 编出来不是 RT | `grep PREEMPT_RT $CFG` | bbappend 里 `bb.fatal` 直接拦住 |
| R8 | RT 分支 SRCREV 漂移 / 上游回退 | `Unable to find revision` | `git ls-remote` 比对 | SRCREV 钉死 + `docs/VERSION-MATRIX.md` 记录 + 每次发版复核 |
| R9 | `rm_work` 删了 `.config` | 事后无法核对、调 cfg 要从零编 | `build-rt/tmp/work/*/linux-rockchip/*/build` 为空 | 按 7.1 在 build 前核对；或打开 `RM_WORK_EXCLUDE` |
| R10 | 内核模块跨构建混装 | `insmod` 报 vermagic 不符 | `modinfo -F vermagic xxx.ko` | TMPDIR 已隔离；不要跨构建建 opkg feed |

---

## 11. 回退与清理

回退不需要改任何代码，只要不叠加 overlay：

```bash
kas build kas/lubancat.yml          # 回到非 RT，产物仍在 build/
```

清理 RT 构建（先删 tmp，再删 sstate 里的 RT 对象才有意义，否则下次会从缓存还原）：

```bash
rm -rf build-rt/tmp build-rt/updateimg build-rt/deploy-rt 2>/dev/null
# 想彻底回收 sstate 空间再执行：find build/sstate-cache -newer build-rt -name '*.tgz' -delete
rm -rf build-rt
```

`build/downloads/git2/github.com.LubanCat.kernel.git` 里会多出 RT 分支的对象（几十 MB），
共用下载目录时留着不影响非 RT；想清掉需重跑 `git gc`，一般不必。

---

## 附录 A 命令速查

```bash
# 构建
KAS_BUILD_DIR=$PWD/build-rt kas build kas/lubancat.yml:kas/realtime.yml

# 看最终 SRC_URI / SRCREV / defconfig
KAS_BUILD_DIR=$PWD/build-rt kas shell kas/lubancat.yml:kas/realtime.yml -c \
  'bitbake -e virtual/kernel | grep -E "^(SRC_URI|SRCREV|KBUILD_DEFCONFIG)="'

# 只生成 .config
KAS_BUILD_DIR=$PWD/build-rt kas shell kas/lubancat.yml:kas/realtime.yml -c \
  'bitbake -c kernel_configme virtual/kernel'

# 重编内核（改了 cfg 之后）
KAS_BUILD_DIR=$PWD/build-rt kas shell kas/lubancat.yml:kas/realtime.yml -c \
  'bitbake -c cleansstate virtual/kernel && bitbake virtual/kernel extboot-image'

# 打包
DEPLOY=$PWD/build-rt/tmp/deploy/images/lubancat-4-v1 WORK=$PWD/build-rt/updateimg \
  IMAGE=lubancat-image-minimal ./scripts/make-updateimg.sh

# 板上
uname -r; cat /sys/kernel/realtime; zcat /proc/config.gz | grep PREEMPT_RT
```

## 附录 B 报错速查

| 现象 | 原因 | 处置 |
|---|---|---|
| `Hunk #1 FAILED ... phydm.mk` | 0002 没有从 RT 的 SRC_URI 摘掉 | 确认 `bitbake -e \| grep ^SRC_URI` 里没有 0002 |
| `fatal error: drv_types.h` | vendor 驱动被打开了（cfg 顺序被覆盖） | `bitbake -e \| grep ^SRC_URI`，`lubancat-realtime.cfg` 必须排在最后 |
| `nothing provides kernel-module-rtw88_8822ce` | 包组里写了下划线 | 用短横线 `kernel-module-rtw88-8822ce`（见手册 7.7.3） |
| `bb.fatal: rk3528 的 ... 没有开 CONFIG_PREEMPT_RT` | 选了不支持的机器 | 换 `lubancat-4-v1` / `lubancat-rk3588` 等 |
| `Unable to find revision 3d027a8...` | RT 分支被 force-push 或网络问题 | `git ls-remote` 复核；必要时更新 SRCREV |
| `uname -r` 没 `-rt36` 但构建成功 | 烧的是非 RT 的 `update.img`，或 deploy 被覆盖 | 检查 `DEPLOY=` 是否指到 `build-rt` |
| `/sys/kernel/realtime` 不存在 | `CONFIG_PREEMPT_RT` 没生效 | `zcat /proc/config.gz \| grep -E 'PREEMPT\|EMBEDDED'` |
