#!/bin/bash
# 企业微信 launcher
# 预载 libwwlocal_compat.so:
#   - 退出保护 (修 "关闭应用时崩溃")
#   - wtrdup/wtrndup (配合 libcurl 改名, 修 "输入组织机构域后闪退")
HERE="$(dirname "$(readlink -f "$0")")"
export LD_PRELOAD="$HERE/libwwlocal_compat.so${LD_PRELOAD:+:$LD_PRELOAD}"
exec "$HERE/wwlocal" "$@"
