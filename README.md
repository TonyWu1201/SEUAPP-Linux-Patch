# 企业微信 (weworklocal) Linux 兼容补丁 —— 下载 / 打补丁 / 安装

东南大学应用门户（app.seu.edu.cn）发布的 Linux 版企业微信（`weworklocal`，
2022 年构建，Electron 8.5.5 / Chrome 80）在新版发行版上无法正常运行：
新版 glibc（≥ 2.41，如 Ubuntu 24.04+/26.04、Fedora 40+、Arch）会拒绝
`dlopen` 声明了可执行栈的库，并对跨分配器释放的指针直接 abort。

本仓库对该安装包做**定点二进制修补**（每步都有字节级校验），并支持封装为
**deb / rpm / pacman** 三种格式。

- 原始安装包：`weworklocal_2.6.290000.49_1648784689.deb`
  - md5：`21ec0afd2ee3e40872ecd97f474608a5`
  - sha256：`df8c22258eee6582e7b0e3905186dba89df12d1fc02b3b90c7c382104062b44b`
- 实测环境：Ubuntu 26.04 LTS（glibc 2.43，kernel 7.0），KDE Wayland
- 迭代历史：patched（仅能启动）→ patched2（修退出崩溃）→ patched3（可登录，
  进主界面闪退）→ **patched4（当前版本，主界面连续 10 分钟以上无崩溃）**。
  本仓库对应 patched4。

---

## 一、三步流程总览

| 步骤 | 做什么 | 结果 |
|---|---|---|
| 1. 下载 | 在 app.seu.edu.cn 下载 Linux 版企业微信 | `weworklocal_2.6.290000.49_1648784689.deb` |
| 2. 打补丁 | `./rebuild.sh 原始.deb 输出.deb` | `...patched4.deb`（可安装的修补版） |
| 3. 安装 | Debian 系：`sudo apt install ./输出.deb`<br>RPM/Arch 见第四节 | 菜单出现「企业微信」，正常运行 |

---

## 二、第一步：从 app.seu.edu.cn 下载原始安装包

1. 在校园网 / VPN 环境打开 <https://app.seu.edu.cn/>，用统一身份认证登录；
2. 搜索并进入「企业微信」，在下载页选择 **Linux 版（64 位，deb 格式）**；
   （若门户未直接提供 Linux 版链接，可向学校信息中心索取同版本文件
   `weworklocal_2.6.290000.49_1648784689.deb`。）
3. 下载后先做校验，必须与下面一致，否则补丁无法套用：

```bash
md5sum weworklocal_2.6.290000.49_1648784689.deb
# 应为: 21ec0afd2ee3e40872ecd97f474608a5
```

> 补丁脚本按**该版本的固定文件偏移 / 特征字节**定位（`patch_*.py` 内有
> assert 校验）。门户上如换成新版本，`rebuild.sh` 会立即报错退出，
> 不会产出损坏的包；需要针对新版本重新适配。

---

## 三、第二步：打补丁

依赖（Ubuntu / Debian）：

```bash
sudo apt install python3 gcc binutils dpkg
```

```bash
git clone <本仓库地址> && cd wework-patch      # 或直接在本目录操作
./rebuild.sh ~/下载/weworklocal_2.6.290000.49_1648784689.deb \
             ~/weworklocal_2.6.290000.49_1648784689.patched4.deb
```

`rebuild.sh` 依次做 5 件事：

1. `clear_execstack.py` — 清除 `libwework_sdk.so` 的可执行栈标志（execstack）
2. `patch_wwlocal.py` — 修复 `wwlocal` 中缺 `%fs` 段前缀的坏指令
3. `patch_curl_strdup.py` — 改 `libcurl.so.4` / `libcurl.so.4.3.0` 的
   `strdup/strndup` 导入符号
4. `patch_saas_free.py` — 修 `libwework_saas_lib.so` 的 `new[]`+`free` 混用
5. 编译 `libwwlocal_compat.so`（退出保护 + `wtrdup/wtrndup`），加入启动器，
   并更新版本号 / desktop 入口 / postinst / md5sums

产物参考 md5：`f09c9506c9aee8860959c1df2f51bae3`
（重新构建时 deb 内时间戳可能不同，md5 会有差异，功能一致。）

---

