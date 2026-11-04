# L0：能启动、能串口登录、能跑 shell 的最小镜像
# 出口判据：串口出现 login:，root 可登录（无密码，仅 bring-up 阶段），uname -a 见 6.1.99

require recipes-core/images/core-image-minimal.bb

inherit lubancat-image

IMAGE_INSTALL:append = " packagegroup-lubancat-base"

# bring-up 阶段打开：ssh-server-dropbear 轻量、debug-tweaks 允许 root 空密码。
# 一旦进入 L1/L2 或任何对外发布，务必去掉 debug-tweaks。
IMAGE_FEATURES:append = " ssh-server-dropbear debug-tweaks"
