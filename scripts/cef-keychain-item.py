#!/usr/bin/env python3
"""Names Pane's own Keychain item in CEF's framework and prints the service name it reads.

  scripts/cef-keychain-item.py <framework binary>    (scripts/fetch-cef.sh runs it)

Chromium derives the key for cookies, saved passwords and card numbers from a secret in the login
Keychain item "<Name> Safe Storage". The CEF builds Pane fetches are upstream Cra's, built with
scripts/cef-patches/keychain-service-name.patch as Cra had it: "Cra Safe Storage", account
"Chromium". Pane's is "Pane Safe Storage", account "Pane" (13 Nov 2026), so macOS names Pane when
it asks about the item. SafeStorage.swift moves the secret over once, so nothing is lost.

The name is changed in the binary. os_crypt's constants hold the 26 bytes
"Cra Safe Storage\\0Chromium\\0", which become "Pane Safe Storage\\0Pane\\0\\0\\0\\0". The compiler
folded both lengths into the code that copies them into KeychainPassword's std::strings (libc++
short strings, arm64), so that code is rewritten in place too:

  service (16 bytes)                     becomes (17 bytes)
    mov  wN, #16                           mov  wN, #17
    strb wN, [xD, #23]                     strb wN, [xD, #23]       (the short size)
    adrp xS, page; add xS, xS, off         adrp xS, page; add xS, xS, off
    add  xT, xD, #16                       ldr  q0, [xS]
    cmp  xS, xT                            str  q0, [xD]
    ccmp xS, xD, #0, lo                    ldrb wT, [xS, #16]
    b.hs <trap>                            strb wT, [xD, #16]
    ldr  q0, [xS]                          strb wzr, [xD, #17]
    str  q0, [xD]                          nop
    strb wzr, [xD, #16]                    nop

  The four instructions dropped are libc++'s hardening check that the source does not overlap the
  string, which a constant in __TEXT and a static in __DATA never do.

  account (8 bytes, "Chromium" from immediates)  becomes "Pane" (4 bytes)
    mov wN, #8 / add xS, …, off / add xT, xD, #8      mov wN, #4 / add xS, …, off + 18 / add xT, xD, #4
    mov xS, #"Ch"; movk "ro", "mi", "um"              mov xS, #"Pa"; movk "ne"; nop; nop
    str xS, [xD]; strb wzr, [xD, #8]                   str xS, [xD]; strb wzr, [xD, #4]

Every reference to the constants must be one of these shapes, and no branch may land inside a
rewritten run; otherwise nothing changes and the framework keeps Cra's item (SafeStorage reads
whichever one the build names in Info.plist). After a change the framework is signed again
(ad hoc; scripts/build.sh signs the app's copy for real).
"""
import os
import struct
import subprocess
import sys

PANE, CRA = "Pane Safe Storage", "Cra Safe Storage"
OLD = b"Cra Safe Storage\0Chromium\0"
NEW = b"Pane Safe Storage\0Pane\0\0\0\0"
assert len(OLD) == len(NEW) == 26
ACCOUNT_AT = len(b"Cra Safe Storage\0")     # "Chromium" in OLD
NEW_ACCOUNT_AT = len(b"Pane Safe Storage\0")  # "Pane" in NEW

NOP = 0xD503201F


def movz32(rd, imm): return 0x52800000 | (imm << 5) | rd
def movz64(rd, imm, hw=0): return 0xD2800000 | (hw << 21) | (imm << 5) | rd
def movk64(rd, imm, hw): return 0xF2800000 | (hw << 21) | (imm << 5) | rd
def add64(rd, rn, imm): return 0x91000000 | (imm << 10) | (rn << 5) | rd
def cmp64(rn, rm): return 0xEB000000 | (rm << 16) | (rn << 5) | 31
def ccmp64_lo(rn, rm): return 0xFA400000 | (rm << 16) | (0x3 << 12) | (rn << 5)
def strb(rt, rn, off): return 0x39000000 | (off << 10) | (rn << 5) | rt
def ldrb(rt, rn, off): return 0x39400000 | (off << 10) | (rn << 5) | rt
def ldr_q0(rn): return 0x3DC00000 | (rn << 5)
def str_q0(rn): return 0x3D800000 | (rn << 5)
def str64(rt, rn): return 0xF9000000 | (rn << 5) | rt
def is_bhs(w): return (w & 0xFF00001F) == 0x54000002


