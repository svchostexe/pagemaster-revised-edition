"""genstamp3.py: stamp v5 art - the whole stamp sheared to the REVISED banner's slope (1 px up per 8 px to the right).

Sprites cannot rotate, so each 16 px wide column sits 2 px higher than the one to its left and the graphics carry the matching 1 px
per 8 px edge slope (top edge of the upper wood row, bottom edge of the rubber pad row), so the staircase between columns closes up
into a straight tilted edge. The handle leans left by 1 px per 8 px of height. Ten 16x16 graphics (4 tiles each, borrowed font glyph tiles):
  0 T0 wood, sloped top   1 TLC top-left cap (end grain)   2 TRC top-right cap   3 B0 wood body   4 B1 wood body variant
  5 BC body end cap (flipped for the right end)   6 PAD wood sliver + black foam + red rubber, sloped bottom
  7 HB_TOP handle bulb top (left half)   8 HS bulb body + shoulder (left half)   9 HN neck
Writes patches/stamp_art.inc, stamp_parts.inc, stamp_defs.inc and shots/stamp_preview.png.
"""
import math
import os
import random
import subprocess

PAL = {
    1: (236, 208, 150), 2: (220, 186, 124), 3: (196, 158, 98), 4: (150, 112, 62), 5: (108, 76, 40),
    6: (22, 20, 20), 7: (74, 70, 70), 8: (176, 170, 164), 9: (38, 32, 30),
    10: (206, 56, 44), 11: (142, 36, 30), 12: (232, 96, 80),
}
TILES = [0x02, 0x0A, 0x22, 0x24, 0x26, 0x40, 0x48, 0x4E, 0x60, 0x62]   # borrowed glyph tile per graphic
PLATE_Y = 117
COLS, X0, DROP = 12, 36, 2          # 2 px of rise per 16 px column = 1 px per 8 px


def bgr555(rgb):
    r, g, b = [c >> 3 for c in rgb]
    return (b << 10) | (g << 5) | r


def blank():
    return [[0] * 16 for _ in range(16)]


