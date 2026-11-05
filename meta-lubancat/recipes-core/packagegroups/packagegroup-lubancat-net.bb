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

# ---- 无线网卡 ----
# 芯片：RTL8188CE / RTL8822CE / RTL8851BE / RTL8852BE，全部 PCIe（M.2 卡），
# 走内核主线驱动；vendor 树的 8189fs / 8821cu 是给 SDIO / USB 模组的板子用的。
#
# 包名怎么来的（这里踩过坑，写清楚）：
#   1. 取实际 .ko 的 basename，不是驱动目录名 —— rtl8852be/ 编出来是 8852be.ko；
#   2. kernel-module-split 会把 basename 里的 **下划线换成短横线**：
#        rtw88_8822ce.ko  →  kernel-module-rtw88-8822ce
#      写成 kernel-module-rtw88_8822ce 的结果是 rootfs 阶段报
#        nothing provides kernel-module-rtw88_8822ce needed by packagegroup-lubancat-net
#      而模块本身其实编得好好的，很容易误判成"驱动没编出来"。
#   3. 模块之间的依赖（rtw88-8822c / rtw88-pci / kernel）由 kernel-module-split
#      按 modinfo 自动写进 RDEPENDS，这里只列最上层的驱动即可。
#
# 这四颗是现场在测的卡，cfg 里默认 =m，所以用 RDEPENDS：模块一定会被编出来，
# 缺了就在 rootfs 阶段明确失败，比装不上却不报错好排查。
# 哪天把某个驱动改回 =n，记得同步删掉这里对应那行。
RDEPENDS:${PN} += " \
    kernel-module-rtl8188ee \
    kernel-module-rtw88-8822ce \
    kernel-module-rtw89-8851be \
    kernel-module-rtw89-8852be \
"

# vendor 树的 SDIO / USB 驱动是给别的板子（8189FS / 8821CU 模组）用的，本机大概率没有，
# 用 RRECOMMENDS：装不上不算错。
RRECOMMENDS:${PN} += " \
    kernel-module-8189fs \
    kernel-module-8821cu \
"

# 固件缺了不会有编译错误，只会在 dmesg 里看到
#   rtw89_8852be ...: Direct firmware load for rtw89/rtw8852b_fw-1.bin failed
# 然后网卡起不来。三个包分别对应：
#   linux-firmware-rtl8188 → rtlwifi/rtl8188efw.bin
#   linux-firmware-rtl8822 → rtw88/rtw8822c_fw.bin
#   linux-firmware-rtw89  → rtw89/rtw8852b_fw-1.bin（本层 linux-firmware bbappend 切出来的）
RDEPENDS:${PN} += " \
    linux-firmware-rtl8188 \
    linux-firmware-rtl8822 \
    linux-firmware-rtw89 \
"

# ---- 无线工具链 ----
# 光有驱动和固件，板上只能看到 /sys 里有张卡、ip link 里有个 DOWN 的接口，
# 扫不了 SSID、也连不上网。这几个是"能真正用起来"的最小集：
#
#   pciutils             → lspci。本镜像原先没装，连"卡有没有枚举出来"都看不到，
#                          只能绕 /sys/bus/pci/devices 手读。（要 pci.ids 才有 -nn 的
#                          名字，pciutils 自己 RDEPENDS 了 pciutils-ids，不用单列）
#   iw                   → 扫 SSID / 看速率 / 看信道。不要装 wireless-tools：
#                          iwconfig 那套接口在 cfg80211 驱动上基本不可用，且已停止维护
#   wpa-supplicant       → WPA/WPA2/WPA3 连接，wpa_cli / wpa_passphrase 在子包里，按需再加
#   wireless-regdb-static → regulatory.db。注意是 -static 子包（主包只放 crda 的旧格式），
#                          没有它内核只能用 world 域，5GHz 信道大量不可用
#   lubancat-netconfig   → 把 wlan0 接入 systemd-networkd（.network + DHCP + 路由 metric），
#                          并启用 wpa_supplicant@wlan0 与 /etc/wpa_supplicant/wpa_supplicant-wlan0.conf。
#                          不要再用 udhcpc 手工配 wlan0：它的脚本 metric 写死 10，与有线的
#                          RouteMetric=10 撞车，默认路由会被内核拒掉（File exists）。
RDEPENDS:${PN} += " \
    pciutils \
    iw \
    wpa-supplicant \
    wireless-regdb-static \
    lubancat-netconfig \
"
