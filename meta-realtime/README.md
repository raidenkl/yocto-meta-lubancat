# meta-realtime

把 `virtual/kernel` 切到 LubanCat 的 PREEMPT_RT 分支（`lbc-develop-6.1-rt36`，6.1.99 + rt36）。

本层不提供独立镜像，RT 构建复用 `lubancat-image-minimal` / `lubancat-image-net`。

```bash
KAS_BUILD_DIR=$PWD/build-rt kas build kas/lubancat.yml:kas/realtime.yml
```

完整说明（支持范围、配置项、打包、上板验收、延迟实测、风险）见
[`../docs/realtime.md`](../docs/realtime.md)。层内只有三个文件有意义：
`conf/layer.conf`（优先级 15）、`recipes-kernel/linux/linux-rockchip_6.1.bbappend`
（换分支 + 摘 vendor wifi 补丁 + 加 cfg）、`recipes-kernel/linux/files/lubancat-realtime.cfg`。
