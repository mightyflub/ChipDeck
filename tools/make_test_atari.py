#!/usr/bin/env python3
"""Generate tests/data/chipdeck-test.sndh and tests/data/chipdeck-test.ym.

Both are our own work (public domain), so they can live in the repo and CI
without copyright issues.

chipdeck-test.sndh: a tiny SNDH file with a hand-assembled 68000 driver.
  Two subtunes. init sets YM channel A to a steady square wave: subtune 1 at
  tone period 254 (~492 Hz), subtune 2 at period 127 (~984 Hz, an octave up).
  FRMS tag: subtune 1 is 20 s, subtune 2 is 30 s.

chipdeck-test.ym: an uncompressed YM5 file, 10 s at 50 Hz. Channel A
  alternates between tone periods 254 and 190 every 16 frames.

Usage: python3 tools/make_test_atari.py [output-dir]
"""
import os
import struct
import sys


def be16(v):
    return struct.pack(">H", v)


def be32(v):
    return struct.pack(">I", v)


def make_sndh():
    tags = (b"TITL" + b"ChipDeck Test SNDH\0"
            + b"COMM" + b"ChipDeck\0"
            + b"YEAR" + b"2026\0"
            + b"##02"
            + b"TC50\0"
            + b"FRMS" + be32(20 * 50) + be32(30 * 50)
            + b"HDNS")
    header_len = 16 + len(tags)
    if header_len & 1:
        tags += b"\0"
        header_len += 1

    # 68000 machine code. d0 = subtune (1-based) on entry to init.
    init = bytes.fromhex(
        "41F8 8800"        # lea     $ffff8800.w,a0   ; YM select/data ports
        "10BC 0007"        # move.b  #7,(a0)          ; mixer
        "117C 003E 0002"   # move.b  #$3e,2(a0)       ; tone A on, rest off
        "10BC 0008"        # move.b  #8,(a0)          ; volume A
        "117C 000F 0002"   # move.b  #15,2(a0)
        "10BC 0001"        # move.b  #1,(a0)          ; period A high
        "117C 0000 0002"   # move.b  #0,2(a0)
        "10BC 0000"        # move.b  #0,(a0)          ; period A low
        "B07C 0002"        # cmp.w   #2,d0
        "6708"             # beq.s   .hi
        "117C 00FE 0002"   # move.b  #$fe,2(a0)       ; subtune 1: 254
        "6006"             # bra.s   .done
        "117C 007F 0002"   # .hi: move.b #$7f,2(a0)   ; subtune 2: 127
        "4E75"             # .done: rts
        .replace(" ", ""))
    exit_ = bytes.fromhex("4E75")  # rts
    play = bytes.fromhex("4E75")   # rts (sound is static, nothing to do)

    init_off = header_len
    exit_off = init_off + len(init)
    play_off = exit_off + len(exit_)

    def bra_w(at, target):
        return be16(0x6000) + be16((target - (at + 2)) & 0xFFFF)

    out = (bra_w(0, init_off) + bra_w(4, exit_off) + bra_w(8, play_off)
           + b"SNDH" + tags + init + exit_ + play)
    assert len(out) & 1 == 0
    return out


def make_ym():
    frames = 10 * 50
    regs = []  # one 16-byte register frame per 50 Hz tick
    for f in range(frames):
        period = 254 if (f // 16) % 2 == 0 else 190
        r = [0] * 16
        r[0] = period & 0xFF
        r[1] = period >> 8
        r[7] = 0x3E          # mixer: tone A only
        r[8] = 15            # volume A
        r[13] = 0xFF         # 0xFF = do not retrigger envelope
        regs.append(r)
    # Interleaved: all frames of register 0, then register 1, ...
    data = bytes(regs[f][reg] for reg in range(16) for f in range(frames))
    out = (b"YM5!" + b"LeOnArD!"
           + be32(frames)
           + be32(1)          # attributes: interleaved
           + be16(0)          # digidrums
           + be32(2000000)    # YM clock (Atari ST)
           + be16(50)         # player rate
           + be32(0)          # loop frame
           + be16(0)          # extra data size
           + b"ChipDeck Test YM\0" + b"ChipDeck\0" + b"public domain\0"
           + data + b"End!")
    return out


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "..", "tests", "data")
    for name, data in (("chipdeck-test.sndh", make_sndh()),
                       ("chipdeck-test.ym", make_ym())):
        path = os.path.join(out_dir, name)
        with open(path, "wb") as f:
            f.write(data)
        print(f"wrote {path} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
