# tools/rkpack —— rkfw 打包工具

把 Yocto 产物打成 Rockchip `update.img`（RKDevTool / `upgrade_tool uf` 可刷）需要两个工具：

| 文件 | 作用 | 版本 |
|---|---|---|
| `afptool` | 按 `parameter.txt` 分区表把 `Image/` 目录打成 `update.img`；`-unpack` 可反解 | Android Firmware Package Tool **v2.29** |
| `rkImageMaker` | 给固件加 `RKFW` 头并标记芯片型号（`-RK3588` 等）；`-unpack` 可脱壳 | 与 SDK 同版本 |

## 来源

从 LubanCat Linux SDK 原样复制，未做任何修改：

```
LubanCat_Linux_Generic_Full_SDK/tools/linux/Linux_Pack_Firmware/rockdev/{afptool,rkImageMaker}
```

- 格式：`ELF 64-bit LSB executable, x86-64, statically linked, stripped`
- 体积：2.0 MB + 2.0 MB
- 无动态依赖（`readelf -d` 无 `.dynamic`），任意 x86-64 Linux 可直接跑
- **不能在 ARM 主机（含 Apple Silicon 上的容器）与 macOS 上运行**；这些环境请走 `wic` 路线

## 校验

```bash
cd tools/rkpack && sha256sum -c SHA256SUMS
```

`afptool` 不带参数会打印版本与用法，可用来确认二进制没坏：

```bash
./afptool | head -1        # Android Firmware Package Tool v2.29
```

## 许可

这两个是 Rockchip 的厂商工具，**不是**本仓库 MIT 的一部分，按原样（as-is）再分发，无担保。
详见仓库根目录 `THIRD-PARTY.md`。

不接受厂商二进制再分发的用户：删除本目录，然后

```bash
PACK=/path/to/LubanCat_Linux_Generic_Full_SDK/tools/linux/Linux_Pack_Firmware/rockdev \
  ./scripts/make-updateimg.sh
```

或用 `EXTBOOT=0`/`wic` 路线——`meta-lubancat` 的镜像构建本身不依赖这两个工具。
