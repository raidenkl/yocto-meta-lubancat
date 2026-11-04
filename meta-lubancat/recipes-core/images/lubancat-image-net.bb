# L1：在 L0 基础上把网口打通（DHCP/静态 IP、抓包、诊断工具）
# 出口判据：ethtool 见 1000Mb/s Full，ping 网关通，ip -s link 收发计数增长

require recipes-core/images/core-image-minimal.bb

inherit lubancat-image

IMAGE_INSTALL:append = " \
    packagegroup-lubancat-base \
    packagegroup-lubancat-net \
"

IMAGE_FEATURES:append = " ssh-server-openssh"

# L1 起不再默认空密码；首次登录用串口设密码，或按需临时打开 debug-tweaks。
# IMAGE_FEATURES:append = " debug-tweaks"
