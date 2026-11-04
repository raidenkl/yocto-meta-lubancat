# LubanCat 镜像公共基类
#
# 职责只有三件，刻意不做别的：
#   1) 统一 IMAGE_FSTYPES（板级 conf 里也可覆盖）
#   2) 给 do_image_wic 补依赖，避免 wic 抢在 u-boot / kernel 的 do_deploy 之前跑，
#      报 "no such file: idblock.img / uboot.img / boot.img"
#   3) 生成一个 latest 软链，方便脚本和 CI 引用产物

IMAGE_FSTYPES ?= "wic.gz ext4 tar"

do_image_wic[depends] += "virtual/bootloader:do_deploy"
do_image_wic[depends] += "virtual/kernel:do_deploy"

IMAGE_POSTPROCESS_COMMAND:append = " lubancat_link_latest;"

lubancat_link_latest() {
    install -d "${TOPDIR}/latest"
    ln -rsf "${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.wic.gz" "${TOPDIR}/latest/${IMAGE_BASENAME}.wic.gz" 2>/dev/null || true
    ln -rsf "${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.wic"    "${TOPDIR}/latest/${IMAGE_BASENAME}.wic"    2>/dev/null || true
    ln -rsf "${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.ext4"   "${TOPDIR}/latest/${IMAGE_BASENAME}.ext4"   2>/dev/null || true
}

# 注意：不要在这个 class 里写 IMAGE_INSTALL。那会让所有镜像被迫背同一份包，
# 分级镜像就失去意义了（见 recipes-core/images 下三个 image recipe）。
