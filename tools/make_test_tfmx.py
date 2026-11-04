#!/usr/bin/env python3
"""Generate ChipDeck's own public-domain TFMX test tune, as an Amiga-style
file pair: tests/data/mdat.chipdeck-test (music data) and
tests/data/smpl.chipdeck-test (samples).

Unpacked TFMX layout: "TFMX-SONG " header, text at $10, song start/end
steps at $100/$140, song speeds at $180, pattern pointers at $400, macro
pointers at $600, track steps (16 bytes each, 8 tracks) from $800, then the
patterns and macros.

Song 1 = steps 0-1: track 1 plays a square-wave melody (macro 0) on Paula
voice 0, track 2 a saw bass (macro 1) on voice 1. Step 1 repeats both
patterns transposed up a fifth.
Song 2 = step 2: only the bass pattern, so voice 0 stays silent.
Speed 5 = a pattern row every 6 frames (120 ms at 50 Hz).
Run: python3 tools/make_test_tfmx.py
"""
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "tests", "data")


def be16(v):
    return struct.pack(">H", v & 0xFFFF)


def be32(v):
    return struct.pack(">I", v & 0xFFFFFFFF)


def note_wait(note, macro, volume, channel, wait):
    """Pattern note with wait: aa = $80 | note, ee = rows to wait."""
    return bytes([0x80 | note, macro, (volume << 4) | channel, wait])


def melody():
    p = b""
    for n, w in [(0x18, 3), (0x1C, 3), (0x1F, 3), (0x24, 3),
                 (0x1F, 3), (0x1C, 3), (0x18, 7)]:
        p += note_wait(n, 0, 15, 0, w)
    return p + bytes([0xF0, 0, 0, 0])   # end of pattern -> next step


def bass():
    p = b""
    for n in [0x0C, 0x0C, 0x13, 0x13]:
        p += note_wait(n, 1, 15, 1, 7)
    return p + bytes([0xF0, 0, 0, 0])


def macro(begin, length_words):
    m = b""
    m += bytes([0x00, 0x00, 0x00, 0x00])          # DMAoff + reset
    m += bytes([0x02]) + be32(begin)[1:]          # SetBegin (offset in smpl)
    m += bytes([0x03, 0x00]) + be16(length_words)  # SetLen (words)
    m += bytes([0x0D, 0x00, 0xFE, 0x10])          # AddVol+Note: note, vol 15*3+16
    m += bytes([0x01, 0x00, 0x00, 0x00])          # DMAon
    m += bytes([0x07, 0x00, 0x00, 0x00])          # Stop (sample keeps looping)
    return m


def build():
    # Samples: TFMX clears the first 4 bytes of the sample data (silence for
    # one-shot sounds), so the real samples start at offset 4.
    square = bytes([0x50] * 16 + [0xB0] * 16)                 # 32 bytes
    saw = bytes(((i * 4 - 128) & 0xFF) for i in range(64))    # 64 bytes
    smpl = bytes(4) + square + saw
    sq_ofs, saw_ofs = 4, 4 + len(square)

    hdr = bytearray(0x800)
    hdr[0:10] = b"TFMX-SONG "
    text = b"ChipDeck TFMX test (public domain)"
    hdr[0x10:0x10 + len(text)] = text
    # Song 0: steps 0..1, speed 5. Song 1: step 2..2, speed 5.
    hdr[0x100:0x102] = be16(0)
    hdr[0x140:0x142] = be16(1)
    hdr[0x180:0x182] = be16(5)
    hdr[0x102:0x104] = be16(2)
    hdr[0x142:0x144] = be16(2)
    hdr[0x182:0x184] = be16(5)
    # Unused songs 2..31 point at step 0..0 and are dropped as duplicates.

    steps = b""
    off = bytes([0xFF, 0x00])
    steps += bytes([0, 0, 1, 0]) + off * 6           # step 0
    steps += bytes([0, 7, 1, 7]) + off * 6           # step 1: +7 semitones
    steps += bytes([1, 0]) + off * 7                 # step 2 (song 2)
    steps += be16(0xEFFE) + be16(0) + bytes(12)      # step 3: STOP

    patterns = [melody(), bass()]
    patt_base = 0x800 + len(steps)
    body = b""
    patt_ofs = []
    for p in patterns:
        patt_ofs.append(patt_base + len(body))
        body += p
    macros = [macro(sq_ofs, len(square) // 2), macro(saw_ofs, len(saw) // 2)]
    mac_ofs = []
    for m in macros:
        mac_ofs.append(patt_base + len(body))
        body += m
    for i, o in enumerate(patt_ofs):
        hdr[0x400 + i * 4:0x404 + i * 4] = be32(o)
    for i, o in enumerate(mac_ofs):
        hdr[0x600 + i * 4:0x604 + i * 4] = be32(o)
    mdat = bytes(hdr) + steps + body
    return mdat, smpl


def main():
    mdat, smpl = build()
    with open(os.path.join(OUT, "mdat.chipdeck-test"), "wb") as f:
        f.write(mdat)
    with open(os.path.join(OUT, "smpl.chipdeck-test"), "wb") as f:
        f.write(smpl)
    print("mdat %d bytes, smpl %d bytes" % (len(mdat), len(smpl)))


if __name__ == "__main__":
    main()
