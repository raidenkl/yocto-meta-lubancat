SUMMARY = "LubanCat 默认网络配置（systemd-networkd）：有线 DHCP + 无线 DHCP/wpa_supplicant"
DESCRIPTION = "装上就有可用的网口。有线由 networkd 直接 DHCP；无线额外做三件事：\
用 .link 把网口钉回 wlan0、用 .network 让 networkd 做 DHCP（metric 100，比有线大，\
有线优先、拔线自动切 wifi）、启用 wpa_supplicant@wlan0 并提供一个用户可编辑的凭据文件。\
无线**不要**再用 busybox udhcpc：它的脚本 metric 写死 10，与有线的 RouteMetric 撞车，\
默认路由会被内核拒掉（RTNETLINK answers: File exists），表现是'连上 wifi 却上不了网'。"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://20-wired.network \
    file://10-lubancat-wlan.link \
    file://50-lubancat-wlan.network \
    file://wpa_supplicant-wlan0.conf \
    file://90-lubancat-net.preset \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/systemd/network
    install -m 0644 ${WORKDIR}/20-wired.network ${D}${sysconfdir}/systemd/network/
    install -m 0644 ${WORKDIR}/10-lubancat-wlan.link ${D}${sysconfdir}/systemd/network/
    install -m 0644 ${WORKDIR}/50-lubancat-wlan.network ${D}${sysconfdir}/systemd/network/

    install -d ${D}${sysconfdir}/wpa_supplicant
    # 凭据文件 0600；落在 /etc 下 → 进 CONFFILES，升级镜像不会冲掉用户填的 SSID
    install -m 0600 ${WORKDIR}/wpa_supplicant-wlan0.conf ${D}${sysconfdir}/wpa_supplicant/

    # 启用 wpa_supplicant@wlan0.service。单元文件属于 wpa-supplicant 包，不在本配方的
    # ${D} 里，所以不能靠 SYSTEMD_SERVICE 自动 enable（systemctl --root 找不到模板会报
    # "Unit does not exist"）。直接建 wants 链接，指向**模板**而非实例文件 —— 这正是
    # systemctl enable 对实例化单元的做法。
    install -d ${D}${sysconfdir}/systemd/system/multi-user.target.wants
    ln -sf /usr/lib/systemd/system/wpa_supplicant@.service \
        ${D}${sysconfdir}/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service

    install -d ${D}${sysconfdir}/systemd/system-preset
    install -m 0644 ${WORKDIR}/90-lubancat-net.preset ${D}${sysconfdir}/systemd/system-preset/
}

FILES:${PN} = " \
    ${sysconfdir}/systemd/network \
    ${sysconfdir}/systemd/system-preset \
    ${sysconfdir}/wpa_supplicant \
    ${sysconfdir}/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service \
"

CONFFILES:${PN} = " \
    ${sysconfdir}/systemd/network/20-wired.network \
    ${sysconfdir}/systemd/network/10-lubancat-wlan.link \
    ${sysconfdir}/systemd/network/50-lubancat-wlan.network \
    ${sysconfdir}/wpa_supplicant/wpa_supplicant-wlan0.conf \
"

# scarthgap 的 systemd 不拆 systemd-networkd 包，networkd 随 systemd 主包提供。
# wpa-supplicant 提供 wpa_supplicant@.service 模板与 /usr/sbin/wpa_supplicant。
RDEPENDS:${PN} = "systemd wpa-supplicant"
