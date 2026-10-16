#!/bin/bash
# 企业微信 (wwlocal) —— 将修补后的 deb 重新打包为 RPM（Fedora / RHEL / openSUSE 等）
#
# 用法: ./pack_rpm.sh <已修补的deb> [输出.rpm]
#   e.g. ./pack_rpm.sh ~/weworklocal_2.6.290000.49_1648784689.patched4.deb
#
# 说明:
#   - 在 Debian/Ubuntu 构建机上做"重打包"，产物供 RPM 系发行版安装:
#       sudo dnf install ./wwlocal-2.6.290000.4-1.x86_64.rpm
#   - rpmbuild 来源: 优先系统已安装的 rpm 包；否则先运行 ./setup_build_tools.sh
#     准备无 root 工具链（.buildtools/）。
#   - 非 root 构建需要 fakeroot（把包内文件属主固定为 root:root）。
#   - 包内容与修补后的 deb 完全一致（字节级），仅封装格式与安装脚本适配 RPM。
set -euo pipefail

DEB="${1:?用法: ./pack_rpm.sh <patched.deb> [输出.rpm]}"
[ -f "$DEB" ] || { echo "错误: 找不到 $DEB" >&2; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"

VERSION="2.6.290000.4"
RELEASE="1"
OUT="${2:-$HERE/wwlocal-$VERSION-$RELEASE.x86_64.rpm}"
APPDIR='opt/企业微信'

export LANG=C.UTF-8 LC_ALL=C.UTF-8
umask 022

WORK="$(mktemp -d /tmp/wwpatch-rpm.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

TOOLS="$HERE/.buildtools/root"

# ---- 0. 工具链 ----------------------------------------------------------
if command -v rpmbuild >/dev/null 2>&1; then
    RPMBUILD="$(command -v rpmbuild)"
    echo "[0/4] 使用系统 rpmbuild: $RPMBUILD"
elif [ -x "$TOOLS/usr/bin/rpmbuild" ]; then
    RPMBUILD="$TOOLS/usr/bin/rpmbuild"
    export LD_LIBRARY_PATH="$TOOLS/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export RPM_CONFIGDIR="$TOOLS/usr/lib/rpm"
    export PATH="$TOOLS/usr/bin:$PATH"
    echo "[0/4] 使用本地工具链: $RPMBUILD"
else
    echo "错误: 未找到 rpmbuild。" >&2
    echo "  可选其一: sudo apt install rpm    或    ./setup_build_tools.sh" >&2
    exit 1
fi

FAKEROOT=()
if [ "$(id -u)" != 0 ]; then
    command -v fakeroot >/dev/null 2>&1 || {
        echo "错误: 非 root 构建需要 fakeroot（sudo apt install fakeroot / dnf install fakeroot）" >&2
        exit 1
    }
    FAKEROOT=(fakeroot -u)
fi

extract_deb() { # $1=deb  $2=目标目录
    if command -v dpkg-deb >/dev/null 2>&1; then
        dpkg-deb -x "$1" "$2"
        return
    fi
    # 无 dpkg 时用 ar+tar（binutils/tar 各发行版均自带）
    local t
    t="$(mktemp -d)"
    (cd "$t" && ar x "$1")
    tar -xf "$t"/data.tar.* -C "$2"
    rm -rf "$t"
}

# ---- 1. 解包载荷 --------------------------------------------------------
echo "[1/4] 解包载荷: $DEB"
PAYLOAD="$WORK/payload"
mkdir -p "$PAYLOAD"
extract_deb "$DEB" "$PAYLOAD"
[ -x "$PAYLOAD/$APPDIR/wwlocal" ] || { echo "错误: 载荷中找不到 $APPDIR/wwlocal（不是企业微信包？）" >&2; exit 1; }
# 防御性恢复 setuid：dpkg-deb 会保留，但 ar+tar 回退路径可能剥离
[ -f "$PAYLOAD/$APPDIR/chrome-sandbox" ] && chmod 4755 "$PAYLOAD/$APPDIR/chrome-sandbox"
[ -u "$PAYLOAD/$APPDIR/chrome-sandbox" ] || echo "警告: chrome-sandbox 缺少 setuid 位" >&2

# ---- 2. 生成依赖（soname 形式的 Requires，跨发行版通用）-----------------
echo "[2/4] 生成依赖列表（按 ELF NEEDED）"
NEEDED="$(readelf -d "$PAYLOAD/$APPDIR/wwlocal" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')"
REQ=""
for lib in $NEEDED; do
    case "$lib" in
        # glibc 家族由 Requires: glibc 覆盖
        libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|ld-linux-x86-64.so.2|ld-linux.so.2)
            continue ;;
    esac
    # 应用自带的库（同目录内存在则跳过）
    [ -e "$PAYLOAD/$APPDIR/$lib" ] && continue
    REQ+="Requires:       ${lib}()(64bit)"$'\n'
