#!/usr/bin/env bash
# 拉取全部依赖层到当前目录，并打印每个层的实际提交（用于写进版本矩阵）
#
# 用法：
#   ./scripts/fetch-layers.sh                 # 默认拉 scarthgap
#   BRANCH=scarthgap ./scripts/fetch-layers.sh
#
# 拉完以后：
#   source poky/oe-init-build-env build
#   bitbake-layers add-layer ../meta-arm/meta-arm ../meta-rockchip ../meta-lubancat
set -euo pipefail

BRANCH="${BRANCH:-scarthgap}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

POKY_URL="${POKY_URL:-https://git.yoctoproject.org/poky}"
ARM_URL="${ARM_URL:-https://git.yoctoproject.org/meta-arm}"
OE_URL="${OE_URL:-https://github.com/openembedded/meta-openembedded.git}"
RK_URL="${RK_URL:-https://github.com/JeffyCN/meta-rockchip.git}"

clone() {
    local url="$1" dir="$2" branch="$3"
    if [ -d "$dir/.git" ]; then
        echo "==> $dir 已存在，跳过"
        return
    fi
    echo "==> 拉取 $dir ($branch)"
    git clone --branch "$branch" --depth 1 "$url" "$dir"
}

clone "$POKY_URL" poky               "$BRANCH"
clone "$ARM_URL"  meta-arm           "$BRANCH"
clone "$OE_URL"   meta-openembedded  "$BRANCH"
clone "$RK_URL"   meta-rockchip      "$BRANCH"

# 被上层引用的三个 BSP 仓库，顺手记录远端 HEAD，用于填版本矩阵
echo
echo "==> 版本矩阵（请原样抄进手册/commit message）"
for d in poky meta-arm meta-openembedded meta-rockchip; do
    printf '%-22s %s\n' "$d" "$(git -C "$d" rev-parse HEAD)"
done

echo
echo "==> 上游 BSP 源（不由本脚本拉取，构建时由 bitbake 取）"
for r in LubanCat/u-boot LubanCat/rkbin LubanCat/kernel; do
    printf '%-22s ' "$r"
    git ls-remote "https://github.com/$r.git" HEAD 2>/dev/null | awk '{print $1}' || echo "(需要网络)"
done