## 四、第三步：安装与运行

### Debian / Ubuntu（deb，推荐）

```bash
sudo apt install ./weworklocal_2.6.290000.49_1648784689.patched4.deb
```

- 菜单启动「企业微信」；命令行：`/opt/企业微信/wwlocal-launcher.sh`
- **不要**直接运行 `/opt/企业微信/wwlocal`（缺 LD_PRELOAD 预载，退出会崩）

### Fedora / RHEL / openSUSE（RPM）

```bash
./pack_rpm.sh ~/weworklocal_2.6.290000.49_1648784689.patched4.deb
# Fedora / RHEL:
sudo dnf install ./wwlocal-2.6.290000.4-1.x86_64.rpm
# openSUSE（未签名包）:
sudo zypper install --allow-unsigned-rpm ./wwlocal-2.6.290000.4-1.x86_64.rpm
```

### Arch Linux（pacman）

```bash
./pack_arch.sh ~/weworklocal_2.6.290000.49_1648784689.patched4.deb
sudo pacman -U ./wwlocal-2.6.290000.4-1-x86_64.pkg.tar.zst

# 或者：从原始 deb 原生重建（需 base-devel）
#   把原始 deb 放到本目录后执行  makepkg -f
```

### 本目录已构建好的产物（可免构建直接安装）

| 格式 | 文件 | 大小 | md5 |
|---|---|---|---|
| RPM | `wwlocal-2.6.290000.4-1.x86_64.rpm` | 123M | `ee47f070ec120cd9d6e703ae7b534d80` |
| pacman | `wwlocal-2.6.290000.4-1-x86_64.pkg.tar.zst` | 123M | `2cc0b9e538fc966ccc3a7e73f9f267e1` |

（大体积二进制不入 git；重新生成用上面的 `pack_*.sh`。）

### 注意事项

- 三种格式安装的是同一个 `/opt/企业微信`，**同一台机器只装一种格式**；
- 包体未做 GPG 签名：dnf / pacman 本地安装默认可直接装，zypper 需加
  `--allow-unsigned-rpm`；
- `chrome-sandbox` 必须保持 `4755 root:root`（Electron 沙箱需要，打包脚本
  已处理；注意用 `bsdtar` 以普通用户解包会剥离 setuid 位）；
- 无 root 权限的 Debian/Ubuntu 构建机：可先运行 `./setup_build_tools.sh`
  把 rpmbuild / bsdtar / pacman 解包到 `.buildtools/`，`pack_*.sh` 会自动使用。

---

## 五、修复内容（原理）

### 1. `libwework_sdk.so` 声明了可执行栈（execstack）
内核 / 新版 glibc（≥ 2.41）拒绝 `dlopen` 这类库：
`dlopen err: libwework_sdk.so: cannot enable executable stack as shared object requires: Invalid argument`
**修复**：清除该 ELF 的 `PT_GNU_STACK` 中的 `PF_X` 标志（等价 `execstack -c`）。

### 2. `wwlocal` 主程序里的一条坏指令（缺 `%fs` 前缀）
虚拟地址 `0x18683c0` 处：`c6 04 25 39 00 00 00 21`（`movb $0x21,[0x39]`，写绝对地址，必崩）。
正确为 `movb $0x21,%fs:0x39`（缺 `0x64` 段前缀）。该函数有 13 处调用点。
**修复**：把该函数重写为 `movb $0x21,%fs:0x39; ret`。

### 3. 关闭应用时崩溃（SIGSEGV / coredump / KDE 崩溃提示）
退出时 glibc 依次执行 `__cxa_atexit` 注册的第三方析构，其中对字符串等的释放
会走进 wwlocal 自带的老版 tcmalloc 的内部 free list 而崩溃：

```
#0 wwlocal + 0x1869d30          ← 老 tcmalloc free list
#3 __run_exit_handlers (libc)
```

glibc 内部是 `__libc_start_call_main` 直接调用内部别名 `__GI_exit`，无法用
`LD_PRELOAD` 覆盖 `exit()`。
**修复**：`libwwlocal_compat.so` 拦截 `__libc_start_main`，把 main 包一层，
main 返回后 `fflush` + `_Exit()`，不再进入 glibc 退出处理链
（应用自身收尾在 main 返回前已完成；被跳过的只是第三方静态析构清理）。