done

# ---- 3. 生成 spec -------------------------------------------------------
echo "[3/4] 生成 spec"
RPMB="$WORK/rpmbuild"
mkdir -p "$RPMB"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
SPEC="$RPMB/SPECS/wwlocal.spec"

cat >"$SPEC" <<'SPEC_EOF'
%global debug_package %{nil}
%global __os_install_post %{nil}

Name:           wwlocal
Version:        @VERSION@
Release:        @RELEASE@
Summary:        企业微信 (weworklocal) 桌面客户端 —— glibc 兼容修补重打包版
License:        ISC
Vendor:         work_weixin <work_weixin@tencent.com>
URL:            https://work.weixin.qq.com/
BuildArch:      x86_64
AutoReqProv:    no

Requires:       glibc
Requires:       xdg-utils
@EXTRA_REQUIRES@
Recommends:     (libappindicator3.so.1()(64bit) or libayatana-appindicator3.so.1()(64bit))
Recommends:     libnotify.so.4()(64bit)
Recommends:     libsecret-1.so.0()(64bit)
Recommends:     libuuid.so.1()(64bit)
Recommends:     libGL.so.1()(64bit)
Recommends:     libgbm.so.1()(64bit)

%description
企业微信 Linux 官方 deb 包（weworklocal 2.6.290000.49）在 Debian/Ubuntu
上新版 glibc（>= 2.41）下无法正常运行的定点修补版，重新封装为 RPM。

修复内容（详见 README.md）:
  * 清除 libwework_sdk.so 的可执行栈标志（execstack）
  * 修复 wwlocal 主程序中的坏指令（缺 %%fs 段前缀）
  * 修复退出应用、输入组织机构域、进入主界面三处跨分配器释放崩溃

包内文件与修补后的 deb 完全一致；安装后菜单启动"企业微信"，
命令行入口: /opt/企业微信/wwlocal-launcher.sh

%install
mkdir -p %{buildroot}
cp -a %{payload_dir}/. %{buildroot}/
chown -R root:root %{buildroot}

%files
"/opt/企业微信"
/usr/share/applications/wwlocal.desktop
/usr/share/doc/wwlocal
/usr/share/icons/hicolor/16x16/apps/wwlocal.png
/usr/share/icons/hicolor/32x32/apps/wwlocal.png
/usr/share/icons/hicolor/512x512/apps/wwlocal.png

%post
{
  if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database -q /usr/share/applications || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
      gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
  fi
  if command -v restorecon >/dev/null 2>&1; then
      restorecon -R "/opt/企业微信" || true
  fi
  # 与 deb 版 postinst 行为一致: 当前用户桌面目录存在时放置快捷方式
  u="${SUDO_USER:-}"
  if [ -n "$u" ] && [ "$u" != root ]; then
      h="$(getent passwd "$u" 2>/dev/null | cut -d: -f6)"
      if [ -n "$h" ]; then
          for d in "$h/Desktop" "$h/桌面"; do
              if [ -d "$d" ]; then
                  cp -f /usr/share/applications/wwlocal.desktop "$d/" 2>/dev/null || true
                  chown "$u" "$d/wwlocal.desktop" 2>/dev/null || true
              fi
          done
      fi
  fi
} >/dev/null 2>&1
exit 0

%postun
{
  if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database -q /usr/share/applications || true
  fi
} >/dev/null 2>&1
exit 0
SPEC_EOF

sed -i -e "s/@VERSION@/$VERSION/" -e "s/@RELEASE@/$RELEASE/" "$SPEC"
awk -v req="$REQ" '{ if ($0 == "@EXTRA_REQUIRES@") printf "%s", req; else print }' "$SPEC" >"$SPEC.new"
mv "$SPEC.new" "$SPEC"

# ---- 4. 构建 ------------------------------------------------------------
echo "[4/4] rpmbuild -bb（约 1~3 分钟）"
LOG="$WORK/rpmbuild.log"
if ! "${FAKEROOT[@]}" "$RPMBUILD" -bb \
        --define "_topdir $RPMB" \
        --define "_dbpath $RPMB/db" \
        --define "payload_dir $PAYLOAD" \
        "$SPEC" >"$LOG" 2>&1; then
    echo "rpmbuild 失败，日志尾部:" >&2
    tail -30 "$LOG" >&2
    exit 1
fi

RPMFILE="$(ls "$RPMB"/RPMS/x86_64/wwlocal-*.rpm)"
cp -f "$RPMFILE" "$OUT"
echo
echo "完成: $OUT ($(du -h "$OUT" | cut -f1))"
echo "安装: sudo dnf install '$OUT'   (openSUSE: sudo zypper install --allow-unsigned-rpm '$OUT')"