def e(x):                              # edge offset at column x of a sprite: 2 for the left half, 1 for the right half
    return DROP - (x // 8)


def wood_fill(seed, top_slope=False, cap=None):
    rnd = random.Random(seed)
    g = blank()
    for y in range(16):
        for x in range(16):
            g[y][x] = 1
    for y in range(16):
        if rnd.random() < 0.55:
            x = rnd.randrange(0, 12)
            ln = rnd.randrange(4, 16 - x + 1)
            col = 2 if rnd.random() < 0.6 else 3
            for i in range(ln):
                if x + i < 16:
                    g[y][x + i] = col
    for _ in range(3):
        y, x = rnd.randrange(16), rnd.randrange(12)
        for i in range(rnd.randrange(2, 5)):
            g[y][min(15, x + i)] = 3
    if cap == "L":
        for y in range(16):
            for x in range(4):
                g[y][x] = 4 if (y + x) % 3 else 5
            g[y][4] = 3
    if cap == "R":
        for y in range(16):
            for x in range(12, 16):
                g[y][x] = 4 if (y + x) % 3 else 5
            g[y][11] = 3
    if top_slope:
        for x in range(16):
            for y in range(e(x)):
                g[y][x] = 0
    return g


def pad(seed):
    rnd = random.Random(seed)
    g = blank()
    for x in range(16):
        w = e(x)                        # wood sliver that closes the slope above the foam
        for y in range(w):
            g[y][x] = 4 if y == w - 1 else 3
        for y in range(w, w + 2):
            g[y][x] = 9
        for y in range(w + 2, w + 9):
            r = rnd.random()
            g[y][x] = 12 if r < 0.08 else (11 if r < 0.2 else 10)
        g[w + 8][x] = 11
    return g


def handle_top():
    g = blank()
    r = 8.0
    for y in range(16):
        cx = 0.0
        if y < r:
            cx = r - math.sqrt(max(0.0, r * r - (r - y) ** 2))
        xi = int(round(cx))
        for x in range(16):
            if x >= cx:
                g[y][x] = 6
        if y >= 1 and xi + 1 < 16:
            g[y][xi + 1] = 7
        if y >= 4:
            for k in (5, 6):
                g[y][xi + k] = 7
            if y <= 9:
                g[y][xi + 5] = 8
        if y == 0:
            for x in range(6, 16):
                g[y][x] = 7 if g[y][x] else 0
    return g


def handle_shoulder():
    g = blank()
    for y in range(16):
        edge = 0.0 if y < 6 else 10.0 * (((y - 6) / 9.0) ** 1.6)
        xe = int(round(edge))
        for x in range(16):
            if x >= xe:
                g[y][x] = 6
        if xe + 1 < 16:
            g[y][xe + 1] = 7
        if y <= 12 and xe + 5 < 16:
            g[y][xe + 5] = 7
            if y <= 8:
                g[y][xe + 5] = 8
    return g


def handle_neck():
    g = blank()
    for y in range(16):
        hw = 6.0 - 0.8 * math.sin(math.pi * y / 15.0)
        if y > 11:
            hw += (y - 11) * 0.7
        for x in range(16):
            if abs((x + 0.5) - 8.0) <= hw:
                g[y][x] = 6
        left = int(math.ceil(8.0 - hw))
        if 0 <= left + 2 < 16 and g[y][left + 2]:
            g[y][left + 2] = 7
        if y in (2, 3, 4, 5) and left + 2 < 16:
            g[y][left + 2] = 8
        right = int(math.floor(8.0 + hw)) - 1
        if 0 <= right < 16 and g[y][right]:
            g[y][right] = 9
    for y in range(16):                   # lean left going up: 1 px per 8 rows inside the sprite (rows above sit 2 px further left)
        sh = (15 - y) // 8
        if sh:
            g[y] = g[y][sh:] + [0] * sh
    return g


GRAPHICS = [wood_fill(11, top_slope=True), wood_fill(5, top_slope=True, cap="L"), wood_fill(8, top_slope=True, cap="R"),
            wood_fill(23), wood_fill(37), wood_fill(5, cap="L"), pad(3),
            handle_top(), handle_shoulder(), handle_neck()]


def tile(g, tx, ty):
    bp = [[0] * 8 for _ in range(4)]
    for r in range(8):
        for c in range(8):
            v = g[ty * 8 + r][tx * 8 + c]
            for p in range(4):
                if v >> p & 1:
                    bp[p][r] |= 0x80 >> c
    out = []
    for r in range(8):
        out += [bp[0][r], bp[1][r]]
    for r in range(8):
        out += [bp[2][r], bp[3][r]]
    return out


data = []
for g in GRAPHICS:
    for (tx, ty) in ((0, 0), (1, 0), (0, 1), (1, 1)):
        data += tile(g, tx, ty)

# ---- layout: (x, y relative to PLATE_Y, graphic, hflip); handle first so it draws in front ----
sprites = []
hx = X0 + 96
for ry, dx, gi in ((-60, -6, 7), (-44, -4, 8)):          # bulb pair, shoulder pair (right half = flipped copy)
    sprites.append((hx - 16 + dx, ry, gi, False))
    sprites.append((hx + dx, ry, gi, True))
sprites.append((hx - 8 - 2, -28, 9, False))               # neck (pre-sheared graphic, rows above sit 2 px further left)
sprites.append((hx - 8, -12, 9, False))
for c in range(COLS):                                     # upper wood row (sloped top), lower wood row, pad row
    y0 = 11 - DROP * c
    if c == 0:
        top, body = 1, 5
        sprites.append((X0, y0, top, False))
        sprites.append((X0, y0 + 16, body, False))
    elif c == COLS - 1:
        sprites.append((X0 + 16 * c, y0, 2, False))
        sprites.append((X0 + 16 * c, y0 + 16, 5, True))
    else:
        sprites.append((X0 + 16 * c, y0, 0, False))
        sprites.append((X0 + 16 * c, y0 + 16, 3 + ((c * 3 + (c >> 2)) % 2), False))
    sprites.append((X0 + 16 * c, y0 + 32, 6, False))

here = os.path.dirname(os.path.abspath(__file__))
lines = ["; generated by genstamp3.py", "stamp_gfx:                      ; 10 graphics x 128 bytes: T0 TLC TRC B0 B1 BC PAD HB_TOP HS HN"]
for i in range(0, len(data), 16):
    lines.append("    db " + ",".join("$%02X" % b for b in data[i:i + 16]))
lines.append("stamp_pal:                      ; OBJ palette 5, indices 1-12 (BGR555)")
lines.append("    dw " + ",".join("$%04X" % bgr555(PAL[i]) for i in range(1, 13)))
open(os.path.join(here, "patches", "stamp_art.inc"), "w", newline="\n").write("\n".join(lines) + "\n")
rows = ["    dw %d, $%04X, $%04X" % (x, y & 0xFFFF, ((0x3A | (0x40 if fl else 0)) << 8) | TILES[gi]) for (x, y, gi, fl) in sprites]
open(os.path.join(here, "patches", "stamp_parts.inc"), "w", newline="\n").write(
    "; generated by genstamp3.py: x, y relative to !PLATE_Y, (attr<<8)|tile\nstamp_parts:\n" + "\n".join(rows) + "\n")
open(os.path.join(here, "patches", "stamp_defs.inc"), "w", newline="\n").write(
    "; generated by genstamp3.py\n!PLATE_Y = %d\n!STAMP_PARTS = %d\n" % (PLATE_Y, len(sprites)))
print(len(sprites), "sprites,", len(data), "graphic bytes")

# ---- preview ----
W, H, S = 256, 150, 4
img = [[(60, 52, 70)] * (W * S) for _ in range(H * S)]
for (x, y, gi, fl) in sprites:
    g = GRAPHICS[gi]
    for py in range(16):
        for px in range(16):
            v = g[py][15 - px if fl else px]
            if v:
                for sy in range(S):
                    for sx in range(S):
                        yy, xx = (y + PLATE_Y - 40 + py) * S + sy, (x + px) * S + sx
                        if 0 <= yy < H * S and 0 <= xx < W * S:
                            img[yy][xx] = PAL[v]
for n in range(15):                                        # the banner's letter baseline for reference
    lx, ly = 36 + 12 * n, 152 - (n * 3) // 2 - 40
    for yy in range(ly + 16, ly + 17):
        for xx in range(lx, lx + 10):
            for sy in range(S):
                for sx in range(S):
                    img[yy * S + sy][xx * S + sx] = (255, 255, 255)
with open(os.path.join(here, "shots", "stamp_preview.ppm"), "wb") as fh:
    fh.write(b"P6\n%d %d\n255\n" % (W * S, H * S))
    for row in img:
        fh.write(bytes([c for px in row for c in px]))
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", os.path.join(here, "shots", "stamp_preview.ppm"), os.path.join(here, "shots", "stamp_preview.png")])
