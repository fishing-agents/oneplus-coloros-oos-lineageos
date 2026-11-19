#!/usr/bin/env python3
"""Print the Qualcomm anti-rollback (ARB) index of an xbl_config image.

Reads the OEM metadata record (major, minor, arb, reserved) from the ELF hash segment.
Format as documented by https://github.com/Bartixxx32/OnePlus-antirollchecker (classic
offset, plus the 16-byte-shifted v8 layout).
usage: scripts/arb.py <xbl_config.img>   -> prints the index, exit 1 if unparseable
"""
import struct
import sys


def plausible(major, minor, arb, reserved, need_major=False):
    return (1 if need_major else 0) <= major <= 10 and minor <= 10 and arb <= 100 and reserved == 0


def arb_index(d):
    if d[:4] != b"\x7fELF" or d[4] != 2:
        return None
    phoff, = struct.unpack_from("<Q", d, 0x20)
    phentsize, phnum = struct.unpack_from("<HH", d, 0x36)
    segs = []
    for i in range(phnum):
        p = phoff + i * phentsize
        if p + 56 > len(d):
            break
        if struct.unpack_from("<I", d, p)[0] == 0 and struct.unpack_from("<Q", d, p + 32)[0] > 0x100:
            segs.append((struct.unpack_from("<Q", d, p + 8)[0], struct.unpack_from("<Q", d, p + 32)[0]))
    if not segs:
        return None
    start, length = segs[-1]
    for off in range(0, min(0x1000, max(0, length - 36)), 4):
        ver, common, qti, oem, tbl = struct.unpack_from("<5I", d, start + off)
        if 1 <= ver <= 10 and common <= 0x1000 and oem <= 0x4000 and tbl <= 0x4000 \
                and off + 36 + common + qti + oem <= length:
            break
    else:
        return None
    classic = start + off + 36 + common + qti
    rec = struct.unpack_from("<4I", d, classic)
    if plausible(*rec):
        return rec[2]
    for pos in range(classic + 16, min(start + length - 16, classic + 0x400) + 1, 16):
        rec = struct.unpack_from("<4I", d, pos)
        if plausible(*rec, need_major=True):
            return rec[2]
    return None


if __name__ == "__main__":
    idx = arb_index(open(sys.argv[1], "rb").read())
    if idx is None:
        sys.exit(f"{sys.argv[1]}: no ARB metadata found")
    print(idx)
