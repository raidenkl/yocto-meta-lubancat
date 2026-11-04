本目录刻意不存放 boot.cmd / uEnv.txt 模板。

原因：这两份模板是随内核树演进的（厂商在 6.1 树里维护了 30 份按板分文件的
uEnvLubanCat*.txt，每份都列好了该板可用的 dtoverlay 候选）。一旦在层里复制一份，
内核升级后就会与源码树漂移，而且 30 份模板的维护成本不可接受。

extboot-image.bb 的取数路径：
  ${STAGING_KERNEL_DIR}/arch/arm64/boot/dts/rockchip/uEnv/boot.cmd
  ${STAGING_KERNEL_DIR}/arch/arm64/boot/dts/rockchip/uEnv/<LUBANCAT_UENV_DIR>/<LUBANCAT_UENV>

需要改脚本行为时，优先改内核树（打补丁进 linux-rockchip 的 SRC_URI），
而不是在这里放一份覆盖副本。
