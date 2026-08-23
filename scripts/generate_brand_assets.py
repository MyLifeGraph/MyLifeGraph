#!/usr/bin/env python3
"""Generate deterministic MyLifeGraph PNG brand assets from the 24px mark."""

from __future__ import annotations

import binascii
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DARK = (8, 17, 15, 255)
MINT = (105, 224, 189, 255)


def _blend(target: list[int], color: tuple[int, int, int, int], alpha: float) -> None:
    inverse = 1 - alpha
    target[0] = round(target[0] * inverse + color[0] * alpha)
    target[1] = round(target[1] * inverse + color[1] * alpha)
    target[2] = round(target[2] * inverse + color[2] * alpha)
    target[3] = 255


def _distance_to_segment(
    px: float,
    py: float,
    ax: float,
    ay: float,
    bx: float,
    by: float,
) -> float:
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def _curve(
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    p3: tuple[float, float],
    steps: int = 80,
) -> list[tuple[float, float]]:
    points = []
    for index in range(steps + 1):
        t = index / steps
        u = 1 - t
        points.append(
            (
                u**3 * p0[0]
                + 3 * u * u * t * p1[0]
                + 3 * u * t * t * p2[0]
                + t**3 * p3[0],
                u**3 * p0[1]
                + 3 * u * u * t * p1[1]
                + 3 * u * t * t * p2[1]
                + t**3 * p3[1],
            )
        )
    return points


def _render(size: int, safe_scale: float) -> bytes:
    supersample = 4
    canvas_size = size * supersample
    pixels = [list(DARK) for _ in range(canvas_size * canvas_size)]
    mark_size = canvas_size * safe_scale
    origin = (canvas_size - mark_size) / 2
    scale = mark_size / 24

    first = _curve((4, 18), (7, 18), (7.6, 14.2), (10, 12), 48)
    second = _curve((10, 12), (12.4, 9.8), (12.5, 6), (17, 6), 48)
    branch = _curve((10, 12), (13.2, 12), (14.4, 15), (19, 15), 48)
    paths = [first + second[1:], branch]
    transformed = [
        [(origin + x * scale, origin + y * scale) for x, y in path]
        for path in paths
    ]
    stroke = 2 * scale
    nodes = [
        (origin + x * scale, origin + y * scale, 2 * scale)
        for x, y in ((4, 18), (17, 6), (19, 15))
    ]

    padding = stroke / 2 + 1
    for path in transformed:
        for (ax, ay), (bx, by) in zip(path, path[1:]):
            min_x = max(0, math.floor(min(ax, bx) - padding))
            max_x = min(canvas_size - 1, math.ceil(max(ax, bx) + padding))
            min_y = max(0, math.floor(min(ay, by) - padding))
            max_y = min(canvas_size - 1, math.ceil(max(ay, by) + padding))
            for y in range(min_y, max_y + 1):
                for x in range(min_x, max_x + 1):
                    distance = _distance_to_segment(
                        x + 0.5,
                        y + 0.5,
                        ax,
                        ay,
                        bx,
                        by,
                    )
                    coverage = max(
                        0.0,
                        min(1.0, stroke / 2 + 0.75 - distance),
                    )
                    if coverage:
                        _blend(pixels[y * canvas_size + x], MINT, coverage)

    for cx, cy, radius in nodes:
        node_padding = radius + 1
        min_x = max(0, math.floor(cx - node_padding))
        max_x = min(canvas_size - 1, math.ceil(cx + node_padding))
        min_y = max(0, math.floor(cy - node_padding))
        max_y = min(canvas_size - 1, math.ceil(cy + node_padding))
        for y in range(min_y, max_y + 1):
            for x in range(min_x, max_x + 1):
                coverage = max(
                    0.0,
                    min(
                        1.0,
                        radius
                        + 0.75
                        - math.hypot(x + 0.5 - cx, y + 0.5 - cy),
                    ),
                )
                if coverage:
                    _blend(pixels[y * canvas_size + x], MINT, coverage)

    rows = bytearray()
    for target_y in range(size):
        rows.append(0)
        for target_x in range(size):
            totals = [0, 0, 0, 0]
            for offset_y in range(supersample):
                for offset_x in range(supersample):
                    source = pixels[
                        (target_y * supersample + offset_y) * canvas_size
                        + target_x * supersample
                        + offset_x
                    ]
                    for channel in range(4):
                        totals[channel] += source[channel]
            count = supersample * supersample
            rows.extend(round(value / count) for value in totals)
    return _png(size, size, bytes(rows))


def _chunk(name: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + name
        + data
        + struct.pack(">I", binascii.crc32(name + data) & 0xFFFFFFFF)
    )


def _png(width: int, height: int, rows: bytes) -> bytes:
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", header)
        + _chunk(b"IDAT", zlib.compress(rows, 9))
        + _chunk(b"IEND", b"")
    )


def _write(relative: str, size: int, safe_scale: float) -> None:
    target = ROOT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(_render(size, safe_scale))
    print(f"{target.relative_to(ROOT)} ({size}x{size})")


def main() -> None:
    for name, size in (("Icon-192.png", 192), ("Icon-512.png", 512)):
        _write(f"apps/mobile/web/icons/{name}", size, 0.66)
    for name, size in (
        ("Icon-maskable-192.png", 192),
        ("Icon-maskable-512.png", 512),
    ):
        _write(f"apps/mobile/web/icons/{name}", size, 0.50)
    _write("apps/mobile/web/favicon.png", 32, 0.72)

    android_sizes = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    for density, size in android_sizes.items():
        _write(
            f"apps/mobile/android/app/src/main/res/mipmap-{density}/ic_launcher.png",
            size,
            0.66,
        )


if __name__ == "__main__":
    main()
