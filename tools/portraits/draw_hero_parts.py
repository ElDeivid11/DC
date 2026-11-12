"""Piezas de los retratos de héroes en pixel art grueso (48x48, de frente,
busto), para armarlos por capas en el juego (HeroPortrait) según la
apariencia elegida en el Hub.

Cada pieza es un dibujo con «materiales» en vez de colores: piel, pelo, ojos,
ropa, capa, y fijos (blanco del ojo, cuero, metal, piel de oso, dientes,
pintura), cada uno en tres tonos (claro, medio, oscuro), más la tinta del
contorno. En el PNG cada píxel guarda material y tono (R = material x 16,
G = tono x 80): el juego los pinta con las paletas de data/apariencia.json.

Las formas (cabeza, orejas, cuello, hombros, pelo, capuchas) se arman con
máscaras y se sombrean con luz de arriba a la izquierda en tres tonos; los
detalles van a mano en ASCII. Cada capa lleva su contorno de 1 px.

Escribe assets/portraits/heroes/partes.png + partes.json (el manifiesto: por
categoría, sus opciones y de cada una sus capas con el rectángulo del atlas y
dónde va en el retrato).
Uso: python3 -I tools/portraits/draw_hero_parts.py [--preview=/tmp/heroes.png]
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "portraits" / "heroes"
N = 48

# Materiales (el índice va en el PNG) y el carácter de cada tono en los dibujos.
MATERIALS = ["tinta", "piel", "pelo", "ojos", "blanco", "ropa", "capa", "cuero", "metal", "oso", "dientes", "pintura"]
CHARS = {
    "K": ("tinta", 0),
    "1": ("piel", 0), "2": ("piel", 1), "3": ("piel", 2),
    "H": ("pelo", 0), "h": ("pelo", 1), "j": ("pelo", 2),
    "E": ("ojos", 0), "e": ("ojos", 1),
    "w": ("blanco", 0),
    "C": ("ropa", 0), "c": ("ropa", 1), "v": ("ropa", 2),
    "A": ("capa", 0), "a": ("capa", 1), "q": ("capa", 2),
    "L": ("cuero", 0), "l": ("cuero", 1), "n": ("cuero", 2),
    "M": ("metal", 0), "m": ("metal", 1), "i": ("metal", 2),
    "F": ("oso", 0), "f": ("oso", 1), "g": ("oso", 2),
    "t": ("dientes", 0),
    "R": ("pintura", 0), "r": ("pintura", 1),
}
# Orden de las capas (de atrás hacia adelante).
LAYERS = ["fondo_pelo", "fondo_tocado", "cuerpo", "cuello", "cabeza", "cara", "barba", "pelo", "tocado", "frente"]

# Paletas de muestra para la vista previa (las de verdad están en data/apariencia.json).
PREVIEW_PAL = {
    "tinta": ["#1a1020"] * 3,
    "blanco": ["#f2ead2"] * 3, "cuero": ["#9a5a30", "#6a4028", "#432818"],
    "metal": ["#d4dce6", "#9a9aa8", "#5c5c6a"], "oso": ["#8a6040", "#5e4028", "#3a2618"],
    "dientes": ["#f2ead2"] * 3, "pintura": ["#e04a3a", "#92243a", "#5e1714"],
}

# --- Máscaras y sombreado -----------------------------------------------------------------


def grid():
    return np.full((N, N), ".", dtype="<U1")


def ellipse(cx, cy, rx, ry):
    ys, xs = np.mgrid[0:N, 0:N]
    return ((xs + 0.5 - cx) / rx) ** 2 + ((ys + 0.5 - cy) / ry) ** 2 <= 1.0


def rect(x0, y0, x1, y1):
    m = np.zeros((N, N), bool)
    m[max(y0, 0):min(y1, N), max(x0, 0):min(x1, N)] = True
    return m


def shade(mask, chars, cx=None, cy=None, bias=0.0, hard=False):
    """Pinta la máscara en tres tonos con luz de arriba a la izquierda (según
    la posición dentro de la forma). chars = (claro, medio, oscuro)."""
    g = grid()
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return g
    cx = xs.mean() if cx is None else cx
    cy = ys.mean() if cy is None else cy
    w = max(xs.max() - xs.min(), 1) / 2
    h = max(ys.max() - ys.min(), 1) / 2
    for x, y in zip(xs, ys):
        t = 0.62 * (x - cx) / w + 0.5 * (y - cy) / h + bias
        c = chars[0] if t < 0.15 else chars[1] if t < 0.62 else chars[2]
        g[y, x] = c
    return g


def over(dst, src):
    m = src != "."
    dst[m] = src[m]
    return dst


def outline(g, ink="K", only_outside=None):
    """Contorno de 1 px alrededor de lo pintado (4-vecinos)."""
    solid = g != "."
    pad = np.pad(solid, 1)
    ring = ~solid & (pad[1:-1, :-2] | pad[1:-1, 2:] | pad[:-2, 1:-1] | pad[2:, 1:-1])
    if only_outside is not None:
        ring &= only_outside
    out = g.copy()
    out[ring] = ink
    return out


def art(s):
    return [r for r in s.strip("\n").split("\n")]


def stamp(g, a, x0, y0):
    for j, row in enumerate(a):
        for i, ch in enumerate(row):
            if ch != "." and 0 <= y0 + j < N and 0 <= x0 + i < N:
                g[y0 + j, x0 + i] = ch
    return g


def mirror(g):
    """Copia la mitad izquierda sobre la derecha (cosas simétricas)."""
    out = g.copy()
    out[:, N // 2:] = g[:, :N // 2][:, ::-1]
    return out


# --- Geometría base (la misma para todas las piezas) --------------------------------------
# Cabeza centrada en x 24, de y 8 (coronilla) a 32 (mentón); ojos en y 20-22.
HEAD_CX, HEAD_CY, HEAD_RX, HEAD_RY = 24.0, 20.5, 11.0, 12.0


def head_mask(shape):
    m = ellipse(HEAD_CX, HEAD_CY, HEAD_RX, HEAD_RY)
    if shape == "cuadrada":
        m |= rect(14, 14, 34, 29) & ellipse(HEAD_CX, 21.5, 12.2, 12.0)
    elif shape == "fina":
        ys, xs = np.mgrid[0:N, 0:N]
        # mandíbula en punta: más angosta cuanto más abajo
        narrow = (ys > 23) & (np.abs(xs + 0.5 - HEAD_CX) > HEAD_RX - (ys - 23) * 0.75)
        m &= ~narrow
        m |= ellipse(HEAD_CX, 18.5, 11.0, 10.5)
    return m


def body_layer(style):
    """Hombros y pecho (y 33-47) con el cuello de la prenda."""
    ys, xs = np.mgrid[0:N, 0:N]
    half = 13 + (ys - 33) * 0.75
    torso = (ys >= 33) & (np.abs(xs + 0.5 - 24) <= half)
    torso |= ellipse(24, 40, 21, 8) & (ys >= 35)
    g = shade(torso, ("C", "c", "v"), cx=20, cy=38)
    if style == "tunica":
        # escote en V con el cuello y una costura
        stamp(g, art("""