### 4. 输入组织机构域后闪退（SIGABRT / `free(): invalid size`）
`libwework_sdk` / `libcurl` 等以 **RTLD_DEEPBIND** 被 dlopen，绕过一切
`LD_PRELOAD` 拦截：

- 这些库自己的 `malloc/free` 在自身作用域内解析到 **glibc**；
- 但 libc 内部函数（`strdup` 等）里的 `malloc` 经全局作用域落到
  **wwlocal 自带的 tcmalloc**；
- libcurl 用 `strdup` 存字符串选项, 之后用 **glibc `free`** 释放这个
  tcmalloc 指针 → 同一指针跨分配器 → 新版 glibc 直接 abort：

```
#0 musable / malloc_printerr  (libc, "free(): invalid size")
#1 realloc / free
#2 Curl_setopt (libcurl)
#8 CurlConnection::SetVerifySslCertificate  ← 设置 URL 时刷新字符串选项
#9 CurlConnection::SetUrl
```

**修复**：把 `libcurl.so.4` / `libcurl.so.4.3.0` 的 `strdup` / `strndup`
导入符号改名为 `wtrdup` / `wtrndup`，由 `libwwlocal_compat.so` 用
**glibc 的 malloc** 实现（与 libcurl 的 free 一致）。只动 libcurl 这一处，
主程序与 tcmalloc 的全部现有行为不变（之前尝试过"全部统一到 glibc"的
方案，会引出 GLib 类型系统崩溃，已放弃）。

### 5. 进入主界面后闪退（SIGABRT / SIGSEGV，释放 new[] 缓冲区用错分配器）
`libwework_saas_lib.so` 以 RTLD_DEEPBIND 方式加入加载组后，该库内符号解析为：

- `operator new[] / delete`（经 libstdc++ → 全局作用域）→ **wwlocal 自带 tcmalloc**
- 直接调用的 `malloc / free / calloc / realloc`（经 libc）→ **glibc**

设备指纹采集线程（读网卡 / WLAN SSID：`socket + ioctl(SIOCGIWESSID)`）里
用 `new char[33]` 分配缓冲区，随后却调用 C 的 `free()` 释放：

```asm
39de722: call _Znam@plt          ; operator new[](33)  -> tcmalloc
...
39de80f: call free@plt           ; free(buffer)        -> glibc free( tcmalloc 指针 )
```

glibc 2.43 的 `free()` 对 tcmalloc 指针直接崩溃（`free(): invalid ...` 或
段错误）。登录进入主界面后该线程运行 → 闪退。实测 coredump 两次，均落在此指令。

**修复**：把该函数内两处释放 new[] 缓冲区的 `call free@plt` 改为
`call _ZdaPv@plt`（`operator delete[]`，经 libstdc++ → wwlocal tcmalloc），
与分配端同一分配器。

---

## 六、包内改动清单

| 文件 | 改动 |
|---|---|
| `opt/企业微信/libwework_sdk.so` | 清除 execstack 标志 |
| `opt/企业微信/wwlocal` | 修复 `0x18683c0` 处的坏指令 |
| `opt/企业微信/libcurl.so.4`、`libcurl.so.4.3.0` | `strdup/strndup` 导入改名 |
| `opt/企业微信/libwework_saas_lib.so` | `0x39de80f`、`0x39de8d1` 两处 `free` -> `delete[]` |
| `opt/企业微信/libwwlocal_compat.so` | 新增：退出保护 + wtrdup/wtrndup |
| `opt/企业微信/wwlocal-launcher.sh` | 新增：启动器（预载 compat 库后 exec wwlocal） |
| `usr/share/applications/wwlocal.desktop` | `Exec` 指向启动器 |
| `DEBIAN/postinst` | 同上前 |
| `DEBIAN/control` | 版本号 2.6.290000.4 |
| `DEBIAN/md5sums` | 重新生成 |

---

## 七、RPM / Arch 打包实现要点

- **依赖表达**：RPM 版用 soname（`libgtk-3.so.0()(64bit)` 等 34 项 +
  `glibc` + `xdg-utils`），Fedora/RHEL/openSUSE 通用；AppIndicator 托盘、
  libnotify、libsecret、GL/GBM 为弱依赖（Recommends）。Arch 版用 Arch 包名
  （gtk3、nss、at-spi2-core、alsa-lib 等，含 optdepends 说明）。
