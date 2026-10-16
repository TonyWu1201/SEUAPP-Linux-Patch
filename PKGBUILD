# 企业微信 (wwlocal) — Arch Linux 打包脚本
# 从原始 deb 直接构建：将原始 deb 与补丁脚本放在同一目录，
#   makepkg -f
#
# 目录中需要存在:
#   weworklocal_2.6.290000.49_1648784689.deb   (原始安装包, 与 deb 版补丁工程相同)
#   clear_execstack.py patch_wwlocal.py patch_curl_strdup.py patch_saas_free.py
#   compat.c wwlocal-launcher.sh wwlocal.install
#
# 产物与 pack_arch.sh 的"重打包"路径等价；两者选一即可。
pkgname=wwlocal
pkgver=2.6.290000.4
pkgrel=1
pkgdesc="企业微信 (weworklocal) 桌面客户端 —— glibc 兼容修补版"
arch=('x86_64')
url="https://work.weixin.qq.com/"
license=('custom:ISC')
depends=(
    gtk3 glib2 pango cairo gdk-pixbuf2 at-spi2-core nss
    libx11 libxcb libxcomposite libxcursor libxdamage libxext libxfixes
    libxi libxrender libxrandr libxtst libxss
    alsa-lib libcups dbus expat xdg-utils
)
optdepends=(
    'libayatana-appindicator: 系统托盘图标（若 Electron 8 未识别，可试 AUR 的 libappindicator-gtk3）'
    'libsecret: 凭据（密码）存储'
    'libnotify: 桌面通知'
    'mesa: OpenGL 硬件加速'
    'noto-fonts-cjk: 中文字体（系统未安装中文字体时）'
)
makedepends=('python' 'gcc')
install=wwlocal.install
# 本地文件源：文件已在本目录时 makepkg 不下载
source=(
    'weworklocal_2.6.290000.49_1648784689.deb'
    'clear_execstack.py'
    'patch_wwlocal.py'
    'patch_curl_strdup.py'
    'patch_saas_free.py'
    'compat.c'
    'wwlocal-launcher.sh'
    'wwlocal.install'
)
sha256sums=('SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP')
options=('!strip' '!debug')

build() {
    cd "$srcdir"

    # 解包原始 deb（ar + bsdtar，均为 base/base-devel 自带）
    rm -rf root
    ar x weworklocal_2.6.290000.49_1648784689.deb
    mkdir -p root
    bsdtar -xf data.tar.* -C root

    local app='root/opt/企业微信'
    [ -x "$app/wwlocal" ] || { error 'deb 载荷异常：找不到 wwlocal'; return 1; }

    # bsdtar 以普通用户解包时会剥离 setuid 位，这里显式恢复
    # （Electron 沙箱需要 chrome-sandbox 为 4755 root:root）
    chmod 4755 "$app/chrome-sandbox"

    # 与 rebuild.sh 相同的定点修补
    python3 "$srcdir/clear_execstack.py"       "$app/libwework_sdk.so"
    python3 "$srcdir/patch_wwlocal.py"         "$app/wwlocal"
    python3 "$srcdir/patch_curl_strdup.py"     "$app/libcurl.so.4"
    python3 "$srcdir/patch_curl_strdup.py"     "$app/libcurl.so.4.3.0"
    python3 "$srcdir/patch_saas_free.py"       "$app/libwework_saas_lib.so"

    # 退出保护 + wtrdup/wtrndup 兼容库、启动器
    gcc -shared -fPIC -O2 -o "$app/libwwlocal_compat.so" "$srcdir/compat.c" -ldl
    install -m 755 "$srcdir/wwlocal-launcher.sh" "$app/wwlocal-launcher.sh"

    # desktop 入口指向启动器（缺 preload 直接运行 wwlocal 会在退出时崩溃）
    sed -i 's|Exec="/opt/企业微信/wwlocal" %U|Exec="/opt/企业微信/wwlocal-launcher.sh" %U|' \
        root/usr/share/applications/wwlocal.desktop
}

package() {
    cd "$srcdir/root"
    cp -a opt usr "$pkgdir/"
}