.v.......v.
.vv.....vv.
..vv...vv..
...v...v...
...vv.vv...
....vvv....
"""), 19, 33)
        for y in range(39, 48):
            g[y, 24] = "v"
    elif style == "cuero":
        # coraza de cuero con correa cruzada y hebilla
        jerkin = torso & (np.abs(xs + 0.5 - 24) <= 10)
        over(g, shade(jerkin, ("L", "l", "n"), cx=21, cy=38))
        for k in range(14):
            x, y = 14 + k, 34 + k
            if 0 <= y < N:
                g[y, x] = "n"
                g[y, x + 1] = "l"
        stamp(g, art("""
MMM
MiM
MMM
"""), 22, 40)
    elif style == "armadura":
        # peto y hombreras de metal sobre la ropa
        plate = torso & (np.abs(xs + 0.5 - 24) <= 9) & (ys >= 35)
        over(g, shade(plate, ("M", "m", "i"), cx=20, cy=38))
        for side in (-1, 1):
            pad = ellipse(24 + side * 14, 37, 6, 4.5)
            over(g, shade(pad, ("M", "m", "i"), cx=24 + side * 14 - 2, cy=35))
            for k in range(-5, 6):
                if (k + 6) % 4 == 0:
                    g[38, int(24 + side * 14 + k)] = "i"
        for y in range(36, 48):
            g[y, 24] = "i"
    elif style == "harapos":
        # tela gastada, con remiendos y un borde roto
        for y in range(36, 48, 3):
            for x in range(4, 44):
                if (x * 7 + y * 3) % 11 == 0 and torso[y, x]:
                    g[y, x] = "v"
        stamp(g, art("""
