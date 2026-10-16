#!/usr/bin/env python3
"""Trace each `call free@plt` in an objdump disassembly back to the origin of the
freed register (operator new / new[] / malloc / calloc / unknown).

It reports sites whose freed pointer traces to _Znwm/_Znam (tcmalloc) under
RTLD_DEEPBIND in the wework libs, i.e. glibc-free-of-tcmalloc-ptr crashes.

Usage: trace_new_free.py <disasm file> <free@plt addr> [new targets: name:addr,...]
"""
import re
import sys


def main():
    path = sys.argv[1]
    free_plt = int(sys.argv[2], 16)
    new_pairs = [p.split(':') for p in sys.argv[3].split(',')] if len(sys.argv) > 3 else []
    NEW = {int(a, 16): n for n, a in new_pairs}
    # auto-added known allocators
    NAME = {'malloc': 'malloc', 'calloc': 'calloc', 'realloc': 'realloc', 'free': 'free',
            '_ZdlPv': '_ZdlPv', '_ZdaPv': '_ZdaPv'}

    inst_re = re.compile(r'^\s+([0-9a-f]+):\s+((?:[0-9a-f]{2} )+)\s*(.*)$')
    lines = []
    with open(path) as f:
        for line in f:
            m = inst_re.match(line)
            if m:
                lines.append((int(m.group(1), 16), m.group(3).strip()))

    def ct(text):
        m = re.search(r'call\s+([0-9a-f]+)\s+<', text) or re.search(r'call\s+([0-9a-f]+)$', text)
        return int(m.group(1), 16) if m else None

    def origin_rax(i):
        for k in range(i - 1, max(0, i - 9), -1):
            c = ct(lines[k][1])
            if c is not None:
                for w in range(k + 1, i):
                    if re.search(r',%rax$', lines[w][1]):
                        return None
                return NEW.get(c, hex(c))
            if re.search(r',%rax$', lines[k][1]):
                return None
            if 'ret' in lines[k][1]:
                break
        return None

    def origin(site, reg, depth=0):
        i, steps = site, 0
        while i > 0 and steps < 3000:
            i -= 1
            steps += 1
            t = lines[i][1]
            m = re.match(rf'([a-z]+)\s+.*,%{reg}$', t)
            if not m:
                continue
            op = m.group(1)
            m = re.match(rf'mov\s+%rax,%{reg}$', t)
            if m:
                o = origin_rax(i)
                return o if o else 'rax-unknown'
            m = re.match(rf'mov\s+%(\w+),%{reg}$', t)
            if m and m.group(1) not in ('rsp', 'rbp', 'rip') and depth < 1:
                r = origin(i, m.group(1), depth + 1)
                return r if r else f'from-{m.group(1)}'
            if op in ('add', 'sub') and re.search(rf'\$,.*,%{reg}$', t):
                continue
            return f'{op}-write'
        return 'exhausted'

    res = []
    for i, (a, t) in enumerate(lines):
        if f'<{"free@plt" if free_plt else ""}>' in t and ct(t) == free_plt:
            reg = None
            for j in range(i - 1, max(0, i - 8), -1):
                m = re.match(r'mov\s+%(\w+),%rdi$', lines[j][1])
                if m:
                    reg = m.group(1)
                    break
                if 'call' in lines[j][1]:
                    break
            if reg:
                res.append((a, reg, origin(i, reg)))
    print(f"{path}: free@plt sites traced: {len(res)}")
    for a, reg, o in res:
        if o in ('_Znam', '_Znwm'):
            print(f"HIGH  {a:#x} rdi<-%{reg} origin={o}")
    from collections import Counter
    print(Counter(r[2] for r in res).most_common(12))


if __name__ == '__main__':
    main()
