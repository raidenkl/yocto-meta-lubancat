SUMMARY = "LubanCat network/debug extras: 抓包、远程调试、常用小工具"
LICENSE = "MIT"

inherit packagegroup

PACKAGE_ARCH = "${MACHINE_ARCH}"

# 包名都按实际层核实过，别再凭印象写：
#   - tftp-hpa：客户端在**主包**里，只有 server 被拆成 tftp-hpa-server，
#     写 tftp-hpa-client 会报 "Nothing RPROVIDES 'tftp-hpa-client'"
#   - nfs-utils：本套层（meta-networking scarthgap）里没有这个 recipe，
#     要 NFS 客户端得自己补 recipe
RDEPENDS:${PN} = " \
    tcpdump \
    tftp-hpa \
    curl \
    wget \
    openssh-sftp-server \
    procps \
    less \
    grep \
    diffutils \
"
