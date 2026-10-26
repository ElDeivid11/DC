"""Texturas de la sala del jefe en pixel art grueso (la misma paleta que los
enemigos, pixel_kit.PAL): la puerta de dos hojas y la alfombra.

Escribe en assets/textures/sala_jefe/ las dos hojas de la puerta
(puerta_izq.png y puerta_der.png, 32x64 cada una: juntas forman el dibujo,
con la calavera partida por la junta) y alfombra.png (16x32: un tramo de
1,2 m x 2 m que se repite a lo largo de la alfombra).
Uso: python3 -I tools/sprites/draw_sala_jefe.py [--preview=/tmp/sala.png]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixel_kit import PAL, ROOT, art  # noqa: E402

OUT = ROOT / "assets" / "textures" / "sala_jefe"

# Calavera tallada arriba, partida al medio por la junta de las hojas.
SKULL = art("""
...WWWWWWWW...
.WWWWWWWWWWWW.
WWWWWWWWWWWWWB
WKKKWWWWWWKKKB
WKKKKWWWWKKKKB
WKKKWWKKWWKKKB
.BWWWWKKWWWWB.
..BWKWKWKWKB..
...BBBBBBBB...
""")
RING = art("""
.iii.
i...i
i...i
i...i
.iii.
""")


def to_rgba(grid):
    h, w = len(grid), len(grid[0])
    out = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        for x in range(w):
            ch = grid[y][x]
            if ch == ".":
                continue
            c = PAL[ch]
            out[y, x] = [int(c[1:3], 16), int(c[3:5], 16), int(c[5:7], 16), 255]
    return out


def stamp(grid, a, x0, y0):
    for j, row in enumerate(a):
        for i, ch in enumerate(row):
            if ch != ".":
                grid[y0 + j][x0 + i] = ch


def door():
    """Tablas verticales de madera oscura con juntas, tres herrajes con
    remaches, argollas y la calavera tallada (una mitad en cada hoja)."""
    n = 64
    g = [["o"] * n for _ in range(n)]
    rng = np.random.default_rng(3)
    for y in range(n):
        for x in range(n):
            plank = x // 8
            # vetas: tramos un tono más claro o más oscuro dentro de cada tabla
            if (x % 8) in (2, 5) and rng.random() < 0.35:
                g[y][x] = "O" if (plank + y // 5) % 2 else "L"
            if x % 8 == 0:
                g[y][x] = "K"  # junta entre tablas
        g[y][31] = "K"
        g[y][32] = "K"  # junta de las dos hojas
    for x in range(n):
        g[0][x] = g[n - 1][x] = "K"
    # herrajes: banda de hierro con remaches
    for yb in (8, 30, 52):
        for x in range(n):
            g[yb][x] = "i"
            g[yb + 1][x] = "I"
            g[yb + 2][x] = "i"
        for x in range(3, n, 6):
            if x not in (31, 32):
                g[yb + 1][x] = "S"
    stamp(g, SKULL, 25, 14)
    for row in range(14, 14 + len(SKULL)):
        g[row][31] = "K"
        g[row][32] = "K"
    # argollas a los dos lados de la junta
    stamp(g, RING, 24, 36)
    stamp(g, RING, 35, 36)
    return g


def carpet():
    """Alfombra roja con ribete dorado y rombos en el medio (se repite)."""
    w, h = 16, 32
    g = [["r"] * w for _ in range(h)]
    for y in range(h):
        g[y][0] = g[y][w - 1] = "K"
        g[y][1] = g[y][w - 2] = "g"
        g[y][2] = g[y][w - 3] = "G"
        g[y][3] = g[y][w - 4] = "r"
    for k, cy in enumerate((8, 24)):
        for dy in range(-5, 6):
            half = 5 - abs(dy)
            for dx in range(-half, half + 1):
                x = 7 + dx + (1 if dx >= 0 else 0)
                if 4 <= x < w - 4:
                    g[cy + dy][x] = "R" if abs(dx) < half else "g"
        g[cy][7] = g[cy][8] = "G"
    return g


def main(args):
    opts = dict(a[2:].split("=", 1) for a in args if a.startswith("--") and "=" in a)
    OUT.mkdir(parents=True, exist_ok=True)
    imgs = {}
    d = door()
    halves = {"puerta_izq": [row[:32] for row in d], "puerta_der": [row[32:] for row in d]}
    for name, grid in (*halves.items(), ("alfombra", carpet())):
        img = Image.fromarray(to_rgba(grid), "RGBA")
        img.save(OUT / f"{name}.png", optimize=True)
        print(f"{name}: {img.size[0]}x{img.size[1]}")
    imgs["puerta"] = Image.fromarray(to_rgba(d), "RGBA")
    imgs["alfombra"] = Image.fromarray(to_rgba(carpet()), "RGBA")
    if opts.get("preview"):
        a, b = imgs["puerta"], imgs["alfombra"]
        out = Image.new("RGBA", (a.width + b.width + 4, max(a.height, b.height)), (40, 34, 30, 255))
        out.alpha_composite(a, (0, 0))
        out.alpha_composite(b, (a.width + 4, 0))
        out.resize((out.width * 6, out.height * 6), Image.NEAREST).save(opts["preview"])


if __name__ == "__main__":
    main(sys.argv[1:])