LLL
LnL
LLL
"""), 31, 40)
        stamp(g, art("""
nn
nn
"""), 14, 43)
    return outline(g)


def neck_layer():
    m = rect(19, 28, 29, 37)
    g = shade(m, ("2", "2", "3"), cx=21)
    # sombra del mentón
    for x in range(19, 29):
        g[28, x] = "3"
        g[29, x] = "3"
    return outline(g)


def head_layer(shape):
    m = head_mask(shape)
    ears = ellipse(12.6, 21.5, 2.2, 3.2) | ellipse(35.4, 21.5, 2.2, 3.2)
    g = shade(ears, ("2", "2", "3"))
    g = outline(g)
    over(g, shade(m, ("1", "2", "3"), cx=22, cy=17, bias=-0.15))
    return outline(g)


EYES = {
    "normales": art("""
HHHH....HHHH
............
.wEK....wEK.
.wEK....wEK.
"""),
    "entornados": art("""
.HHHH..HHHH.
............
.KKK....KKK.
.wEK....wEK.
"""),
    "grandes": art("""
HHH......HHH
.wwK....wwK.
.wEE....wEE.
.weK....weK.
"""),
}
MOUTHS = {
    "neutral": art("""
...K...
.......
.KKKKK.
"""),
    "sonrisa": art("""
...K...
.......
K.....K
.KKKKK.
"""),
    "mueca": art("""
...K...
.......
.KKK...
....KK.
"""),
}


def face_layer(eyes, mouth):
    g = grid()
    stamp(g, EYES[eyes], 18, 18)
    # nariz (sombra) y boca
    stamp(g, MOUTHS[mouth], 21, 24)
    g[25, 24] = "3"
    g[25, 23] = "2" if mouth != "mueca" else "3"
    # el ojo derecho del dibujo mira igual que el izquierdo: espejarlo
    return g


MARKS = ["ninguna", "cicatriz", "pintura", "pecas"]


def mark_layer(mark):
    g = grid()
    if mark == "cicatriz":
        for k in range(6):
            g[16 + k, 28 + (k % 2)] = "3"
        g[17, 30] = "3"
        g[19, 28] = "3"
    elif mark == "pintura":
        for x in range(16, 22):
            g[23, x] = "R"
            g[24, x] = "r" if x % 2 else "R"
        for x in range(27, 33):
            g[23, x] = "R"
            g[24, x] = "r" if x % 2 else "R"
    elif mark == "pecas":
        for x, y in ((17, 24), (19, 25), (16, 26), (30, 24), (28, 25), (31, 26), (23, 23), (25, 23)):
            g[y, x] = "3"
    return g


BEARDS = ["ninguna", "corta", "larga", "bigote", "candado"]


def beard_layer(beard):
    g = grid()
    if beard == "ninguna":
        return g
    ys, xs = np.mgrid[0:N, 0:N]
    if beard in ("corta", "larga"):
        bottom = 33 if beard == "corta" else 39
        # patillas por los costados y la barba bajo la nariz, sin tapar ojos
        jaw = head_mask("redonda") & (ys >= 25)
        jaw |= head_mask("redonda") & (ys >= 19) & (np.abs(xs + 0.5 - 24) >= 9)
        if beard == "larga":
            jaw |= ellipse(24, 32, 9.5, 7.5) & (ys >= 26)
        jaw &= ys < bottom
        # deja ver la boca
        jaw &= ~(rect(20, 26, 29, 28))
        g = shade(jaw, ("H", "h", "j"), cx=21, cy=26)
        # mechones
        for x in range(14, 35, 3):
            for y in range(26, bottom - 1, 2):
                if g[y, x] != ".":
                    g[y, x] = "j"
    if beard in ("bigote", "corta", "larga", "candado"):
        stamp(g, art("""
