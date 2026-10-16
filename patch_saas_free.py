#!/usr/bin/env python3
"""
Patch libwework_saas_lib.so: 修 "进入主界面后闪退" (SIGABRT/SIGSEGV, free of new[] ptr)。

背景:
  libwework_saas_lib.so 以 RTLD_DEEPBIND 方式加载后，其作用域内的符号解析为:
    - operator new[] / delete  (经 libstdc++ -> 全局作用域)  -> wwlocal 内置 tcmalloc
    - 直接调用的 malloc/free    (经 libc)                     -> glibc
  设备信息采集函数(读 WLAN SSID, ioctl SIOCGIWESSID)里用 new char[33] 分配缓冲区，
  之后却用 C 的 free() 释放 -> glibc free() 拿到 tcmalloc 指针 -> 新版 glibc
  直接 abort ("free(): invalid ...") 或段错误。进入主界面时该线程被触发，表现为闪退。

修复:
  该函数内两处释放 new[] 缓冲区的 `call free@plt` 改为 `call _ZdaPv@plt`
  (operator delete[])，使释放走与 new[] 相同的 tcmalloc 分配器。

用法: patch_saas_free.py <libwework_saas_lib.so 路径>
"""
import struct
import sys

# (vaddr, 原 5 字节 call 编码) —— 均为 call free@plt (目标 0x201b940)
SITES = [
    (0x39DE80F, b"\xe8\x2c\xd1\x63\xfe"),  # ioctl 成功路径: 释放 SSID 缓冲区
    (0x39DE8D1, b"\xe8\x6a\xd0\x63\xfe"),  # socket/ioctl 失败路径: 同一缓冲区
]
FREE_PLT = 0x201B940   # free@plt
ZDA_PLT = 0x1FF4010    # _ZdaPv@plt (operator delete[])


def patch_file(path):
    with open(path, "r+b") as f:
        data = f.read()
        for vaddr, old in SITES:
            cur = data[vaddr:vaddr + 5]
            assert cur == old, (
                f"{path}: vaddr 0x{vaddr:x} 预期 {old.hex()} 实际 {cur.hex()}")
            tgt = struct.unpack_from("<i", cur, 1)[0] + vaddr + 5
            assert tgt == FREE_PLT, f"call target 0x{tgt:x} != free@plt"
            rel = ZDA_PLT - (vaddr + 5)
            new = b"\xe8" + struct.pack("<i", rel)
            f.seek(vaddr)
            f.write(new)
            print(f"patched 0x{vaddr:x}: call free@plt -> call _ZdaPv@plt")


if __name__ == "__main__":
    patch_file(sys.argv[1])
