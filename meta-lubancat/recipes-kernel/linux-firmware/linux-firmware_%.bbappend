# linux-firmware 20240909 把 Realtek 的固件拆成 -rtl8188 / -rtl8822 / -rtl8723 …
# 一堆子包，但没有 rtw89（8851BE / 8852BE 用的那批）。
#
# 没被任何子包认领的文件会落到主包 linux-firmware 里，因为 recipe 末尾有
#     FILES:${PN} += "${nonarch_base_libdir}/firmware/*"
# 装主包等于把整棵固件树（几百 MB）塞进 rootfs，所以这里补一个子包把它切出来。

PACKAGE_BEFORE_PN += "${PN}-rtw89"

# rtw89 的固件同样适用 Realtek 的 LICENCE.rtlwifi_firmware.txt，
# 和 -rtl8822（rtw88）一致；-rtl-license 包里放的正是这个文件。
LICENSE:${PN}-rtw89 = "Firmware-rtlwifi_firmware"

# 只放现场用到的两颗（8851BE / 8852BE），别把整个 rtw89 目录都收进来：
# rtw89/ 下还有 8852A/8852C/8922A 的固件，加起来十几 MB，用不上的没必要进 rootfs。
#   rtw8851b_fw.bin      ← 8851B 的 FORMAT_MAX 是 0，没后缀
#   rtw8852b_fw-1.bin    ← 8852B 的 FORMAT_MAX 是 1，6.1 的驱动就要带 -1 的那份
#   rtw8852b_fw.bin      ← 老格式，一起留着，换固件版本时不用回来改配方
FILES:${PN}-rtw89 = " \
    ${nonarch_base_libdir}/firmware/rtw89/rtw8851b_fw*.bin \
    ${nonarch_base_libdir}/firmware/rtw89/rtw8852b_fw*.bin \
"

RDEPENDS:${PN}-rtw89 += "${PN}-rtl-license"