def keep(name, why):
    """Leaves the framework as it is: it reads `name`."""
    if why:
        print(f"Keeping the Keychain item {name}: {why}", file=sys.stderr)
    print(name)
    sys.exit(0)


def macho(data):
    """(segments, __text) of a thin arm64 Mach-O: segments as (vmaddr, vmsize, fileoff, filesize)."""
    magic, cputype = struct.unpack_from("<II", data, 0)
    if magic != 0xFEEDFACF or cputype != 0x0100000C:
        return None
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off, segs, text = 32, [], None
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, off)
        if cmd == 0x19:  # LC_SEGMENT_64
            segname = data[off + 8:off + 24].rstrip(b"\0")
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", data, off + 24)
            segs.append((vmaddr, vmsize, fileoff, filesize))
            nsects = struct.unpack_from("<I", data, off + 64)[0]
            for s in range(nsects):
                so = off + 72 + s * 80
                sect = data[so:so + 16].rstrip(b"\0")
                addr, ssize = struct.unpack_from("<QQ", data, so + 32)
                soff = struct.unpack_from("<I", data, so + 48)[0]
                if segname == b"__TEXT" and sect == b"__text":
                    text = (addr, ssize, soff)
        off += size
    return (segs, text) if text else None


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.split("\n\n")[1])
    path = sys.argv[1]
    with open(path, "rb") as f:
        data = bytearray(f.read())
    has_pane, has_cra = PANE.encode() + b"\0" in data, CRA.encode() + b"\0" in data
    if has_pane and not has_cra:
        keep(PANE, None)
    if not has_cra:
        print("This CEF names neither Pane Safe Storage nor Cra Safe Storage", file=sys.stderr)
        sys.exit(1)
    if data.count(OLD) != 1:
        keep(CRA, "its constants are not laid out as in the builds this script knows")
    layout = macho(data)
    if not layout:
        keep(CRA, "the name is only changed in arm64 frameworks")
    segs, (text_addr, text_size, text_off) = layout
    blob_off = data.find(OLD)
    seg = next((s for s in segs if s[2] <= blob_off < s[2] + s[3]), None)
    if not seg:
        keep(CRA, "its constants are outside every segment")
    blob = seg[0] + blob_off - seg[2]

    import numpy as np  # only needed for a change
    count = text_size // 4
    w = np.frombuffer(bytes(data[text_off:text_off + count * 4]), dtype="<u4")
    pc = np.arange(count, dtype=np.int64) * 4 + text_addr

    # Every ADRP of the constants' page, and the ADD that completes it within 64 instructions.
    idx = np.nonzero((w & 0x9F000000) == 0x90000000)[0]
    ins = w[idx].astype(np.int64)
    imm = (((ins >> 5) & 0x7FFFF) << 2) | ((ins >> 29) & 3)
    imm = np.where(imm & (1 << 20), imm - (1 << 21), imm)
    page = (pc[idx] & ~0xFFF) + (imm << 12)
    service, account = [], []
    for i in idx[page == (blob & ~0xFFF)]:
        i = int(i)
        rd = int(w[i]) & 31
        for j in range(i + 1, min(i + 65, count)):
            x = int(w[j])
            if (x & 0xFF800000) == 0x91000000 and ((x >> 5) & 31) == rd:
                target = (blob & ~0xFFF) + (((x >> 10) & 0xFFF) << (12 * ((x >> 22) & 1)))
                if blob <= target < blob + len(OLD):
                    if j != i + 1 or (x & 31) != rd or target not in (blob, blob + ACCOUNT_AT):
                        keep(CRA, f"an unknown reference to its constants at {pc[i]:#x}")
                    (service if target == blob else account).append(i)
                break
    if not service or len(service) != len(account):
        keep(CRA, f"{len(service)} service and {len(account)} account references, not pairs")

    def word(i): return int(w[i])
    patches = {}  # instruction index -> new word
    runs = []     # (first, last) instruction indexes rewritten

    for i in service:
        n = word(i - 2) & 31
        if word(i - 2) != movz32(n, 16):
            keep(CRA, f"no 'mov w, #16' before {pc[i]:#x}")
        d = (word(i - 1) >> 5) & 31
        s = word(i) & 31
        t = word(i + 2) & 31
        expected = {i - 1: strb(n, d, 0x17), i + 2: add64(t, d, 0x10), i + 3: cmp64(s, t), i + 4: ccmp64_lo(s, d),
                    i + 6: ldr_q0(s), i + 7: str_q0(d), i + 8: strb(31, d, 0x10)}
        if any(word(k) != v for k, v in expected.items()) or not is_bhs(word(i + 5)) or len({d, s, t}) < 3 or n == d:
            keep(CRA, f"the service name's copy at {pc[i]:#x} is not the shape this script knows")
        patches.update({i - 2: movz32(n, 17), i + 2: ldr_q0(s), i + 3: str_q0(d), i + 4: ldrb(t, s, 16),
                        i + 5: strb(t, d, 16), i + 6: strb(31, d, 17), i + 7: NOP, i + 8: NOP})
        runs.append((i - 2, i + 8))

    for i in account:
        n = word(i - 2) & 31
        if word(i - 2) != movz32(n, 8):
            keep(CRA, f"no 'mov w, #8' before {pc[i]:#x}")
        d = (word(i - 1) >> 5) & 31
        s = word(i) & 31
        t = word(i + 2) & 31
        expected = {i - 1: strb(n, d, 0x17), i + 2: add64(t, d, 8), i + 3: cmp64(s, t), i + 4: ccmp64_lo(s, d),
                    i + 6: movz64(s, 0x6843), i + 7: movk64(s, 0x6F72, 1), i + 8: movk64(s, 0x696D, 2),
                    i + 9: movk64(s, 0x6D75, 3), i + 10: str64(s, d), i + 11: strb(31, d, 8)}
        if any(word(k) != v for k, v in expected.items()) or not is_bhs(word(i + 5)) or len({d, s, t}) < 3 or n == d:
            keep(CRA, f"the account name's copy at {pc[i]:#x} is not the shape this script knows")
        lo = (word(i + 1) >> 10) & 0xFFF
        new_lo = lo + NEW_ACCOUNT_AT - ACCOUNT_AT
        if new_lo > 0xFFF or (word(i + 1) >> 22) & 1:
            keep(CRA, f"the account name's address at {pc[i]:#x} can't move within its page")
        patches.update({i - 2: movz32(n, 4), i + 1: add64(s, s, new_lo), i + 2: add64(t, d, 4),
                        i + 6: movz64(s, 0x6150), i + 7: movk64(s, 0x656E, 1), i + 8: NOP, i + 9: NOP,
                        i + 11: strb(31, d, 4)})
        runs.append((i - 2, i + 11))

    # No branch may land inside a rewritten run (its first instruction is fine).
    inside = np.zeros(count, dtype=bool)
    for a, b in runs:
        inside[a + 1:b + 1] = True
    k = np.arange(count, dtype=np.int64)
    targets = []
    m = (w & 0x7C000000) == 0x14000000                       # B, BL
    v = (w & 0x03FFFFFF).astype(np.int64); v = np.where(v & (1 << 25), v - (1 << 26), v)
    targets.append((k + v)[m])
    m = ((w & 0xFF000010) == 0x54000000) | ((w & 0x7E000000) == 0x34000000)  # B.cond, CBZ/CBNZ
    v = ((w >> 5) & 0x7FFFF).astype(np.int64); v = np.where(v & (1 << 18), v - (1 << 19), v)
    targets.append((k + v)[m])
    m = (w & 0x7E000000) == 0x36000000                       # TBZ/TBNZ
    v = ((w >> 5) & 0x3FFF).astype(np.int64); v = np.where(v & (1 << 13), v - (1 << 14), v)
    targets.append((k + v)[m])
    t = np.concatenate(targets)
    t = t[(t >= 0) & (t < count)]
    if inside[t].any():
        keep(CRA, "a branch lands inside the code it would rewrite")

    for i, x in patches.items():
        struct.pack_into("<I", data, text_off + i * 4, x)
    data[blob_off:blob_off + len(NEW)] = NEW
    tmp = path + ".pane-keychain"
    with open(tmp, "wb") as f:
        f.write(data)
    os.chmod(tmp, os.stat(path).st_mode)
    os.replace(tmp, path)
    framework = os.path.dirname(path)
    if framework.endswith(".framework"):
        subprocess.run(["codesign", "--force", "--sign", "-", framework], check=True, capture_output=True)
    print(f"Renamed CEF's Keychain item to {PANE} ({len(service)} + {len(account)} places)", file=sys.stderr)
    print(PANE)


if __name__ == "__main__":
    main()
