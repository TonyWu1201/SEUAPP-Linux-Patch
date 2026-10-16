#!/usr/bin/env python3
"""Patch wwlocal (企业微信 2.6.290000.49) so it runs on modern glibc.

Patch list (all offsets are vaddrs; wwlocal .text maps file=vaddr-0x1000):
 1. vaddr 0x18683c0: tiny setter `movb $imm, [abs]` lost its %fs segment prefix
    (should be `movb $0x21, %fs:0x39`).  Rewrite the 16-byte function in place.
"""
import struct
import sys

WWLOCAL = sys.argv[1] if len(sys.argv) > 1 else "wwlocal"

FILE_BIAS = 0x1000  # vaddr -> file offset for .text


def patch_file(path):
    with open(path, "r+b") as f:
        data = f.read()

        # --- Patch 1: vaddr 0x18683c0 (function, 16 bytes available) -------
        off = 0x18683C0 - FILE_BIAS
        old = bytes.fromhex("554889e5c6042539000000215dc3cccc")
        assert data[off:off + len(old)] == old, (
            "patch1: unexpected bytes: " + data[off:off + 16].hex())
        new = bytes.fromhex(
            "554889e5"                  # push %rbp
            "64c604253900000021"        # movb $0x21,%fs:0x39
            "5dc3"                      # pop %rbp; ret
            "cc")                       # padding
        assert len(new) == 16
        f.seek(off)
        f.write(new)
        print(f"patch1 applied at vaddr 0x18683c0 (file 0x{off:x})")


if __name__ == "__main__":
    patch_file(WWLOCAL)
