#!/usr/bin/env python3
"""
把 libcurl 里的 strdup / strndup 导入符号改名为 wtrdup / wtrndup。

原因: libcurl 以 RTLD_DEEPBIND 方式加载, 它的 free() 解析到 glibc,
但 strdup() 内部经 libc 的 malloc 落到 wwlocal 自带的 tcmalloc,
同一个字符串指针跨分配器释放, 新版 glibc 直接 abort
("free(): invalid size", 输入组织机构域时触发)。

改名后这两个函数由 libwwlocal_compat.so 提供 (用 glibc malloc 实现),
与 libcurl 的 free 一致。

用法: patch_curl_strdup.py <libcurl.so.x.y.z 路径>
"""
import struct
import sys

RENAMES = {"strdup": "wtrdup", "strndup": "wtrndup"}


def main():
    path = sys.argv[1]
    d = bytearray(open(path, "rb").read())
    assert d[:4] == b"\x7fELF" and d[4] == 2, "not ELF64"

    e_shoff = struct.unpack_from("<Q", d, 0x28)[0]
    e_shentsize = struct.unpack_from("<H", d, 0x3A)[0]
    e_shnum = struct.unpack_from("<H", d, 0x3C)[0]

    def sh(i):
        return struct.unpack_from("<IIQQQQIIQQ", d, e_shoff + i * e_shentsize)

    sections = [sh(i) for i in range(e_shnum)]
    dynsym = None
    for s in sections:
        if s[1] == 11:  # SHT_DYNSYM
            dynsym = s
            break
    assert dynsym is not None, "no .dynsym"

    dynstr = sections[dynsym[6]]  # sh_link
    dynsym_off, dynsym_size = dynsym[4], dynsym[5]
    dynstr_off = dynstr[4]
    count = dynsym_size // 24

    done = []
    for i in range(count):
        off = dynsym_off + i * 24
        st_name = struct.unpack_from("<I", d, off)[0]
        if not st_name:
            continue
        end = d.index(b"\0", dynstr_off + st_name)
        name = d[dynstr_off + st_name:end].decode()
        if name in RENAMES:
            new = RENAMES[name]
            assert len(new) == len(name)
            d[dynstr_off + st_name:dynstr_off + st_name + len(name)] = new.encode()
            done.append((i, name, new))

    assert done, "no strdup/strndup imports found"
    open(path, "wb").write(bytes(d))
    print("renamed:", done)


if __name__ == "__main__":
    main()
