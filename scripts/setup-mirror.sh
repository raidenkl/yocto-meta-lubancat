#!/bin/bash
# 在 source oe-init-build-env 之后、bitbake 之前 source 本文件。
# 作用：让 git 访问 GitHub 时自动走 gh-proxy 前缀（实测 4.3 MB/s，直连 30 KB/s）。
#
# 只影响当前 shell 的 git 子进程，不写 ~/.gitconfig，所以不会影响你自己的
# git push / 其他仓库。
#
# 用法（在仓库根，source 之后可以继续 kas / bitbake）：
#   source ./scripts/setup-mirror.sh
#   kas build kas/lubancat.yml
# 或：
#   source ./scripts/setup-mirror.sh && bitbake lubancat-image-minimal

export LANG=en_US.UTF-8
ulimit -n 65536 2>/dev/null

# git >= 2.31 支持 GIT_CONFIG_COUNT 方式注入配置（这台机器 2.34，可用）
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="url.https://gh-proxy.com/https://github.com/.insteadOf"
export GIT_CONFIG_VALUE_0="https://github.com/"

echo "[mirror] github -> https://gh-proxy.com  (git only)"
echo "[mirror] LANG=$LANG  nofile=$(ulimit -n)"

# 自检（可选，比较慢，注释掉即可）
# git ls-remote https://github.com/LubanCat/u-boot.git refs/heads/main