.HHHHHHH.
HHhhhhhHH
Hh.....hH
"""), 20, 24)
    if beard == "candado":
        stamp(g, art("""
..hhh..
..HHH..
...h...
"""), 21, 28)
    return outline(g)


HAIR = ["calvo", "corto", "flequillo", "largo", "coleta", "cresta", "trenzas"]


def hair_layers(style):
    """-> (detrás de la cabeza, sobre la cabeza)."""
    back, front = grid(), grid()
    if style == "calvo":
        return back, front
    ys, xs = np.mgrid[0:N, 0:N]
    cap = ellipse(HEAD_CX, HEAD_CY - 0.5, HEAD_RX + 1.6, HEAD_RY + 1.4)
    if style == "cresta":
        top = cap & (np.abs(xs + 0.5 - 24) <= 3) & (ys <= 14)
        top |= ellipse(24, 6, 3.5, 4) & (ys <= 10)
        front = shade(top, ("H", "h", "j"))
        for y in range(3, 14, 2):
            front[y, 22] = "j"
        return back, outline(front)
    # casquete: arriba de la frente, con los costados hasta las sienes
    hairline = 13 if style != "flequillo" else 17
    sides = 22 if style in ("largo", "trenzas") else 19
    m = cap & ((ys < hairline) | ((np.abs(xs + 0.5 - 24) > 9) & (ys < sides)))
    front = shade(m, ("H", "h", "j"), cx=20, cy=10)
    # mechas: líneas oscuras que bajan
    for x in range(14, 35, 3):
        for y in range(5, sides):
            if front[y, x] != "." and (y + x) % 3 != 0:
                front[y, x] = "h" if front[y, x] == "H" else "j"
    if style == "flequillo":
        # flequillo de puntas sobre la frente
        for x in range(15, 34):
            if (x // 2) % 2 == 0 and front[16, x] != ".":
                front[17, x] = "h"
    if style in ("largo", "trenzas"):
        hang = (ellipse(24, 26, 15, 16) & (ys >= 14) & (np.abs(xs + 0.5 - 24) >= 9)) & (ys < 40)
        back = shade(hang, ("H", "h", "j"), cx=18, cy=22)
        if style == "trenzas":
            back = grid()
            for side in (-1, 1):
                for k in range(8):
                    cx = 24 + side * 12
                    cy = 24 + k * 2.2
                    blob = ellipse(cx, cy, 2.4, 1.6)
                    over(back, shade(blob, ("H", "h", "j")))
                stamp(back, art("""
LL
"""), int(24 + side * 12 - 1), 41)
        back = outline(back)
    if style == "coleta":
        tail = ellipse(36.5, 16, 3.5, 6) | ellipse(38, 24, 2.5, 5)
        back = outline(shade(tail, ("H", "h", "j")))
        stamp(back, art("""
