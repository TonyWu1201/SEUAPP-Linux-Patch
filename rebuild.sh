#!/bin/bash
# 企业微信 (wwlocal) 补丁包重建脚本
# 用法: ./rebuild.sh <原始deb> <输出deb>
set -euo pipefail

ORIG="${1:?用法: ./rebuild.sh <原始deb> <输出deb>}"
OUT="${2:?用法: ./rebuild.sh <原始deb> <输出deb>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
APPDIR='opt/企业微信'

WORK="$(mktemp -d /tmp/wwpatch.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "[1/8] 解包 $ORIG"
dpkg-deb -R "$ORIG" "$WORK"

echo "[2/8] 清除 libwework_sdk.so 的 execstack 标志"
python3 "$HERE/clear_execstack.py" "$WORK/$APPDIR/libwework_sdk.so"

echo "[3/8] 修复 wwlocal 坏指令"
python3 "$HERE/patch_wwlocal.py" "$WORK/$APPDIR/wwlocal"

echo "[4/8] 改 libcurl 的 strdup/strndup 导入 (修组织机构域闪退)"
python3 "$HERE/patch_curl_strdup.py" "$WORK/$APPDIR/libcurl.so.4"
python3 "$HERE/patch_curl_strdup.py" "$WORK/$APPDIR/libcurl.so.4.3.0"

echo "[5/8] 修 libwework_saas_lib.so 的 new[]+free 混用 (修进入主界面后闪退)"
python3 "$HERE/patch_saas_free.py" "$WORK/$APPDIR/libwework_saas_lib.so"

echo "[6/8] 编译并加入 compat 库与启动器"
gcc -shared -fPIC -O2 -o "$WORK/$APPDIR/libwwlocal_compat.so" \
    "$HERE/compat.c" -ldl
cp "$HERE/wwlocal-launcher.sh" "$WORK/$APPDIR/wwlocal-launcher.sh"
chmod 644 "$WORK/$APPDIR/libwwlocal_compat.so"
chmod 755 "$WORK/$APPDIR/wwlocal-launcher.sh"

echo "[7/8] 更新版本号 / desktop 入口 / postinst / md5sums"
sed -i 's/^Version: .*/Version: 2.6.290000.4/' "$WORK/DEBIAN/control"
sed -i 's|Exec="/opt/企业微信/wwlocal" %U|Exec="/opt/企业微信/wwlocal-launcher.sh" %U|' \
    "$WORK/usr/share/applications/wwlocal.desktop"
sed -i 's|wwlocal\\" %U|wwlocal-launcher.sh\\" %U|' "$WORK/DEBIAN/postinst"
(
  cd "$WORK"
  find . -type f ! -path './DEBIAN/*' | sed 's|^\./||' | sort | xargs md5sum > DEBIAN/md5sums
)

echo "[8/8] 重新打包 -> $OUT"
dpkg-deb --root-owner-group -Zxz -b "$WORK" "$OUT"
echo "完成: $OUT"
