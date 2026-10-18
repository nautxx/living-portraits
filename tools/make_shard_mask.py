#!/usr/bin/env python3
"""Build media/shard.tga: the mask for warlock soul shard pixels (modules/classResource.lua).

A gem like Blizzard's soul shard: flat top, cut top corners, sides narrowing to a point at the
bottom. White with the shape in the alpha channel (like TempPortraitAlphaMask), filling the whole
square: the texture stretches it to the shard's frame (taller than wide).
Usage: python3 tools/make_shard_mask.py   (no dependencies)
"""
import os
import struct

SIZE = 128
SAMPLES = 4  # per axis, for anti-aliased edges
# Polygon in 0..1 coordinates, y down: top edge, cut corners, point at the bottom.
SHAPE = [(0.25, 0.0), (0.75, 0.0), (1.0, 0.25), (0.5, 1.0), (0.0, 0.25)]


def inside(x, y):
    # Even-odd ray cast.
    hit = False
    n = len(SHAPE)
    for i in range(n):
        x1, y1 = SHAPE[i]
        x2, y2 = SHAPE[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            hit = not hit
    return hit


def main():
    pixels = bytearray()
    for py in range(SIZE):  # top row first (header sets top-left origin)
        for px in range(SIZE):
            covered = 0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = (px + (sx + 0.5) / SAMPLES) / SIZE
                    y = (py + (sy + 0.5) / SAMPLES) / SIZE
                    covered += inside(x, y)
            alpha = round(255 * covered / (SAMPLES * SAMPLES))
            pixels += bytes((255, 255, 255, alpha))  # BGRA
    # Uncompressed true-color TGA, 32 bpp, 8 alpha bits, top-left origin (like media/vignette.tga).
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    out = os.path.join(os.path.dirname(__file__), "..", "media", "shard.tga")
    with open(out, "wb") as f:
        f.write(header + pixels)
    print("Built " + os.path.normpath(out))


if __name__ == "__main__":
    main()
