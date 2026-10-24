"""Dibujo 2D por piezas («recortes») para los sprites de enemigos.

Cada pieza (calavera, costillas, un hueso, la espada...) se dibuja PLANA, como
un dibujo: relleno, sombras y brillos puestos a mano con formas (no se
calculan con luz 3D), y su propio contorno oscuro. Las piezas se apilan en
orden y la animación las mueve, gira y estira como un títere de papel.

Coordenadas: px finales, y hacia ARRIBA, origen entre los pies. Cada forma se
rasteriza a SS veces (sin antialias) y cada píxel final es el color más
frecuente de sus SSxSS muestras: píxeles limpios con los colores exactos de
la paleta.
"""
import math

import numpy as np
from PIL import Image, ImageDraw

SS = 4
COVER = 0.5


class Palette:
    """Colores con nombre -> índice (0 = vacío)."""

    def __init__(self, colors):
        self.names = ["_"] + list(colors)
        self.rgb = np.array([(0, 0, 0)] + [_hex(c) for c in colors.values()], dtype=np.uint8)
        self.idx = {n: i for i, n in enumerate(self.names)}

    def __getitem__(self, name):
        return self.idx[name]


def _hex(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


# --- Formas (polígonos en coordenadas locales de la pieza) --------------------------

def ellipse(cx, cy, rx, ry, rot=0.0, n=None):
    if n is None:
        n = max(16, int(2 * math.pi * max(rx, ry) * 1.5))
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x, y = rx * math.cos(a), ry * math.sin(a)
        pts.append((cx + x * c - y * s, cy + x * s + y * c))
    return pts


def circle(cx, cy, r):
    return ellipse(cx, cy, r, r)


def capsule(a, b, ra, rb=None, n=10):
    """Hueso: segmento con puntas redondas (radio ra en a, rb en b)."""
    rb = ra if rb is None else rb
    ax, ay = a
    bx, by = b
    ang = math.atan2(by - ay, bx - ax)
    pts = []
    for i in range(n + 1):
        t = ang + math.pi / 2 + math.pi * i / n
        pts.append((bx + rb * math.cos(t - math.pi), by + rb * math.sin(t - math.pi)))
    for i in range(n + 1):
        t = ang + math.pi / 2 + math.pi * i / n
        pts.append((ax + ra * math.cos(t), ay + ra * math.sin(t)))
    return pts


def band(points, w0, w1=None):
    """Trazo grueso por una polilínea (ancho w0 al principio, w1 al final)."""
    w1 = w0 if w1 is None else w1
    left, right = [], []
    n = len(points)
    for i, (x, y) in enumerate(points):
        if i == 0:
            dx, dy = points[1][0] - x, points[1][1] - y
        elif i == n - 1:
            dx, dy = x - points[i - 1][0], y - points[i - 1][1]
        else:
            dx, dy = points[i + 1][0] - points[i - 1][0], points[i + 1][1] - points[i - 1][1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        w = (w0 + (w1 - w0) * i / max(n - 1, 1)) / 2
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left + right[::-1]


# --- Pieza ---------------------------------------------------------------------------

class Piece:
    """Una capa dibujada: operaciones de relleno sobre una grilla a SSx.
    transform = (x, y, rot en grados, escala x, escala y) de local a mundo."""

    def __init__(self, frame, outline, transform=(0.0, 0.0, 0.0, 1.0, 1.0)):
        self.f = frame
        self.outline = outline
        self.tx, self.ty, self.rot, self.sx, self.sy = transform
        self.hi = np.zeros((frame.h * SS, frame.w * SS), dtype=np.uint8)
        self.ops = []

    def world(self, x, y):
        """Local -> mundo (px finales, y hacia arriba)."""
        c, s = math.cos(math.radians(self.rot)), math.sin(math.radians(self.rot))
        x, y = x * self.sx, y * self.sy
        return self.tx + x * c - y * s, self.ty + x * s + y * c

    def _px(self, pts, shift=(0.0, 0.0), k=SS):
        f = self.f
        out = []
        for x, y in pts:
            wx, wy = self.world(x, y)
            out.append(((f.ox + (wx + shift[0]) * f.scale) * k, (f.oy - (wy + shift[1]) * f.scale) * k))
        return out

    def _mask(self, polys, shift=(0.0, 0.0)):
        """Máscara (a SSx) de la unión de polígonos, en toda la pieza."""
        if polys and isinstance(polys[0][0], (int, float)):
            polys = [polys]
        h, w = self.hi.shape
        img = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(img)
        for pts in polys:
            d.polygon(self._px(pts, shift), fill=1)
        return np.asarray(img, dtype=bool)

    def _where(self, polys, only, clip):
        m = self._mask(polys)
        m &= self.hi > 0
        if only is not None:
            m &= np.isin(self.hi, [self.f.pal[o] if isinstance(o, str) else o for o in only])
        if clip is not None:
            m &= self._mask(clip)
        return m

    def fill(self, polys, color):
        """Pinta la forma (agranda la pieza)."""
        self.hi[self._mask(polys)] = self.f.pal[color]

    def shade(self, polys, color, only=None, clip=None):
        """Pinta la forma solo donde la pieza ya tiene color (sombras, brillos).
        only: solo sobre esos colores; clip: solo dentro de esa forma."""
        self.hi[self._where(polys, only, clip)] = self.f.pal[color]

    def rim(self, polys, color, d, only=None, clip=None):
        """Media luna: la forma menos ella misma corrida d (px de mundo). Con d
        hacia la luz (arriba a la izquierda = (-k, +k)) queda el borde en
        sombra; con d al revés, el borde iluminado."""
        m = self._where(polys, only, clip) & ~self._mask(polys, d)
        self.hi[m] = self.f.pal[color]

    def line(self, pts, color, inside=True, only=None):
        """Línea de 1 px (Bresenham en la grilla final) por la polilínea."""
        self.ops.append(("line", pts, self.f.pal[color], inside, only))

    def dot(self, x, y, color, inside=True, only=None):
        self.ops.append(("line", [(x, y), (x, y)], self.f.pal[color], inside, only))

    def _apply_ops(self, fin):
        for _, pts, color, inside, only in self.ops:
            px = [(math.floor(x), math.floor(y)) for x, y in self._px(pts, k=1)]
            ok_colors = None if only is None else [self.f.pal[o] for o in only]
            cells = []
            for a, b in zip(px, px[1:]) if len(px) > 1 else [(px[0], px[0])]:
                cells += _bresenham(a, b)
            for x, y in cells:
                if 0 <= x < fin.shape[1] and 0 <= y < fin.shape[0]:
                    if inside and fin[y, x] == 0:
                        continue
                    if ok_colors is not None and fin[y, x] not in ok_colors:
                        continue
                    fin[y, x] = color


class Frame:
    """Un cuadro: piezas apiladas en orden (la última queda adelante)."""

    def __init__(self, w, h, origin, palette, scale=1.0):
        self.w, self.h = w, h
        self.ox, self.oy = origin
        self.pal = palette
        self.scale = scale
        self.pieces = []

    def piece(self, outline, transform=(0.0, 0.0, 0.0, 1.0, 1.0)):
        """outline: color del contorno de la pieza (None = sin contorno)."""
        p = Piece(self, self.pal[outline] if outline else 0, transform)
        self.pieces.append(p)
        return p

    def render(self, glow_names=()):
        """-> (RGBA uint8, máscara de brillo)."""
        h, w = self.h, self.w
        out = np.zeros((h, w), dtype=np.uint8)
        n = len(self.pal.names)
        for p in self.pieces:
            fin = _mode_down(p.hi, h, w, n)
            p._apply_ops(fin)
            solid = fin > 0
            if not solid.any():
                continue
            pad = np.pad(solid, 1)
            ring = ~solid & (pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:])
            if p.outline:
                fin = np.where(ring, p.outline, fin)
            out = np.where(fin > 0, fin, out)
        rgba = np.zeros((h, w, 4), dtype=np.uint8)
        rgba[..., :3] = self.pal.rgb[out]
        rgba[..., 3] = np.where(out > 0, 255, 0)
        glow = np.isin(out, [self.pal[g] for g in glow_names])
        return rgba, glow


def _mode_down(hi, h, w, n):
    blocks = hi.reshape(h, SS, w, SS).transpose(0, 2, 1, 3).reshape(h * w, SS * SS)
    cover = (blocks > 0).mean(1)
    idx = (np.arange(h * w)[:, None] * n + blocks).ravel()
    counts = np.bincount(idx, minlength=h * w * n).reshape(h * w, n)
    counts[:, 0] = 0
    best = counts.argmax(1)
    return np.where(cover >= COVER, best, 0).astype(np.uint8).reshape(h, w)


def _bresenham(a, b):
    (x0, y0), (x1, y1) = a, b
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    out = []
    while True:
        out.append((x0, y0))
        if x0 == x1 and y0 == y1:
            return out
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy
