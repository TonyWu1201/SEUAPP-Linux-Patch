#!/bin/bash
# 在 Debian/Ubuntu 上无 root 权限准备打包工具链
#
# 下载 rpm/rpmbuild、bsdtar（libarchive-tools）、pacman 及其依赖的 .deb，
# 解包到本目录 .buildtools/root 下。pack_rpm.sh / pack_arch.sh 会自动使用。
#
# 用法: ./setup_build_tools.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$HERE/.buildtools"
DL="$TOOLS/dl"
ROOT="$TOOLS/root"

mkdir -p "$DL" "$ROOT"

# rpmbuild 工具链 + bsdtar + pacman（pacman 仅用于校验生成的 Arch 包）
PKGS=(
    rpm rpm-common rpm2cpio
    librpm10 librpmio10 librpmbuild10 librpmsign10
    librpm-sequoia-1 libpopt0 libelf1t64 libfsverity0
    libarchive-tools
    pacman-package-manager
    libalpm16
)

echo "[1/2] apt-get download 工具包（无需 root）"
cd "$DL"
for p in "${PKGS[@]}"; do
    # 已下载过则跳过
    if ls "${p}"_*.deb >/dev/null 2>&1; then
        printf '  = %s (已存在)\n' "$p"
        continue
    fi
    if apt-get download "$p" 2>/dev/null; then
        printf '  + %s\n' "$p"
    else
        printf '  ! 跳过 %s（下载失败，可能本机为其他发行版）\n' "$p" >&2
    fi
done

echo "[2/2] 解包到 $ROOT"
for d in "$DL"/*.deb; do
    dpkg-deb -x "$d" "$ROOT"
done

echo
LD_LIBRARY_PATH="$ROOT/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
RPM_CONFIGDIR="$ROOT/usr/lib/rpm" \
    "$ROOT/usr/bin/rpmbuild" --version
echo "完成: $ROOT"
echo "提示: 若系统本身已装 rpm 包（sudo apt install rpm），pack_rpm.sh 会优先使用系统 rpmbuild。"
