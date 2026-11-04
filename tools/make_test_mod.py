#!/usr/bin/env python3
"""Generate tests/data/chipdeck-test.mod, ChipDeck's own public-domain test
module: a 4-channel Protracker (M.K.) file with tiny synthesised samples.

Song layout (speed 6, 125 BPM, so one row is 120 ms):
  order 0 (pattern 0): ch1 square C-2 on row 0 (held), ch2 saw every 8 rows,
                       ch3 noise drum every 4 rows, ch4 silent.
  order 1 (pattern 1): same, plus ch4 sine A-2; row 63 jumps back to order 0
                       (B00), so the main song is orders 0-1 and loops.
  order 2 (pattern 2): never reached from the main song, so libxmp finds it
                       as a second sequence ("subtune 2"); ch1 square only.
Run: python3 tools/make_test_mod.py
"""
import math
import os
import random
import struct

PERIOD = {"C-2": 428, "A-2": 254, "C-3": 214, "G-2": 285}


def sample_header(name, data, volume, loop):
    words = len(data) // 2
    ls, ll = (0, words) if loop else (0, 1)
    return struct.pack(">22sHBBHH", name.encode().ljust(22, b"\0"), words, 0,
                       volume, ls, ll)


def note(sample, period, eff=0, param=0):
    return bytes([(sample & 0xF0) | (period >> 8), period & 0xFF,
                  ((sample & 0x0F) << 4) | eff, param])


EMPTY = bytes(4)


def pattern(cells):
    """cells: dict (row, ch) -> 4 bytes."""
    out = bytearray()
    for r in range(64):
        for c in range(4):
            out += cells.get((r, c), EMPTY)
    return bytes(out)


def main():
    square = bytes([0x60] * 16 + [0xA0] * 16)                      # 32 bytes
    saw = bytes(((i * 4) - 128) & 0xFF for i in range(64))         # 64 bytes
    rnd = random.Random(1234)
    drum = bytes(int(rnd.randint(-100, 100) * (1 - i / 2000)) & 0xFF
                 for i in range(2000))                              # one-shot
    sine = bytes(int(100 * math.sin(2 * math.pi * i / 32)) & 0xFF
                 for i in range(32))
    samples = [("square", square, 48, True), ("saw", saw, 40, True),
               ("noise drum", drum, 64, False), ("sine", sine, 64, True)]

    header = b"ChipDeck test".ljust(20, b"\0")
    for i in range(31):
        if i < len(samples):
            header += sample_header(*samples[i])
        else:
            header += sample_header("", b"", 0, False)
    orders = [0, 1, 2]
    header += bytes([len(orders), 127])
    header += bytes(orders + [0] * (128 - len(orders)))
    header += b"M.K."

    p0 = {(0, 0): note(1, PERIOD["C-2"])}
    for r in range(0, 64, 8):
        p0[(r, 1)] = note(2, PERIOD["G-2"])
    for r in range(0, 64, 4):
        p0[(r, 2)] = note(3, PERIOD["C-3"])
    p1 = dict(p0)
    p1[(0, 3)] = note(4, PERIOD["A-2"])
    p1[(63, 3)] = note(0, 0, 0xB, 0)   # jump to order 0
    p2 = {(0, 0): note(1, PERIOD["A-2"]), (31, 0): note(0, 0, 0xB, 2)}
    # Pattern 2 loops on itself (B02), a separate 32-row sequence.

    body = pattern(p0) + pattern(p1) + pattern(p2)
    data = header + body + square + saw + drum + sine
    path = os.path.join(os.path.dirname(__file__), "..", "tests", "data",
                        "chipdeck-test.mod")
    with open(path, "wb") as f:
        f.write(data)
    print(f"wrote {os.path.normpath(path)} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
