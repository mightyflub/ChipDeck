#!/usr/bin/env python3
"""Generate tests/data/chipdeck-test.sid, a tiny PSID tune written for ChipDeck.

It is our own work (public domain), so it can live in the repo and CI without
copyright issues. Two subtunes, each a pulse wave alternating between two
notes every 16 frames. Subtune 1 is lower than subtune 2.

Usage: python3 tools/make_test_sid.py [output.sid]
"""
import struct
import sys

LOAD = 0x1000


def assemble():
    code = bytearray()
    labels = {}
    fixups = []  # (offset, label) for absolute 16-bit references

    def emit(*b):
        code.extend(b)

    def abs_(op, label):
        emit(op, 0, 0)
        fixups.append((len(code) - 2, label))

    def sta(addr):
        emit(0x8D, addr & 0xFF, addr >> 8)

    def lda_imm(v):
        emit(0xA9, v)

    # init: A = subtune (0-based)
    labels["init"] = LOAD + len(code)
    emit(0xAA)                      # TAX
    lda_imm(0x0F); sta(0xD418)      # volume max
    lda_imm(0x09); sta(0xD405)      # AD
    lda_imm(0xF0); sta(0xD406)      # SR
    lda_imm(0x00); sta(0xD402)      # PW lo
    lda_imm(0x08); sta(0xD403)      # PW hi (50%)
    lda_imm(0x00); sta(0xD400)      # freq lo
    abs_(0xBD, "freqtab")           # LDA freqtab,X
    abs_(0x8D, "base")              # STA base
    sta(0xD401)                     # freq hi
    lda_imm(0x41); sta(0xD404)      # pulse + gate
    lda_imm(0x00)
    abs_(0x8D, "counter")           # STA counter
    emit(0x60)                      # RTS

    # play: called once per frame
    labels["play"] = LOAD + len(code)
    abs_(0xEE, "counter")           # INC counter
    abs_(0xAD, "counter")           # LDA counter
    emit(0x29, 0x10)                # AND #$10
    emit(0x4A, 0x4A)                # LSR LSR  -> 0 or 4
    emit(0x18)                      # CLC
    abs_(0x6D, "base")              # ADC base
    sta(0xD401)                     # freq hi
    emit(0x60)                      # RTS

    labels["freqtab"] = LOAD + len(code)
    emit(0x10, 0x20)
    labels["base"] = LOAD + len(code)
    emit(0x00)
    labels["counter"] = LOAD + len(code)
    emit(0x00)

    for off, label in fixups:
        addr = labels[label]
        code[off] = addr & 0xFF
        code[off + 1] = addr >> 8
    return bytes(code), labels


def psid(code, labels):
    def text(s):
        return s.encode("latin-1")[:32].ljust(32, b"\0")

    header = struct.pack(
        ">4sHHHHHHHI32s32s32sHBBBB",
        b"PSID", 2, 0x7C,
        0,                    # load address taken from data
        labels["init"], labels["play"],
        2, 1,                 # songs, start song
        0,                    # speed: VBI for all songs
        text("ChipDeck Test Tune"),
        text("ChipDeck contributors"),
        text("2026 Public Domain"),
        0x0014,               # flags: PAL, 6581
        0, 0, 0, 0,
    )
    assert len(header) == 0x7C
    return header + struct.pack("<H", LOAD) + code


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "tests/data/chipdeck-test.sid"
    code, labels = assemble()
    with open(out, "wb") as f:
        f.write(psid(code, labels))
    print(f"wrote {out}: init ${labels['init']:04X} play ${labels['play']:04X}")