- **安装脚本**与 deb 版 postinst 行为一致：刷新 desktop 数据库与图标缓存、
  给运行 sudo 的用户桌面放置快捷方式；Fedora/RHEL 上额外执行
  `restorecon`（SELinux）。
- pacman 7 会**以包内 `.MTREE` 作为文件清单**：`.MTREE` 缺失或不全会导致
  "安装成功但静默跳过解包"，`pack_arch.sh` 按 makepkg 相同方式生成，请勿
  手工删改包内该文件。
- RPM 与 Arch 包内容与修补后的 deb **逐字节一致**，仅封装与安装脚本适配。

---

## 八、验证记录

- **deb（实测）**：Ubuntu 26.04 LTS / glibc 2.43 / KDE Wayland。启动、显示
  界面、输入组织机构域（seuapp）进入登录二维码页、登录进入主界面、正常关闭
  （退出码 0、无 coredump）。修复前进入主界面 6~52 秒内必崩；修复后连续运行
  10 分钟以上无崩溃（同一账号自动登录场景）。
- **RPM（假根安装验证）**：`rpm -U` 安装成功，`rpm -V` 全部通过，权限 /
  属主（含 `chrome-sandbox` 4755 root:root）正确，解包内容与 deb 载荷逐字节
  一致。
- **pacman（假根安装验证）**：`pacman -U` 全量解包，安装结果与 deb 载荷逐
  字节一致、setuid/属主正确；`pacman -Qip` 元数据正常。
- 未在真实 Fedora / openSUSE / Arch 机器上实测运行；补丁针对应用与 glibc 的
  兼容性，与发行版无关，预期同样适用。

---

## 九、本目录文件

```bash
./rebuild.sh <原始deb> <输出deb>     # 一键打补丁（deb -> patched deb）
```

- `clear_execstack.py` — 清除指定 ELF 的 execstack 标志
- `patch_wwlocal.py` — 修复 `wwlocal` 坏指令
- `patch_curl_strdup.py` — 改 libcurl 的 strdup/strndup 导入
- `patch_saas_free.py` — 修 libwework_saas_lib.so 的 new[]+free 混用
- `compat.c` / `libwwlocal_compat.so` — 退出保护 + wtrdup/wtrndup（源码与产物）
- `wwlocal-launcher.sh` — 启动器
- `rebuild.sh` — 一键重建脚本（deb）
- `trace_new_free.py` — 调试工具：在 objdump 反汇编里追踪 `free` 参数的
  分配来源，找出 "new 分配 / C free 释放" 的混用点（本次修复即由此定位）
- `pack_rpm.sh` — 把修补后的 deb 重打包为 RPM（Fedora / RHEL / openSUSE）
- `pack_arch.sh` — 把修补后的 deb 重打包为 Arch Linux 包（`.pkg.tar.zst`）
- `setup_build_tools.sh` — 无 root 权限准备 rpmbuild / bsdtar / pacman
  工具链（下载解包到 `.buildtools/`，仅用于打包与自检）
- `PKGBUILD`、`wwlocal.install` — Arch 原生重建用（原始 deb + 本目录补丁
  脚本，`makepkg -f`；与 `pack_arch.sh` 二选一）

---

## 十、备注：为什么不建议 AppImage / Flatpak

本次问题不是"缺老运行时库"，而是**进程内同时存在 tcmalloc 与 glibc
两套分配器、少数指针跨分配器释放**所致（wwlocal 自带 tcmalloc 并导出
malloc/free，SDK 组又以 deepbind 方式使用 glibc）。

- AppImage：不换 glibc 就没区别；要像 Steam Runtime 那样整套捆绑老
  glibc 才能改变行为，工程量与风险都很大。
- Flatpak：用老 runtime（20.08/21.08，glibc 2.31/2.33）*也许*能靠老
  glibc 的宽松检查规避，但运行时已 EOL、打包需处理权限/托盘/IPC/登录，
  且不保证覆盖其它兼容点。

结论：deb（或 rpm/pacman）内的定点修复（本补丁）已经解决已知的全部问题；
如后续遇到新的系统兼容性问题，再评估 Flatpak 方案。
