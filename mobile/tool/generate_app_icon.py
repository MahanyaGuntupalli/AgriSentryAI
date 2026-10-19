#!/usr/bin/env python3
"""Generate AgriSentry AI app icons from the same leaf+shield+scan design as
the in-app vector logo (single source of truth, no copyrighted assets).

Usage:  python tool/generate_app_icon.py
Writes: assets/branding/agrisentry_icon.png (512x512 source - covers every
        Android launcher density, max required 192px, plus Play Store 512).
"""
import math
import struct
import zlib
from collections import defaultdict
from pathlib import Path

SIZE = 512
PINE = (31, 107, 74)
FOREST = (18, 56, 42)
LEAF_LIGHT = (157, 222, 192)
LEAF = (95, 191, 138)
SKY = (59, 130, 196)
WHITE = (255, 255, 255)


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def quad(x0, y0, cx, cy, x1, y1, n=48):
    pts = []
    for i in range(n + 1):
        t = i / n
        bx = (1 - t) ** 2 * x0 + 2 * (1 - t) * t * cx + t ** 2 * x1
        by = (1 - t) ** 2 * y0 + 2 * (1 - t) * t * cy + t ** 2 * y1
        pts.append((bx, by))
    return pts


# ---- precomputed geometry (normalized 0..1 space) ----
SHIELD_PTS = (
    quad(0.78, 0.52, 0.78, 0.76, 0.50, 0.88, 48)
    + quad(0.50, 0.88, 0.22, 0.76, 0.22, 0.52, 48)
    + [(0.22 + 0.56 * i / 40, 0.14) for i in range(41)]
    + [(0.78, 0.24 + 0.28 * i / 40) for i in range(41)]
    + [(0.22, 0.24 + 0.28 * i / 40) for i in range(41)]
)
LEAF_SEGS = [
    ((0.34, 0.70), (0.22, 0.50), (0.42, 0.32)),
    ((0.42, 0.32), (0.62, 0.16), (0.72, 0.34)),
    ((0.72, 0.34), (0.82, 0.54), (0.60, 0.72)),
    ((0.60, 0.72), (0.47, 0.81), (0.34, 0.70)),
]
LEAF_PTS = [p for seg in LEAF_SEGS for p in quad(*seg[0], *seg[1], *seg[2], 48)]
# bounding boxes for fast rejection
SHIELD_BBOX = (0.20, 0.12, 0.80, 0.90)
LEAF_BBOX = (0.20, 0.14, 0.84, 0.83)
VEIN_PTS = quad(0.37, 0.68, 0.50, 0.54, 0.66, 0.38, 48)
ARC_START = -math.pi * 0.78
ARC_END = ARC_START + math.pi * 0.56
ARC_R = 0.40
DOT_ANGLE = ARC_END
DOT_X = 0.5 + ARC_R * math.cos(DOT_ANGLE)
DOT_Y = 0.5 + ARC_R * math.sin(DOT_ANGLE)


def inside_rounded_rect(x, y, size, radius):
    cx = max(radius, min(x, size - radius))
    cy = max(radius, min(y, size - radius))
    if abs(x - cx) <= radius and abs(y - cy) <= radius:
        if x < radius or x >= size - radius or y < radius or y >= size - radius:
            return (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius
    return True


def nearest_dist(nx, ny, pts, bbox):
    if not (bbox[0] <= nx <= bbox[2] and bbox[1] <= ny <= bbox[3]):
        return 1e9
    return min((nx - px) ** 2 + (ny - py) ** 2 for px, py in pts) ** 0.5


def leaf_inside(nx, ny):
    if not (LEAF_BBOX[0] <= nx <= LEAF_BBOX[2] and LEAF_BBOX[1] <= ny <= LEAF_BBOX[3]):
        return False
    inside = False
    n = len(LEAF_PTS)
    for i in range(n):
        x0, y0 = LEAF_PTS[i]
        x1, y1 = LEAF_PTS[(i + 1) % n]
        if (y0 > ny) != (y1 > ny):
            xint = x0 + (ny - y0) * (x1 - x0) / (y1 - y0)
            if nx < xint:
                inside = not inside
    return inside


def arc_dist(nx, ny):
    dx, dy = nx - 0.5, ny - 0.5
    r = math.hypot(dx, dy)
    if abs(r - ARC_R) > 0.05:
        return 1e9
    a = math.atan2(dy, dx)
    if ARC_START <= a <= ARC_END:
        return abs(r - ARC_R)
    return 1e9


def render():
    stroke = 0.045 / 2
    scan_w = 0.055 / 2
    vein_w = 0.030 / 2
    radius = SIZE * 0.24
    px = bytearray(SIZE * SIZE * 4)
    for y in range(SIZE):
        ny = (y + 0.5) / SIZE
        for x in range(SIZE):
            nx = (x + 0.5) / SIZE
            if not inside_rounded_rect(x + 0.5, y + 0.5, SIZE, radius):
                continue
            t = (nx + ny) / 2
            r, g, b = lerp(PINE, FOREST, t)
            # shield outline
            if nearest_dist(nx, ny, SHIELD_PTS, SHIELD_BBOX) <= stroke:
                r, g, b = lerp(WHITE, LEAF_LIGHT, 0.3)
            # leaf
            li = leaf_inside(nx, ny)
            if li:
                lt = min(max(((nx - 0.28) + (ny - 0.16)) / 1.1, 0), 1)
                r, g, b = lerp(LEAF_LIGHT, LEAF, lt)
            elif nearest_dist(nx, ny, LEAF_PTS, LEAF_BBOX) <= stroke:
                r, g, b = lerp(WHITE, LEAF_LIGHT, 0.3)
            # vein (only on leaf)
            if li:
                vd = nearest_dist(nx, ny, VEIN_PTS, LEAF_BBOX)
                if vd <= vein_w:
                    r, g, b = lerp((r, g, b), FOREST, 0.55)
            # scan arc + head dot
            if arc_dist(nx, ny) <= scan_w:
                r, g, b = SKY
            if math.hypot(nx - DOT_X, ny - DOT_Y) <= 0.040:
                r, g, b = SKY
            i = (y * SIZE + x) * 4
            px[i] = int(r)
            px[i + 1] = int(g)
            px[i + 2] = int(b)
            px[i + 3] = 255
    return bytes(px)


def write_png(path, size, raw):
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    ihdr = struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)
    rows = b''
    for y in range(size):
        rows += b'\x00' + raw[y * size * 4:(y + 1) * size * 4]
    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
           + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_bytes(png)
    print(f'wrote {path} ({len(png)} bytes)')


if __name__ == '__main__':
    write_png('assets/branding/agrisentry_icon.png', SIZE, render())
