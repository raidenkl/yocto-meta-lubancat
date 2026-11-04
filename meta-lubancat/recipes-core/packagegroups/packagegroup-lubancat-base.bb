SUMMARY = "LubanCat base runtime: 能登录、能挂载、能看设备"
DESCRIPTION = "最小可用集合。刻意只放 bring-up 与现场排查必需的包，图形/NPU 见 \
packagegroup-lubancat-net 与 L2 镜像。"
LICENSE = "MIT"

# 注意：不要 RDEPENDS 到 systemd-networkd / systemd-resolved。
# scarthgap(5.0) 的 systemd 255 并不拆这两个包（networkd/resolved 的二进制与 unit
# 都在 systemd 主包里，只受 PACKAGECONFIG[networkd]/[resolved] 控制）。
# 写 systemd-networkd 会直接报 "Nothing RPROVIDES 'systemd-networkd'"。
inherit packagegroup

PACKAGE_ARCH = "${MACHINE_ARCH}"

RDEPENDS:${PN} = " \
    ${@bb.utils.contains('DISTRO_FEATURES','systemd','systemd','',d)} \
    ethtool \
    iproute2 \
    iputils \
    i2c-tools \
    e2fsprogs-mke2fs \
    e2fsprogs-resize2fs \
    dosfstools \
    util-linux-mount \
    util-linux-blkid \
    lubancat-firstboot \
"
