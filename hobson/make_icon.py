#!/usr/bin/env python3
"""Draw the JCB Remote icon (teal tile, white H) as PNG and ICO."""

import struct
import zlib
from pathlib import Path

TEAL = (14, 107, 103, 255)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


def pixel(size, x, y, foreground_only):
    pad = size * 0.16
    if foreground_only:
        if x < pad or y < pad or x >= size - pad or y >= size - pad:
            return CLEAR
    else:
        radius = size * 0.22
        dx = min(x, size - 1 - x)
        dy = min(y, size - 1 - y)
        if dx < radius and dy < radius:
            if (radius - dx) ** 2 + (radius - dy) ** 2 > radius ** 2:
                return CLEAR
    # H strokes, centered.
    cx, cy = size / 2, size / 2
    arm = size * 0.11
    half_w = size * 0.28
    half_h = size * 0.32
    left = cx - half_w
    right = cx + half_w
    top = cy - half_h
    bot = cy + half_h
    in_bar = abs(y - cy) <= arm and left <= x <= right
    in_stem = top <= y <= bot and (abs(x - left) <= arm or abs(x - right) <= arm)
    if in_bar or in_stem:
        return WHITE
    return CLEAR if foreground_only else TEAL


def png(size, foreground_only):
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            raw.extend(pixel(size, x, y, foreground_only))

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(
        b"IDAT", zlib.compress(bytes(raw), 9)
    ) + chunk(b"IEND", b"")


def ico(images):
    header = struct.pack("<HHH", 0, 1, len(images))
    entries = b""
    offset = 6 + 16 * len(images)
    blobs = b""
    for size, data in images:
        entries += struct.pack(
            "<BBBBHHII",
            size if size < 256 else 0,
            size if size < 256 else 0,
            0,
            0,
            1,
            32,
            len(data),
            offset,
        )
        offset += len(data)
        blobs += data
    return header + entries + blobs


def main():
    root = Path(__file__).resolve().parents[1]
    full = {size: png(size, False) for size in (48, 72, 96, 144, 192, 256)}
    mark = {size: png(size, True) for size in (48, 72, 96, 144, 192)}
    res = root / "flutter/android/app/src/main/res"
    folders = {
        48: "mipmap-mdpi",
        72: "mipmap-hdpi",
        96: "mipmap-xhdpi",
        144: "mipmap-xxhdpi",
        192: "mipmap-xxxhdpi",
    }
    for size, folder in folders.items():
        dest = res / folder
        dest.mkdir(parents=True, exist_ok=True)
        (dest / "ic_launcher.png").write_bytes(full[size])
        (dest / "ic_launcher_round.png").write_bytes(full[size])
        (dest / "ic_launcher_foreground.png").write_bytes(mark[size])
        (dest / "ic_stat_logo.png").write_bytes(mark[size])
    icon = ico([(32, png(32, False)), (48, full[48]), (256, full[256])])
    (root / "flutter/windows/runner/resources/app_icon.ico").write_bytes(icon)
    print("wrote launcher pngs and app_icon.ico")


if __name__ == "__main__":
    main()