LLL
"""), 34, 11)
    return back, outline(front)


HEADWEAR = ["ninguno", "capucha", "oso", "cinta", "casco"]


def headwear_layers(kind):
    """-> (detrás, adelante)."""
    back, front = grid(), grid()
    ys, xs = np.mgrid[0:N, 0:N]
    if kind == "capucha":
        hood = ellipse(24, 19, 15, 16.5) & (ys < 36)
        face_hole = ellipse(24, 23, 10, 11.5) & (ys >= 13)
        back = outline(shade(hood & (ys >= 18), ("A", "a", "q"), cx=19, cy=20))
        top = hood & ~face_hole & (ys < 36)
        front = shade(top, ("A", "a", "q"), cx=18, cy=12)
        # pliegue y sombra del borde de la cara
        edge = ellipse(24, 23, 11, 12.5) & ~face_hole & (ys >= 12)
        front[edge & (front != ".")] = "q"
        front = outline(front)
    elif kind == "oso":
        # la cabeza del oso encima (hocico sobre la frente) y la piel que cae
        # por los costados de la cara hasta los hombros
        pelt = ellipse(24, 9.5, 14, 7.5) & (ys < 16)
        pelt |= ellipse(24, 23, 15.5, 15) & (np.abs(xs + 0.5 - 24) >= 11) & (ys >= 9) & (ys < 37)
        back = outline(shade(ellipse(24, 26, 15.5, 12) & (ys >= 20) & (ys < 38), ("F", "f", "g"), cx=18, cy=24))
        front = shade(pelt, ("F", "f", "g"), cx=19, cy=8)
        for side in (-1, 1):
            ear = ellipse(24 + side * 10.5, 3.5, 2.6, 2.6)
            over(front, shade(ear, ("F", "f", "g")))
            front[3, int(24 + side * 10.5)] = "g"
        stamp(front, art("""
KK.........KK
"""), 18, 6)
        stamp(front, art("""
..gggg..
.gfffffg
ggfKKffg
.gggggg.
"""), 20, 8)
        # dientes del borde del hocico, sobre la frente
        for x in range(15, 34):
            front[15, x] = "f"
        for x in range(16, 33, 2):
            front[16, x] = "t"
        front = outline(front)
    elif kind == "cinta":
        band = rect(12, 13, 37, 16) & ellipse(HEAD_CX, HEAD_CY, HEAD_RX + 1.5, HEAD_RY + 1.5)
        front = shade(band, ("A", "a", "q"))
        tails = grid()
        stamp(tails, art("""
