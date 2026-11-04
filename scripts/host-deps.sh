#!/usr/bin/env bash
# 主机依赖安装（Ubuntu 22.04 / 24.04、Debian 12）
#
# 用法：sudo ./scripts/host-deps.sh
#
# 设计要点：
#   - apt 段必须以 root 跑；pip 段**不能**以 root 跑（否则 kas 装进 /root/.local，
#     普通用户构建时看不到），所以用 $SUDO_USER 还原成原用户。
#   - 必需包缺失即失败；可选包（bmap-tools / u-boot-tools）失败只告警，不阻塞。
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "请用 sudo 运行：sudo $0" >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    echo "警告：SUDO_USER 为空（你在 root shell 里直接跑的？）。" >&2
    echo "      kas 需要装到**构建用户**名下，请改用：sudo -u <你的账号> ... 或手动 pip install --user kas" >&2
    TARGET_USER=""
fi

echo "==> [1/4] Yocto 必需依赖"
apt-get update
apt-get install -y --no-install-recommends \
    build-essential chrpath cpio debianutils diffstat file gawk gcc git \
    iputils-ping libacl1 liblz4-tool locales python3 python3-git python3-jinja2 \
    python3-pexpect python3-pip python3-subunit python3-venv socat texinfo unzip wget xz-utils zstd

# 注意：不要加 python3-wic —— Ubuntu 22.04/24.04 的 apt 源里没有这个包，
# 加了会让整条 apt-get install 失败（wic 由 poky 自带，不需要主机包）。

echo "==> [2/4] 可选：镜像处理与 wic 工具链（失败只告警）"
OPTIONAL_PKGS="parted gdisk dosfstools mtools e2fsprogs device-tree-compiler"
# shellcheck disable=SC2086
if ! apt-get install -y --no-install-recommends $OPTIONAL_PKGS; then
    echo "警告：可选包安装失败（$OPTIONAL_PKGS）。" >&2
    echo "      只影响 wic / 分区检查；boot-ext2.img 与 update.img 仍可正常生成。" >&2
fi

# u-boot-tools 提供 mkimage（extboot-image.bb 需要，缺了会回退到主机 /usr/bin/mkimage）
if ! apt-get install -y --no-install-recommends u-boot-tools bmap-tools; then
    echo "警告：u-boot-tools / bmap-tools 装不上。" >&2
    echo "      mkimage 缺失会导致 bitbake extboot-image 报「需要 mkimage」。" >&2
fi

echo "==> [3/4] kas（可选，推荐；只装到构建用户）"
if [ -n "$TARGET_USER" ]; then
    SUDO_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    if sudo -u "$TARGET_USER" env HOME="$SUDO_HOME" python3 -m pip install --user kas 2>/dev/null; then
        echo "    kas 已装到 $SUDO_HOME/.local/bin/kas"
        case ":$PATH:" in
            *":$SUDO_HOME/.local/bin:"*) ;;
            *) echo "    提示：把 $SUDO_HOME/.local/bin 加进 PATH（或直接用 python3 -m venv）" ;;
        esac
    else
        echo "    警告：pip 安装 kas 失败（PEP 668 或被墙）。建议改用 venv：" >&2
        echo "      python3 -m venv .kas && . .kas/bin/activate && pip install kas" >&2
    fi
else
    echo "    跳过（未识别到构建用户）。手动装：python3 -m venv .kas && . .kas/bin/activate && pip install kas"
fi

echo "==> [4/4] locale 与资源自检"
if ! locale -a | grep -qi '^en_US.utf8'; then
    locale-gen en_US.UTF-8
fi

echo
echo "---- 自检 ----"
printf 'locale  : '; locale 2>/dev/null | awk -F= '/^LANG=/{print $2}' | head -1
printf 'nofile  : '; ulimit -n
printf '磁盘    : '; df -h . | awk 'NR==2{print $4" 可用 ("$5" 已用) on "$6}'
printf 'CPU/内存: '; echo "$(nproc) 核 / $(awk '/MemTotal/{printf "%.0f", $2/1024/1024}' /proc/meminfo) GiB"

cat <<'EOF'

完成。还需要注意三件事：

1) 每个新 shell 都要（建议写进 ~/.bashrc）：
       export LANG=en_US.UTF-8
       ulimit -n 65536          # 64 核并发会撞 Too many open files

2) 首次全量构建建议剩余 >= 300 GB（downloads 35~60G + sstate 45~80G + tmp 60~120G）。
   工作区必须放本地 ext4/xfs（NTFS / 9p / 网络盘会慢 5~10 倍或直接报错）。

3) rkdeveloptool 不在 apt 源里，只在走 wic 烧写时才需要：
       git clone https://github.com/rockchip-linux/rkdeveloptool
       cd rkdeveloptool && autoreconf -i && ./configure && make -j"$(nproc)" && sudo make install
       # 若报 "Creating Comm Object failed"，装 udev 规则后重插 USB：
       # sudo cp 99-rk-rockusb.rules /etc/udev/rules.d/ && sudo udevadm control --reload
EOF
