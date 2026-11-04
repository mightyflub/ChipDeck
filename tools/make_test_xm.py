#!/usr/bin/env python3
"""Generate tests/data/chipdeck-test.xm, ChipDeck's own public-domain test
module in Fasttracker 2 (.xm) format: 6 channels, two looped synthesised
instruments (square and saw), one 32-row pattern.

Channels 1-5 start a note on row 0; channel 6 only starts on row 16
(1.92 s in at speed 6, 125 BPM), so tests can check that per-channel
scopes keep channels apart.
Run: python3 tools/make_test_xm.py
"""
import os
import struct

CHANNELS = 6
ROWS = 32


def delta(data):
    out, prev = bytearray(), 0
    for v in data:
        out.append((v - prev) & 0xFF)
        prev = v
    return bytes(out)


def instrument(name, wave):
    smp = struct.pack("<IIIBbBBbB22s", len(wave), 0, len(wave), 48, 0, 1,
                      0x80, 0, 0, name.encode().ljust(22, b"\0"))
    head = struct.pack("<I22sBH", 263, name.encode().ljust(22, b"\0"), 0, 1)
    head += struct.pack("<I", 40) + bytes(96) + bytes(48) + bytes(48)
    head += bytes(14) + struct.pack("<H", 0) + bytes(22)
    assert len(head) == 263
    return head + smp + delta(wave)


def main():
    square = [0x40] * 16 + [0xC0] * 16
    saw = [(i * 8 - 128) & 0xFF for i in range(32)]

    rows = []
    for r in range(ROWS):
        for c in range(CHANNELS):
            if (r == 0 and c < 5) or (r == 16 and c == 5):
                rows.append(bytes([0x80 | 0x03, 49 + c * 2, c % 2 + 1]))
            else:
                rows.append(b"\x80")
    pdata = b"".join(rows)
    pattern = struct.pack("<IBHH", 9, 0, ROWS, len(pdata)) + pdata

    header = b"Extended Module: " + b"ChipDeck XM test".ljust(20, b"\0")
    header += b"\x1a" + b"ChipDeck".ljust(20, b" ")
    header += struct.pack("<H", 0x0104)
    orders = bytes([0]) + bytes(255)
    body = struct.pack("<HHHHHHHH", 1, 0, CHANNELS, 1, 2, 1, 6, 125) + orders
    header += struct.pack("<I", 4 + len(body)) + body

    data = header + pattern + instrument("square", square) + instrument("saw", saw)
    path = os.path.join(os.path.dirname(__file__), "..", "tests", "data",
                        "chipdeck-test.xm")
    with open(path, "wb") as f:
        f.write(data)
    print(f"wrote {os.path.normpath(path)} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
