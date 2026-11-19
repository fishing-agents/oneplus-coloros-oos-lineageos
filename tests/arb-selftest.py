#!/usr/bin/env python3
"""Self-test for scripts/arb.py: synthetic xbl_config ELFs with known ARB values."""
import struct
import subprocess
import sys
import tempfile


def elf(arb, shifted=False):
    d = bytearray(0x400)
    d[:5] = b"\x7fELF\x02"
    struct.pack_into("<Q", d, 0x20, 64)
    struct.pack_into("<HH", d, 0x36, 56, 1)
    struct.pack_into("<Q", d, 72, 0x200)   # p_offset
    struct.pack_into("<Q", d, 96, 0x200)   # p_filesz
    struct.pack_into("<5I", d, 0x200, 6, 0, 0, 32, 0)
    rec = 0x200 + 36 + (16 if shifted else 0)
    if shifted:
        struct.pack_into("<4I", d, 0x200 + 36, 37, 0, 3, 1)  # garbage at the classic offset
    struct.pack_into("<4I", d, rec, 2, 0, arb, 0)
    return bytes(d)


fail = 0
for arb, shifted in ((0, False), (3, False), (5, True)):
    with tempfile.NamedTemporaryFile(suffix=".img") as f:
        f.write(elf(arb, shifted)); f.flush()
        out = subprocess.run([sys.executable, "scripts/arb.py", f.name], capture_output=True, text=True).stdout.strip()
    ok = out == str(arb)
    fail |= not ok
    print(f"{'ok ' if ok else 'FAIL'} arb={arb} shifted={shifted} -> {out!r}")
with tempfile.NamedTemporaryFile() as f:
    f.write(b"not an elf"); f.flush()
    r = subprocess.run([sys.executable, "scripts/arb.py", f.name], capture_output=True)
    print(f"{'ok ' if r.returncode else 'FAIL'} non-ELF rejected"); fail |= not r.returncode
sys.exit(fail)
