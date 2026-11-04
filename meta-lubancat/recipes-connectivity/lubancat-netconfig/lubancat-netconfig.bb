SUMMARY = "LubanCat 默认有线网络配置（systemd-networkd）"
DESCRIPTION = "装上就有一块可用的 DHCP 网口。GMAC1(fe1c0000) + RTL8211F 在 6.1 内核里 \
通常枚举为 eth0，但以 ethtool / ip link 的实查结果为准。"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://20-wired.network \
    file://90-lubancat-net.preset \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/systemd/network
    install -m 0644 ${WORKDIR}/20-wired.network ${D}${sysconfdir}/systemd/network/

    install -d ${D}${sysconfdir}/systemd/system-preset
    install -m 0644 ${WORKDIR}/90-lubancat-net.preset ${D}${sysconfdir}/systemd/system-preset/
}

FILES:${PN} = " \
    ${sysconfdir}/systemd/network \
    ${sysconfdir}/systemd/system-preset \
"

# scarthgap 的 systemd 不拆 systemd-networkd 包，networkd 随 systemd 主包提供
RDEPENDS:${PN} = "systemd"
