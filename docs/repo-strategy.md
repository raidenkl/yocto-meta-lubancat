# 仓库管理方式：选型与结论

本文回答一个问题：**一个只有几十个文件、却依赖 4 个上游大仓 + 3 个 BSP 仓的 Yocto 层，应该怎么放上 GitHub。**

结论先写在这里：**层仓库 + kas + lockfile**。
下面的矩阵与论证用于说明为什么，以及什么情况下应该换别的做法。

---

## 1. 七种方式对比

评级：◎ 好 / ○ 中 / △ 差。"体积"指开发者 `git clone` 之后工作区里的量级。

| 方式 | 可复现性 | 上手成本 | 升级 Yocto 的代价 | 仓库体积 | 漂移风险 | PR / review 体验 | 一句话适用场景 |
|---|---|---|---|---|---|---|---|
| A 纯层仓库 + 手工版本矩阵 | ○ 靠人抄 SHA | ◎ clone 即用 | ○ 改文档 + 重拉 | ◎ 221 KB | △ 分支 HEAD 每天都在变 | ◎ 纯文本 diff | 单人一次性交付，不再跟上游 |
| **B 层仓库 + kas + lock** ★ | ◎ yml + lock 双锁 | ○ 多装一个 `kas` | ◎ 改 branch + `kas lock --update` | ◎ 221 KB | ○ lock 由人显式提交 | ◎ diff 是可读的 commit 变更 | 层数少、要交接、要长期跟 LTS |
| C git submodule | ◎ gitlink 即 SHA | △ `--recursive` + 大仓 + 游离头 | ○ 逐个子模块 checkout 再 commit | △ `.git/modules` 数百 MB~1 GB | ○ 漏提 gitlink / 游离头丢提交 | △ 只有 `Subproject commit` 一行 | 上游是你自己维护的 fork；或必须离线整树 |
| D Google repo + manifest | ◎ manifest 锁全仓 | △ 装 repo、要 Linux/WSL | ○ 改 manifest revision | ○ 元数据 + 多仓 | ○ | △ manifest 不在 PR 视野里 | 几十个仓的整机 SDK（原厂那种 `repo init`） |
| E 单体仓库（全量提交上游） | ○ 一个 SHA 但混入二进制 | ◎ | △ 每次升级是数万文件替换 | △ 数 GB 起 | ○ 但与上游永久分叉 | △ 升级 PR 无法 review | 交付即冻结快照、永不跟上游 |
| F combo-layer | ◎ conf 记每层 revision | △ 额外工具 + 解冲突 | △ 每次 pull 都要 rebase | ○ | ○ | △ 合并提交淹没业务改动 | 必须把上游"摊平"成单一可交付仓库 |
| G git subtree | ○ `--squash` 丢历史 | ○ | △ 每次 pull 冲突 | △ 上游历史进本仓 | ○ | △ | 只有 1~2 个小层要嵌进主应用仓 |

## 2. 为什么选 B

1. **与现有资产零冲突**：`kas/lubancat.yml` 已经把 repos / layers / local.conf 三件事写完了，
   lock 只是给它补一份"机读的版本断言"，不需要重排目录、重写脚本。
2. **lock 是唯一同时被人和机器读懂的 pin**：`kas/lubancat.lock.yml` 里是 4 行 `commit:`，
   diff 就是"这次升级了什么"，reviewer 三秒看完。
3. **体积零成本**：仓库永远 221 KB；上游按需拉、可浅克隆、可复用 `DL_DIR`。
   层里不复制 `boot.cmd` / `uEnv` / `rk*.inc`，仓库里不复制 poky——同一个"薄"的哲学。
4. **一条命令满足"克隆者从零到烧写"**：`kas build kas/lubancat.yml`。
5. **升级路径最短**：改 `kas/lubancat.yml` 的 4 处 `branch:` → `kas lock --update` → 看 diff → 提交。

## 3. 为什么不用 submodule（具体代价）

1. **clone 成本与收益倒挂**：本仓 48 个文件、221 KB，`git clone` 是秒级。submodule 会把
   poky / meta-arm / meta-openembedded / meta-rockchip 的 `.git/modules` 一起装进工作区
   （浅克隆也是数百 MB~1 GB），而 build 时这 4 个目录**本来就应该被忽略**。
2. **升级动作更长且容易"假成功"**：kas 是"改一行 + `kas lock --update`"，diff 4 行；
   submodule 是 4 次 `cd X && git checkout <tag>` + 回父仓 `git add` 4 个路径 + commit。
   **漏掉一个子模块不会报错**，`git status` 也不会提醒你"这个层还是旧的"。
3. **两种经典事故**：
   - 在 `poky/` 的 detached HEAD 里 commit 了本地修改 → 父仓毫无感知，下次
     `git submodule update` 一执行，改动凭空消失；
   - 切分支后子模块不跟着切，`git status` 干净，实际用的是旧层。
   如果把自己的层也做成 submodule（很常见），这两类事故直接作用在最贵的那部分代码上。
