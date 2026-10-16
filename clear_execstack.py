#!/usr/bin/env python3
"""Clear PF_X on PT_GNU_STACK program headers of an ELF file (in place)."""
import struct
import sys


def patch(path):
    with open(path, "r+b") as f:
        data = f.read()
        if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
            raise SystemExit(f"{path}: not a 64-bit little-endian ELF")
        e_phoff = struct.unpack_from("<Q", data, 0x20)[0]
        e_phentsize = struct.unpack_from("<H", data, 0x36)[0]
        e_phnum = struct.unpack_from("<H", data, 0x38)[0]
        changed = False
        for i in range(e_phnum):
            off = e_phoff + i * e_phentsize
            p_type = struct.unpack_from("<I", data, off)[0]
            if p_type == 0x6474E551:  # PT_GNU_STACK
                p_flags = struct.unpack_from("<I", data, off + 4)[0]
                if p_flags & 0x1:  # PF_X
                    new = p_flags & ~0x1
                    f.seek(off + 4)
                    f.write(struct.pack("<I", new))
                    changed = True
                    print(f"{path}: GNU_STACK flags 0x{p_flags:x} -> 0x{new:x}")
        if not changed:
            print(f"{path}: no executable-stack flag found")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        patch(p)