.AA
Aaq
aq.
q..
"""), 34, 15)
        over(front, tails)
        front = outline(front)
    elif kind == "casco":
        dome = ellipse(24, 15, 13, 10) & (ys < 18)
        front = shade(dome, ("M", "m", "i"), cx=20, cy=10)
        for x in range(11, 38):
            if dome[16, x] or dome[17, x] or abs(x - 24) < 12:
                front[17, x] = "i"
                front[16, x] = "m" if x % 3 else "M"
        # nasal
        for y in range(17, 25):
            front[y, 24] = "m"
            front[y, 23] = "M"
        front = outline(front)
    return back, front


CATEGORIES = {
    "cara": ["redonda", "cuadrada", "fina"],
    "ojos": list(EYES),
    "boca": list(MOUTHS),
    "marca": MARKS,
    "barba": BEARDS,
    "pelo": HAIR,
    "tocado": HEADWEAR,
    "ropa": ["tunica", "cuero", "armadura", "harapos"],
}


def layers_for(cat, opt):
    """-> {capa: grilla} de una opción."""
    if cat == "cara":
        return {"cabeza": head_layer(opt), "cuello": neck_layer()}
    if cat == "ojos":
        return {"cara": stamp(grid(), EYES[opt], 18, 18)}
    if cat == "boca":
        g = stamp(grid(), MOUTHS[opt], 21, 24)
        g[25, 24] = "3"
        return {"cara": g}
    if cat == "marca":
        return {"cara": mark_layer(opt)}
    if cat == "barba":
        return {"barba": beard_layer(opt)}
    if cat == "pelo":
        back, front = hair_layers(opt)
        return {"fondo_pelo": back, "pelo": front}
    if cat == "tocado":
        back, front = headwear_layers(opt)
        return {"fondo_tocado": back, "tocado": front}
    if cat == "ropa":
        return {"cuerpo": body_layer(opt)}
    raise KeyError(cat)


# --- Atlas ---------------------------------------------------------------------------------

def encode(g):
    """Grilla de caracteres -> RGBA con material y tono en R y G."""
    out = np.zeros((N, N, 4), np.uint8)
    for ch, (mat, tone) in CHARS.items():
        m = g == ch
        out[m] = [MATERIALS.index(mat) * 16, tone * 80, 0, 255]
    return out


def build():
    pieces = []  # (cat, i, layer, crop, (x, y))
    # Con estos tocados no se dibuja el pelo (queda adentro).
    manifest = {"size": N, "layers": LAYERS, "materials": MATERIALS, "hides_hair": ["capucha", "oso", "casco"],
                "categories": {}}
    for cat, opts in CATEGORIES.items():
        manifest["categories"][cat] = []
        for i, opt in enumerate(opts):
            entry = {"id": opt, "layers": {}}
            for layer, g in layers_for(cat, opt).items():
                ys, xs = np.nonzero(g != ".")
                if len(xs) == 0:
                    continue
                x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
                pieces.append((cat, i, layer, encode(g)[y0:y1, x0:x1], (int(x0), int(y0))))
                entry["layers"][layer] = None
            manifest["categories"][cat].append(entry)
    # Estante simple: filas de 256 px.
    W = 256
    x = y = row_h = 0
    placed = []
    for p in pieces:
        h, w = p[3].shape[:2]
        if x + w > W:
            x, y, row_h = 0, y + row_h + 1, 0
        placed.append((p, x, y))
        x += w + 1
        row_h = max(row_h, h)
    H = y + row_h
    atlas = np.zeros((H, W, 4), np.uint8)
    for (cat, i, layer, img, at), ax, ay in placed:
        h, w = img.shape[:2]
        atlas[ay:ay + h, ax:ax + w] = img
        manifest["categories"][cat][i]["layers"][layer] = {"rect": [ax, ay, w, h], "at": list(at)}
    return atlas, manifest


def compose(atlas, manifest, look, pal):
    """Lo mismo que HeroPortrait en el juego (para la vista previa)."""
    out = np.zeros((N, N, 4), np.uint8)
    picks = {cat: manifest["categories"][cat][look[cat]] for cat in CATEGORIES}
    hood = picks["tocado"]["id"] in manifest["hides_hair"]
    for layer in LAYERS:
        for cat, entry in picks.items():
            spec = entry["layers"].get(layer)
            if not spec:
                continue
            # bajo capucha o casco no se ve el pelo de arriba ni el de atrás
            if hood and cat == "pelo":
                continue
            ax, ay, w, h = spec["rect"]
            x0, y0 = spec["at"]
            piece = atlas[ay:ay + h, ax:ax + w]
            for yy in range(h):
                for xx in range(w):
                    px = piece[yy, xx]
                    if px[3] == 0:
                        continue
                    mat = MATERIALS[px[0] // 16]
                    tone = px[1] // 80
                    hexc = pal[mat][min(tone, len(pal[mat]) - 1)]
                    out[y0 + yy, x0 + xx] = [int(hexc[1:3], 16), int(hexc[3:5], 16), int(hexc[5:7], 16), 255]
    return out


SAMPLES = [
    # Bjorn: capucha de oso, barba larga castaña, ropa azul verdosa con cuero
    ({"cara": 1, "ojos": 1, "boca": 0, "marca": 0, "barba": 2, "pelo": 1, "tocado": 2, "ropa": 1},
     {"piel": ["#f0c4a0", "#d09070", "#9a5a48"], "pelo": ["#a0603a", "#704028", "#482818"],
      "ojos": ["#5a8ac0", "#2c4a70"], "ropa": ["#4a8a8a", "#2e6060", "#1c3c40"], "capa": ["#8a52aa", "#6a3a8a", "#42245a"]}),
    # Elena: capucha morada
    ({"cara": 2, "ojos": 0, "boca": 1, "marca": 0, "barba": 0, "pelo": 3, "tocado": 1, "ropa": 0},
     {"piel": ["#f6d2b4", "#d8a888", "#a06c58"], "pelo": ["#3a2a28", "#24181a", "#120a0c"],
      "ojos": ["#6aa848", "#3a6028"], "ropa": ["#6a8a58", "#4a6a3c", "#2c4426"], "capa": ["#8a52aa", "#6a3a8a", "#42245a"]}),
    ({"cara": 0, "ojos": 2, "boca": 1, "marca": 3, "barba": 0, "pelo": 4, "tocado": 0, "ropa": 3},
     {"piel": ["#e8b890", "#c08860", "#88583c"], "pelo": ["#e8823a", "#b8502a", "#7a2c1a"],
      "ojos": ["#5a8ac0", "#2c4a70"], "ropa": ["#a89a74", "#7a6e50", "#4e4432"], "capa": ["#d8a838", "#a07828", "#604818"]}),
    ({"cara": 1, "ojos": 1, "boca": 2, "marca": 1, "barba": 3, "pelo": 5, "tocado": 0, "ropa": 2},
     {"piel": ["#a8704c", "#7e5036", "#523020"], "pelo": ["#2a2224", "#1a1416", "#0c0a0a"],
      "ojos": ["#c09040", "#7a5420"], "ropa": ["#9a3a3a", "#6a2828", "#401818"], "capa": ["#3d62a8", "#24396b", "#16223f"]}),
    ({"cara": 2, "ojos": 0, "boca": 0, "marca": 2, "barba": 0, "pelo": 6, "tocado": 3, "ropa": 1},
     {"piel": ["#f0d8c0", "#d0b098", "#a08470"], "pelo": ["#f0e0a0", "#c8b070", "#8a7848"],
      "ojos": ["#6aa848", "#3a6028"], "ropa": ["#5a6aa8", "#3d4a80", "#252c50"], "capa": ["#e04a3a", "#92243a", "#5e1714"]}),
    ({"cara": 0, "ojos": 1, "boca": 0, "marca": 0, "barba": 4, "pelo": 0, "tocado": 4, "ropa": 2},
     {"piel": ["#d8a07c", "#b07858", "#7a4c38"], "pelo": ["#8a8a8a", "#606060", "#3a3a3a"],
      "ojos": ["#5a8ac0", "#2c4a70"], "ropa": ["#6a6a7a", "#4a4a58", "#2a2a36"], "capa": ["#3d62a8", "#24396b", "#16223f"]}),
]


def main(args):
    opts = dict(a[2:].split("=", 1) for a in args if a.startswith("--") and "=" in a)
    atlas, manifest = build()
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(atlas, "RGBA").save(OUT / "partes.png", optimize=True)
    (OUT / "partes.json").write_text(json.dumps(manifest, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"partes: atlas {atlas.shape[1]}x{atlas.shape[0]}, {sum(len(v) for v in CATEGORIES.values())} opciones")
    if opts.get("preview"):
        z = 4
        out = Image.new("RGBA", ((N + 4) * len(SAMPLES) * z, (N + 4) * z), (43, 35, 29, 255))
        for k, (look, pal) in enumerate(SAMPLES):
            p = dict(PREVIEW_PAL)
            p.update(pal)
            img = Image.fromarray(compose(atlas, manifest, look, p), "RGBA").resize((N * z, N * z), Image.NEAREST)
            out.alpha_composite(img, ((N + 4) * k * z + 2 * z, 2 * z))
        out.save(opts["preview"])
        print(f"vista previa: {opts['preview']}")


if __name__ == "__main__":
    main(sys.argv[1:])