4. **PR 不可读**：review 里只看到 `Subproject commit 4f1c…`，看不出上游改了什么；
   `kas.lock.yml` 的 diff 则直接写着"poky 从 a1b2 → c3d4"。
5. **Windows 侧成本不对称**：本仓库在 Windows 编辑、Linux 构建。submodule 叠加
   `.gitmodules` URL 改写（国内要配 `insteadOf`）、`core.autocrlf`、可执行位丢失三件事，
   是新人第一小时的常见卡点。
6. **心智冲突**：submodule 隐含"上游是我仓库的一部分"，容易诱导 vendoring。
   本手册第 13 章评估过的 `CHTUZKI/yocto-rk3588-core` 就是这个模式的终局——
   submodule + 预编译 `MiniLoaderAll.bin` + `构建日志.txt` 全部入库，
   最后"哪个 loader 对应哪个 rkbin"无法追溯。

submodule 的独家能力（离线完整树）可以用 `kas lock` + `DL_DIR` 预热 + `BB_GENERATE_MIRROR_TARBALLS`
覆盖，而且不污染日常 clone。

## 4. 仓库布局

```
yocto-meta-lubancat/          # 仓库根 = kas 的 work dir
├── README.md                 # 面向使用者：从装依赖到烧写
├── LICENSE  THIRD-PARTY.md  CHANGELOG.md
├── kas/
│   ├── lubancat.yml          # 机器无关的 repos + local.conf（machine 可被 KAS_MACHINE 覆盖）
│   └── lubancat.lock.yml     # 4 个上游层的 commit（入库）
├── build-conf/local.conf.sample
├── scripts/                  # host-deps / fetch-layers / setup-mirror / make-updateimg / flash-emmc
├── tools/rkpack/             # afptool + rkImageMaker（厂商二进制，见 THIRD-PARTY）
├── docs/                     # manual.md / VERSION-MATRIX.md / 本文件
├── meta-lubancat/            # 层本体
└── （运行时生成，全部 .gitignore）build/ poky/ meta-arm/ meta-openembedded/ meta-rockchip/
```

## 5. 版本指针：三处真相

| 元件 | 锁在哪 | 谁更新 | 何时变 |
|---|---|---|---|
| poky / meta-arm / meta-openembedded / meta-rockchip | `kas/lubancat.lock.yml` 的 `commit:` | `kas lock --update kas/lubancat.yml`（人执行并提交） | 有意升级 Yocto 时 |
| LubanCat kernel / u-boot / rkbin | bbappend 的 `SRCREV` | 手工改，改完必须编译验证（DDR bin、`CONFIG_LOADER_INI` 断言） | 换 BSP 版本时 |
| 本层自身 | git tag + `LAYERVERSION_lubancat` | `git tag -a vX.Y.Z` | 发版 |

规则：

- **`kas/*.lock.yml` 必须入库**；面向使用者的命令永远用带 lock 的那份配置。
- **只在"有意升级"时重新生成 lock**，且必须在 PR 里 review lock 的 diff。
- `build-conf/local.conf.sample` 是示例，不是真相；真相在 `kas/lubancat.yml` 的 `local_conf_header`。
- 不要提交 `build/`、`downloads/`、`sstate-cache/`、`*.wic`、`*.rootfs.*`、`update.img`、`*.bin`。

## 6. 分支与 tag

| 分支 | 何时存在 | 职责 |
|---|---|---|
| `main` | 现在 | 唯一活跃开发线，当前内容对应 scarthgap (5.0) |
| `scarthgap` | 第一次正式 release 时从 tag 切出 | LTS 冻结线，只收 backport |
| `kirkstone` / 其他 | **真机跑通后**才建 | 另一条 Yocto 系列 |

不要预建空的 `kirkstone` 分支：`linux-rockchip_6.1.bbappend` / `u-boot-rockchip.bbappend` 里的
recipe 名与变量在别的系列会变（kirkstone 的 linux-rockchip 是 5.15 线），空分支等于承诺一个
不存在的支持面。

tag 规则：`vMAJOR.MINOR.PATCH`

- MAJOR：`LUBANCAT_*` 变量改名、MACHINE 重命名、分区布局变更
- MINOR：新增 MACHINE / 镜像 / 脚本能力
- PATCH：修复、文档
- 只做过编译验证的里程碑用 `vX.Y.Z-rcN`，tag message 里写明"哪个 MACHINE 上板、日期"

`LAYERVERSION_lubancat` 与 tag 的 `MAJOR.MINOR` 联动（Yocto 生态里层版本用 `X.Y`）。

## 7. 升级到新 Yocto 系列的六步

1. 改 `kas/lubancat.yml` 的 4 处 `branch:`
2. 改 `meta-lubancat/conf/layer.conf` 的 `LAYERSERIES_COMPAT_lubancat`
3. 检查 bbappend 的 recipe 版本名（`linux-rockchip_6.1.bbappend` 在新系列可能不存在）
4. `kas lock --update kas/lubancat.yml`，review lock diff
5. 完整构建 + 上板验收，更新 `docs/VERSION-MATRIX.md`
6. 打 tag，`CHANGELOG.md` 记一条
