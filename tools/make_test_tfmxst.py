#!/usr/bin/env python3
"""Generate ChipDeck's own public-domain TFMX-ST (Atari ST TFMX) test tune:
tests/data/mdat.chipdeck-st-test (music data) and
tests/data/smpl.chipdeck-st-test (4-bit digi-drum samples).

Same unpacked TFMX layout as tools/make_test_tfmx.py, but the instrument
macros use the ST's YM2149 commands ($40 and up), which is how TFMX-ST
files are recognised (the macro pointer at $7FC must mark the end of the
macros, as in real files).

Song 1 = steps 0-1: track 1 a square lead with a volume decay on YM
voice A (macro 0), track 2 a square bass on voice B (macro 1), track 3 a
noise hi-hat on voice C (macro 2). Step 1 repeats it transposed by +5.
Song 2 = step 2: a 4-bit digi drum on voice C (macro 3) every 8 rows.
Speed 5 = a pattern row every 6 VBLs (120 ms at 50 Hz).
Run: python3 tools/make_test_tfmxst.py
"""
import os
import random
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "tests", "data")


def be16(v):
    return struct.pack(">H", v & 0xFFFF)


def be32(v):
    return struct.pack(">I", v & 0xFFFFFFFF)


def nw(note, macro, volume, channel, wait):
    return bytes([0x80 | note, macro, (volume << 4) | channel, wait])


END = bytes([0xF0, 0, 0, 0])


def cmd(c, bb=0, cd=0, ee=0):
    return bytes([c, bb, cd, ee])


def build():
    random.seed(1)
    drum = bytes(max(0, min(15, int((15 - i / 40.0) * random.random() + 0.5)))
                 for i in range(600))
    smpl = bytes(4) + drum

    lead = b"".join(nw(n, 0, 15, 0, 3) for n in [0x18, 0x1C, 0x1F, 0x24, 0x1F, 0x1C, 0x18, 0x13]) + END
    bass = b"".join(nw(n, 1, 15, 1, 7) for n in [0x0C, 0x0C, 0x13, 0x13]) + END
    hats = b"".join(nw(0x20, 2, 15, 2, 3) for _ in range(8)) + END
    drums = b"".join(nw(0x18, 3, 15, 2, 7) for _ in range(4)) + END

    macros = [
        # 0: lead on voice A: tone on, noise off, note, volume 60, decay
        cmd(0x40) + cmd(0x41, 1, 0, 0) + cmd(0x08) + cmd(0x0D, 0, 0, 0x0F)
        + cmd(0x0F, 2, 3, 0x10) + cmd(0x07),
        # 1: bass on voice B, vibrato
        cmd(0x40) + cmd(0x41, 1, 0, 0) + cmd(0x08) + cmd(0x0E, 0, 0, 0x34)
        + cmd(0x0C, 8, 0, 2) + cmd(0x07),
        # 2: hi-hat on voice C: noise only, noise period via the pseudo voice
        cmd(0x40) + cmd(0x41, 0, 0, 1) + cmd(0x44, 0x08) + cmd(0x0E, 0, 0, 0x30)
        + cmd(0x0F, 6, 0, 0) + cmd(0x07),
        # 3: digi drum on voice C, rate period $100, stop after 20 VBLs
        cmd(0x49, 0, 0x01, 0x00) + cmd(0x48, 0, 0, 4) + cmd(0x04, 0, 0, 20)
        + cmd(0x4A) + cmd(0x07),
    ]

    hdr = bytearray(0x800)
    hdr[0:10] = b"TFMX-SONG "
    text = b"ChipDeck TFMX-ST test (public domain)"
    hdr[0x10:0x10 + len(text)] = text
    hdr[0x100:0x102] = be16(0)
    hdr[0x140:0x142] = be16(1)
    hdr[0x180:0x182] = be16(5)
    hdr[0x102:0x104] = be16(2)
    hdr[0x142:0x144] = be16(2)
    hdr[0x182:0x184] = be16(5)

    off = bytes([0xFF, 0x00])
    steps = b""
    steps += bytes([0, 0, 1, 0, 2, 0]) + off * 5
    steps += bytes([0, 5, 1, 5, 2, 0]) + off * 5
    steps += bytes([3, 0]) + off * 7
    steps += be16(0xEFFE) + be16(0) + bytes(12)

    base = 0x800 + len(steps)
    body = b""
    patt_ofs = []
    for p in [lead, bass, hats, drums]:
        patt_ofs.append(base + len(body))
        body += p
    mac_ofs = []
    for m in macros:
        mac_ofs.append(base + len(body))
        body += m
    end = base + len(body)
    for i, o in enumerate(patt_ofs):
        hdr[0x400 + i * 4:0x404 + i * 4] = be32(o)
    for i, o in enumerate(mac_ofs):
        hdr[0x600 + i * 4:0x604 + i * 4] = be32(o)
    hdr[0x7FC:0x800] = be32(end)
    return bytes(hdr) + steps + body, smpl


def main():
    mdat, smpl = build()
    with open(os.path.join(OUT, "mdat.chipdeck-st-test"), "wb") as f:
        f.write(mdat)
    with open(os.path.join(OUT, "smpl.chipdeck-st-test"), "wb") as f:
        f.write(smpl)
    print("mdat %d bytes, smpl %d bytes" % (len(mdat), len(smpl)))


if __name__ == "__main__":
    main()
