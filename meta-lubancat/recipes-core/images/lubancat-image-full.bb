# L2：带 GPU / Wayland 的完整镜像
# 出口判据：weston 起得来（systemctl status weston），kmscube 出画面，glmark2 出分
#
# 前置要求（缺一个就编不过或起不来）：
#   1) local.conf 里 DISTRO_FEATURES:append = " pam"
#      —— weston 的 required-distro-features.inc 在 systemd 下强制要求 pam，
#         不加会报 "Nothing RPROVIDES 'weston-xwayland'"（weston 被 skip）
#   2) meta-rockchip 的 mali.inc 已配好：
#      PREFERRED_PROVIDER_virtual/{egl,gles1,gles2,gles3,gbm,opencl} = rockchip-libmali
#   3) 闭源 blob 的 license 需要放行（见 local.conf 的 LICENSE_FLAGS_ACCEPTED）

require recipes-graphics/images/core-image-weston.bb

inherit lubancat-image

IMAGE_INSTALL:append = " \
    packagegroup-lubancat-base \
    packagegroup-lubancat-net \
    rockchip-libmali \
    rockchip-librga \
    rockchip-npu \
    kmscube \
"

# glmark2 在 meta-oe/recipes-benchmark/glmark2，默认是 x11 口味；要在 weston 里跑 es2
# 需要 wayland + gles2，得再加一个 bbappend：
#   recipes-graphics/glmark2/glmark2_%.bbappend
#     PACKAGECONFIG:append = " wayland gles2"
# 确认能编过再取消注释。
# IMAGE_INSTALL:append = " glmark2"

IMAGE_FEATURES:append = " ssh-server-openssh hwcodecs"

# weston 起不来时，串口上直接手起一个看日志：
#   systemctl stop weston
#   weston --tty=1 --backend=drm-backend.so --log=/tmp/weston.log
