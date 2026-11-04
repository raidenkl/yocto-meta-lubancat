SUMMARY = "LubanCat 首次启动：把 rootfs 扩到分区大小"
DESCRIPTION = "parameter.txt 里 rootfs 是 -@0x48000(rootfs:grow)，afptool 刷写时已把分区拉到磁盘末尾，但 ext4 文件系统本身仍是镜像里的大小。这个 oneshot 服务在首次启动跑一次 resize2fs（ext4 支持在线扩容），完成后打标记不再执行。"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://lubancat-resize-rootfs.sh \
    file://lubancat-resize-rootfs.service \
    file://lubancat-board-detect.sh \
    file://lubancat-board-detect.service \
    file://board-table \
"

S = "${WORKDIR}"

inherit systemd

# 扩容服务永远装；切板服务由 LUBANCAT_FIRSTBOOT_SWITCH 控制（族镜像=1，板级别名也=1，
# 但脚本会 cmp 目标 dtb，内容一致就不重启，所以板级别名镜像不会白重启一次）。
LUBANCAT_FIRSTBOOT_SWITCH ?= "1"

SYSTEMD_SERVICE:${PN} = "lubancat-resize-rootfs.service ${@bb.utils.contains('LUBANCAT_FIRSTBOOT_SWITCH', '1', 'lubancat-board-detect.service', '', d)}"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# 只用 resize2fs；脚本刻意不依赖 lsblk/findmnt/parted —— 全部信息从 /proc/mounts
# 与 /sys/class/block 读，少一层包依赖，也不受 busybox 精简影响。
RDEPENDS:${PN} = "e2fsprogs-resize2fs"

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/lubancat-resize-rootfs.sh ${D}${sbindir}/lubancat-resize-rootfs

    install -m 0755 ${WORKDIR}/lubancat-board-detect.sh ${D}${sbindir}/lubancat-board-detect

    install -d ${D}${datadir}/lubancat
    install -m 0644 ${WORKDIR}/board-table ${D}${datadir}/lubancat/board-table

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/lubancat-resize-rootfs.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${WORKDIR}/lubancat-board-detect.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} += " \
    ${systemd_system_unitdir}/lubancat-resize-rootfs.service \
    ${systemd_system_unitdir}/lubancat-board-detect.service \
    ${datadir}/lubancat/board-table \
"
