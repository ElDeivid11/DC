"""Generador del kit pixel de la UI «Grimorio de la Cripta».

Dibuja a 1x (pixel art) cada pieza de la UI con los colores de
data/ui_palette.json, las empaqueta en un único atlas escalado x2 sin
suavizado (ui/kit/ui_atlas.png) y escribe ui/kit/manifest.json con las
regiones, márgenes 9-slice, ejes, cuadros de animación e íconos. ThemeBuilder
arma el Theme a partir de ese manifiesto (scripts/ui/ui_kit.gd).

    python3 -I tools/ui/make_ui_kit.py [--preview=RUTA.png]

Determinista: dos corridas dan el mismo PNG y el mismo JSON (el test
tests/unit/test_ui_kit.gd compara los SHA-256 de la paleta y de este script).
Solo necesita Pillow. Las máscaras de los íconos salen de rasterize_icons.py
(commiteadas en tools/ui/src/icons_1x/).

Convenciones: «a» = píxel de arte (1x); en pantalla 1 a = PIXEL_SCALE px.
Anillo i = píxeles a distancia de Chebyshev i del borde. ring(img, i, tl, br):
fila de arriba y columna izquierda en tl, abajo y derecha en br.
"""
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
PALETTE_PATH = ROOT / "data" / "ui_palette.json"
TEXTS_PATH = ROOT / "data" / "texts.json"
LOGO_FONT = ROOT / "assets" / "fonts" / "Jacquard24-Regular.ttf"
ICON_MASKS = ROOT / "tools" / "ui" / "src" / "icons_1x"
ICON_LIST = ROOT / "tools" / "ui" / "src" / "icons.json"
OUT_DIR = ROOT / "ui" / "kit"
ATLAS_RES = "res://ui/kit/ui_atlas.png"

PAL_DATA = json.loads(PALETTE_PATH.read_text(encoding="utf-8"))
PAL = PAL_DATA["palette"]
SCALE = int(PAL_DATA["pixel_scale"])
B4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
CLEAR = (0, 0, 0, 0)


def c(name, alpha=255):
    h = PAL[name].lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), alpha)


def col(v):
    return c(v) if isinstance(v, str) else v


def new(w, h, fill=None):
    return Image.new("RGBA", (w, h), col(fill) if fill else CLEAR)


def ring(img, i, tl, br=None, chamfer=False):
    br = tl if br is None else br
    w, h = img.size
    for x in range(i, w - i):
        img.putpixel((x, i), col(tl))
        img.putpixel((x, h - 1 - i), col(br))
    for y in range(i, h - i):
        img.putpixel((i, y), col(tl))
        img.putpixel((w - 1 - i, y), col(br))
    # esquinas: arriba-derecha → br, abajo-izquierda → tl (luz arriba-izquierda)
    img.putpixel((w - 1 - i, i), col(br))
    img.putpixel((i, h - 1 - i), col(tl))
    if chamfer:
        for (x, y) in [(i, i), (w - 1 - i, i), (i, h - 1 - i), (w - 1 - i, h - 1 - i)]:
            img.putpixel((x, y), CLEAR)


def chamfer_inner(img, color0):
    """Ochavado: las esquinas del anillo 1 toman el color del anillo 0."""
    w, h = img.size
    for (x, y) in [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)]:
        img.putpixel((x, y), col(color0))


def rect(img, x0, y0, x1, y1, color):
    for y in range(y0, y1):
        for x in range(x0, x1):
            img.putpixel((x, y), col(color))


def stamp(img, ox, oy, rows, cmap):
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in cmap:
                img.putpixel((ox + x, oy + y), col(cmap[ch]))


def dist(img, x, y):
    w, h = img.size
    return min(x, y, w - 1 - x, h - 1 - y)


# --- Piezas 9-slice ---------------------------------------------------------------------------

SPRITES = {}   # nombre → (Image, info)


def sprite(name, img, margin=(0, 0, 0, 0), content=(0, 0, 0, 0), axis=("stretch", "stretch"), draw_center=True):
    SPRITES[name] = (img, {"margin": list(margin), "content": list(content), "axis": list(axis), "draw_center": draw_center})


PLATE = [
    "ooooooooo",
    "olllllllo",
    "olhhhhhdo",
    "olhLBBhdo",
    "olhBBDhdo",
    "olhBDDhdo",
    "olhhhhhdo",
    "olddddddo",
    "ooooooooo",
]


def panel_iron():
    img = new(30, 30, "VITELA")
    ring(img, 0, "TINTA")
    ring(img, 1, "HIERRO_LUZ", "HIERRO_OSC")
    ring(img, 2, "HIERRO")
    ring(img, 3, "HIERRO")
    ring(img, 4, "HIERRO_OSC", "HIERRO_LUZ")
    ring(img, 5, "TINTA")
    ring(img, 6, "VITELA")
    ring(img, 7, "BRONCE_FILETE")
    for y in range(30):
        for x in range(30):
            d = dist(img, x, y)
            if d in (2, 3) and (x + 2 * y) % 5 == 0:
                img.putpixel((x, y), c("HIERRO_GRANO"))
            if d >= 8:
                if (x + 3 * y) % 10 == 0 and y % 2 == 0:
                    img.putpixel((x, y), c("VITELA_ALTA"))
                elif (3 * x + 7 * y + 5) % 10 == 0 and y % 2 == 1:
                    img.putpixel((x, y), c("CRIPTA"))
    cmap = {"o": "TINTA", "l": "HIERRO_LUZ", "h": "HIERRO", "d": "HIERRO_OSC",
            "L": "BRONCE_LUZ", "B": "BRONCE", "D": "BRONCE_OSC"}
    for (ox, oy) in [(0, 0), (21, 0), (0, 21), (21, 21)]:
        stamp(img, ox, oy, PLATE, cmap)
    sprite("panel_iron", img, (10, 10, 10, 10), (14, 14, 14, 14), ("tile", "tile"))


def panel_inset():
    img = new(12, 12, "VITELA_ALTA")
    ring(img, 0, "HUNDIDO", "BORDE_HUNDIDO")
    for y in range(1, 11):
        for x in range(1, 11):
            if (x + 3 * y) % 8 == 0 and y % 2 == 0:
                img.putpixel((x, y), c("VITELA"))
    sprite("panel_inset", img, (2, 2, 2, 2), (6, 6, 6, 6), ("tile", "tile"))


def panel_hud():
    img = new(12, 12, c("VITELA", 235))
    ring(img, 0, "TINTA")
    ring(img, 1, "HIERRO_LUZ", "HIERRO_OSC")
    for (x, y) in [(1, 1), (10, 1), (1, 10), (10, 10)]:
        img.putpixel((x, y), c("BRONCE"))
    ring(img, 2, "TINTA")
    sprite("panel_hud", img, (3, 3, 3, 3), (5, 4, 5, 4))


def card(name, ring0, tl, br, fill):
    img = new(14, 14, fill)
    ring(img, 0, ring0, chamfer=True)
    ring(img, 1, tl, br)
    chamfer_inner(img, ring0)
    sprite(name, img, (4, 4, 4, 4), (5, 4, 5, 4))


def portrait_frame(name, ring0, tl, br, corner):
    img = new(16, 16, "NICHO")
    ring(img, 0, "TINTA")
    ring(img, 1, tl, br)
    for (x, y) in [(1, 1), (14, 1), (1, 14), (14, 14)]:
        img.putpixel((x, y), c(corner))
    ring(img, 2, "TINTA")
    ring(img, 3, "HUNDIDO", "NICHO")
    if ring0 != "TINTA":
        ring(img, 0, ring0)
    sprite(name, img, (4, 4, 4, 4), (4, 4, 4, 4))


def rank_plaque():
    img = new(10, 10, "PIEDRA")
    ring(img, 0, "TINTA", chamfer=True)
    ring(img, 1, "PIEDRA_LUZ", "PIEDRA_OSC")
    chamfer_inner(img, "TINTA")
    sprite("rank_plaque", img, (3, 3, 3, 3), (3, 1, 3, 1))


def keycap():
    img = new(10, 11)
    top = new(10, 10, "PIEDRA")
    ring(top, 0, "TINTA", chamfer=True)
    ring(top, 1, "PIEDRA_LUZ", "PIEDRA_OSC")
    chamfer_inner(top, "TINTA")
    img.paste(top, (0, 0))
    for x in range(1, 9):
        img.putpixel((x, 10), c("PIEDRA_OSC"))
    img.putpixel((0, 10), c("TINTA"))
    img.putpixel((9, 10), c("TINTA"))
    sprite("keycap", img, (3, 3, 3, 4), (3, 1, 3, 2))


def tooltip():
    img = new(14, 14)
    rect(img, 2, 2, 14, 14, (0, 0, 0, 140))
    note = new(12, 12, "NOTA")
    ring(note, 0, "TINTA")
    ring(note, 1, "BRONCE_FILETE")
    img.paste(note, (0, 0))
    sprite("tooltip", img, (3, 3, 5, 5), (5, 4, 7, 6))


def buttons():
    def base(ring0, tl, br, fill, ring2=None, center=True):
        img = new(16, 16)
        if center:
            rect(img, 1, 1, 15, 15, fill)
        ring(img, 0, ring0, chamfer=True)
        ring(img, 1, tl, br)
        chamfer_inner(img, ring0)
        if ring2:
            ring(img, 2, ring2[0], ring2[1])
        return img
    args = dict(margin=(4, 4, 4, 4), content=(6, 3, 6, 3))
    sprite("button_normal", base("TINTA", "PIEDRA_LUZ", "PIEDRA_OSC", "PIEDRA"), **args)
    sprite("button_pressed", base("BRASA", "PIEDRA_OSC", "PIEDRA_LUZ", "PIEDRA_OSC"), **args)
    sprite("button_disabled", base("HUNDIDO", "VITELA_ALTA", "VITELA_ALTA", "VITELA"), **args)
    sprite("button_focus", base("BRASA", "VELA", "BRASA_OSC", None, ("PIEDRA_LUZ", "PIEDRA_OSC"), False),
           draw_center=False, **args)
    sprite("button_danger_focus", base("RUBRICA", "RUBRICA_CLARA", "RUBRICA_OSC", None, ("PIEDRA_LUZ", "PIEDRA_OSC"), False),
           draw_center=False, **args)


def menu_band():
    w, h = 48, 5
    img = new(w, h)
    for x in range(w):
        t = 1.0 if x < 8 else 1.0 - (x - 8) / 39.0
        for y in range(4):
            if 16 * t > B4[y % 4][x % 4] + 4:
                img.putpixel((x, y), c("BRASA_OSC", 110))
        if 16 * t > B4[0][x % 4]:
            img.putpixel((x, 4), c("BRONCE"))
    sprite("menu_band", img, (0, 0, 40, 1), (0, 0, 0, 0), ("tile", "tile"))


def tabs():
    def outline(img, fill):
        rect(img, 1, 1, 15, 12, fill)
        for x in range(2, 14):
            img.putpixel((x, 0), c("TINTA"))
        for y in range(2, 12):
            img.putpixel((0, y), c("TINTA"))
            img.putpixel((15, y), c("TINTA"))
        img.putpixel((1, 1), c("TINTA"))
        img.putpixel((14, 1), c("TINTA"))
        for (x, y) in [(0, 0), (15, 0), (0, 1), (15, 1)]:
            img.putpixel((x, y), CLEAR)
    args = dict(margin=(4, 4, 4, 0), content=(6, 3, 6, 2))
    normal = new(16, 12)
    outline(normal, "PIEDRA_OSC")
    for x in range(2, 14):
        normal.putpixel((x, 1), c("PIEDRA_LUZ"))
        normal.putpixel((x, 11), c("TINTA"))
    sprite("tab_normal", normal, **args)
    sel = new(16, 12)
    outline(sel, "VITELA_ALTA")
    for x in range(2, 14):
        sel.putpixel((x, 1), c("BRONCE_LUZ"))
        sel.putpixel((x, 2), c("BRONCE_OSC"))
        sel.putpixel((x, 11), c("VITELA_ALTA"))
    sprite("tab_selected", sel, **args)
    foc = new(16, 12)
    for x in range(2, 14):
        foc.putpixel((x, 0), c("BRASA_OSC"))
        foc.putpixel((x, 1), c("BRASA"))
    sprite("tab_focus", foc, draw_center=False, **args)


def bars():
    frame = new(8, 8, "HUNDIDO")
    ring(frame, 0, "TINTA")
    ring(frame, 1, "CRIPTA", "BORDE_HUNDIDO")
    sprite("bar_frame", frame, (2, 2, 2, 2), (2, 2, 2, 2))
    focus = new(8, 8)
    ring(focus, 0, "BRASA")
    ring(focus, 1, "VELA")
    sprite("bar_focus", focus, (2, 2, 2, 2), (2, 2, 2, 2), draw_center=False)
    fills = {
        "bar_fill_hp": ["SANGRE_LUZ", "SANGRE", "SANGRE", "SANGRE_OSC"],
        "bar_fill_enemy": ["SANGRE_LUZ", "SANGRE", "SANGRE", "SANGRE", "SANGRE_OSC", "SANGRE_OSC"],
        "bar_fill_soul": ["ALMA_LUZ", "ALMA", "ALMA", "ALMA_OSC"],
        "bar_fill_exp": ["AMATISTA_LUZ", "AMATISTA", "AMATISTA_OSC"],
        "bar_fill_exp_thin": ["AMATISTA"],
        "bar_fill_coin": ["MONEDA_LUZ", "MONEDA", "MONEDA", "MONEDA_OSC"],
        "bar_fill_progress": ["BRONCE_LUZ", "BRONCE", "BRONCE", "BRONCE_OSC"],
        "bar_fill_trail": [c("HUESO", 150)] * 4,
        "bar_fill_flash": ["VELA_BLANCA"] * 4,
    }
    for name, rows in fills.items():
        img = new(4, len(rows))
        for y, color in enumerate(rows):
            for x in range(4):
                img.putpixel((x, y), col(color))
        sprite(name, img, axis=("tile", "stretch"))


def slots():
    def niche(fill, vignette):
        img = new(24, 24, fill)
        ring(img, 0, "TINTA")
        ring(img, 1, "CRIPTA", "BORDE_HUNDIDO")
        ring(img, 2, "HUNDIDO", "NICHO")
        if vignette:
            for y in range(24):
                for x in range(24):
                    if dist(img, x, y) == 3 and (x + y) % 2 == 0:
                        img.putpixel((x, y), c("HUNDIDO"))
        return img
    args = dict(margin=(5, 5, 5, 5), content=(4, 4, 4, 4))
    sprite("slot_normal", niche("NICHO", True), **args)
    sprite("slot_empty", niche("HUNDIDO", False), **args)
    foc = new(24, 24)
    for (cx, cy, sx, sy) in [(0, 0, 1, 1), (23, 0, -1, 1), (0, 23, 1, -1), (23, 23, -1, -1)]:
        for k in range(5):
            color = "VELA" if k < 2 else "BRASA"
            foc.putpixel((cx + sx * k, cy), c(color))
            foc.putpixel((cx, cy + sy * k), c(color))
    sprite("slot_focus", foc, draw_center=False, **args)


def ribbons():
    def ribbon(w, h, depth):
        img = new(w, h)
        half = (h - 1) / 2.0
        for y in range(h):
            cut = int(round(depth - abs(y - half) * depth / half))
            for x in range(cut, w - cut):
                img.putpixel((x, y), c("PIEDRA"))
        src = img.copy()
        for y in range(h):
            for x in range(w):
                if src.getpixel((x, y))[3] == 0:
                    continue
                for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
                    nx, ny = x + dx, y + dy
                    if not (0 <= nx < w and 0 <= ny < h) or src.getpixel((nx, ny))[3] == 0:
                        img.putpixel((x, y), c("TINTA"))
                        break
        for x in range(depth + 1, w - depth - 1):
            img.putpixel((x, 1), c("BRONCE"))
            img.putpixel((x, h - 2), c("BRONCE_OSC"))
        return img
    sprite("ribbon", ribbon(40, 18, 5), (8, 0, 8, 0), (10, 3, 10, 3), ("tile", "stretch"))
    sprite("ribbon_small", ribbon(32, 13, 3), (5, 0, 5, 0), (7, 0, 7, 0), ("tile", "stretch"))


def separators():
    h = new(4, 2)
    for x in range(4):
        h.putpixel((x, 0), c("BRONCE_FILETE"))
        h.putpixel((x, 1), c("TINTA"))
    sprite("separator", h, (0, 1, 0, 1), (0, 0, 0, 0), ("tile", "stretch"))
    v = new(2, 4)
    for y in range(4):
        v.putpixel((0, y), c("BRONCE_FILETE"))
        v.putpixel((1, y), c("TINTA"))
    sprite("separator_v", v, (1, 0, 1, 0), (0, 0, 0, 0), ("stretch", "tile"))


def scrolls():
    track = new(6, 6, "HUNDIDO")
    ring(track, 0, "CRIPTA", "BORDE_HUNDIDO")
    sprite("scroll_track", track, (2, 2, 2, 2), (2, 2, 2, 2))
    for name, tl, br, fill in [("scroll_grabber", "HIERRO_LUZ", "HIERRO_OSC", "HIERRO"),
                               ("scroll_grabber_hot", "BRONCE_LUZ", "BRONCE_OSC", "BRONCE")]:
        g = new(6, 8, fill)
        ring(g, 0, "TINTA")
        ring(g, 1, tl, br)
        sprite(name, g, (3, 3, 3, 3), (0, 0, 0, 0))


# --- Íconos y sprites sueltos (sin 9-slice) ---------------------------------------------------

ICONS = {}      # "id_rampa" o nombre → Image
FRAMES = {}     # nombre → (Image tira, (w, h), count, fps)


def icon(name, img):
    ICONS[name] = img


SEAL = [
    "....ooooo....",
    "..oodrrrdoo..",
    ".odrrRRrrrdo.",
    ".odrRrrrrrdo.",
    "odrRrrorrrrdo",
    "odrrrooorrrdo",
    "odrrooHoorrdo",
    "odrrrooorrrdo",
    "odrrrrorrrrdo",
    ".odrrrrrrrdo.",
    ".oddrrrrrddo.",
    "..oodddddoo..",
    "....ooooo....",
]
SEAL_MINI = [
    "..ooooo..",
    ".odrrrdo.",
    "odrRRrrdo",
    "odRrrrrdo",
    "odrrHrrdo",
    "odrrrrrdo",
    "odrrrrrdo",
    ".oddrddo.",
    "..ooooo..",
]
CREST = [
    "...ooooo...",
    "..oLLLLBo..",
    ".oLLLLLLBo.",
    ".oLooLooBo.",
    ".oLooLooBo.",
    ".oLLLoLLBo.",
    "..oLLLLBo..",
    "..oBoBoBo..",
    "...ooooo...",
]
GEM = ["..L..", ".LBB.", "LBoBD", ".BDD.", "..D.."]
SOUL_FLAME = [
    "...o...",
    "..oLo..",
    "..oLo..",
    ".oLWLo.",
    ".oLWLo.",
    "oLWWWLo",
    "oLWWWBo",
    ".oLLBo.",
    "..ooo..",
]
GRABBER = [
    ".oooo.",
    "oLLLBo",
    "oLBBDo",
    "oLBBDo",
    "oLBBDo",
    "oLBBDo",
    "oLBBDo",
    "oLBBDo",
    "oBDDDo",
    ".oooo.",
]
ARROW = ["ooooooo", ".oVVVo.", "..oVo..", "...o..."]
MAP_MARKERS = {
    "map_player": (["..V..", ".VVV.", "VVVVV", "..V..", "..V.."], {"V": "VELA"}),
    "map_enemy": ([".....", ".R.R.", "..R..", ".R.R.", "....."], {"R": "RUBRICA_CLARA"}),
    "map_stairs": (["LLLLL", "...LD", "..LLD", ".LLLD", "LLLLD"], {"L": "BRONCE_LUZ", "D": "BRONCE_OSC"}),
    "map_chest": ([".....", "MMMMM", "MDMDM", "MMMMM", "....."], {"M": "MONEDA", "D": "MONEDA_OSC"}),
    "map_exit": ([".GGG.", "G...G", "G...G", "G...G", "G...G"], {"G": "MUSGO"}),
}
FLAME = [
    ["...r....", "...rr...", "..rbr...", "..rbbr..", ".rbybr..", ".rbyybr.",
     ".rbyyybr", ".rbywybr", ".rbbwbr.", "..rbbr..", "...rr...", "........"],
    ["....r...", "...rr...", "...rbr..", "..rbbr..", "..rbybr.", ".rbyybr.",
     ".rbyyybr", ".rbywybr", ".rbbwbr.", "..rbbr..", "...rr...", "........"],
    ["........", "...r....", "..rr....", "..rbr...", ".rbbbr..", ".rbyybr.",
     ".rbyyybr", ".rbywybr", ".rbbwbr.", "..rbbr..", "...rr...", "........"],
    ["....r...", "....rr..", "...rbr..", "..rbbr..", ".rbbybr.", ".rbyybr.",
     "rbyyybr.", "rbywybr.", ".rbwbbr.", "..rbbr..", "...rr...", "........"],
]


def small_sprites():
    def from_rows(rows, cmap):
        img = new(len(rows[0]), len(rows))
        stamp(img, 0, 0, rows, cmap)
        return img
    lacre = {"o": "LACRE_SOMBRA", "d": "RUBRICA_OSC", "r": "RUBRICA", "R": "RUBRICA_CLARA", "H": "RUBRICA_CLARA"}
    icon("seal", from_rows(SEAL, lacre))
    icon("seal_mini", from_rows(SEAL_MINI, lacre))
    icon("crest", from_rows(CREST, {"o": "TINTA", "L": "BRONCE_LUZ", "B": "BRONCE"}))
    icon("divider_gem", from_rows(GEM, {"L": "BRONCE_LUZ", "B": "BRONCE", "D": "BRONCE_OSC", "o": "TINTA"}))
    icon("soul_full", from_rows(SOUL_FLAME, {"o": "TINTA", "L": "ALMA", "W": "ALMA_LUZ", "B": "ALMA_OSC"}))
    icon("soul_empty", from_rows(SOUL_FLAME, {"o": "BORDE_HUNDIDO", "L": "HUNDIDO", "W": "HUNDIDO", "B": "HUNDIDO"}))
    icon("slider_grabber", from_rows(GRABBER, {"o": "TINTA", "L": "BRONCE_LUZ", "B": "BRONCE", "D": "BRONCE_OSC"}))
    icon("slider_grabber_focus", from_rows(GRABBER, {"o": "TINTA", "L": "VELA_BLANCA", "B": "VELA", "D": "BRASA"}))
    icon("option_arrow", from_rows(ARROW, {"o": "TINTA", "V": "BRONCE"}))
    icon("option_arrow_focus", from_rows(ARROW, {"o": "TINTA", "V": "VELA"}))
    for name, (rows, cmap) in MAP_MARKERS.items():
        icon(name, from_rows(rows, cmap))
    # Pips (rangos de mejora, puntos sin repartir).
    def pip(rows_colors):
        img = new(4, 7)
        ring(img, 0, "TINTA")
        for y, color in rows_colors:
            for x in (1, 2):
                img.putpixel((x, y), c(color))
        return img
    icon("pip_full", pip([(1, "MONEDA_LUZ"), (2, "MONEDA"), (3, "MONEDA"), (4, "MONEDA"), (5, "MONEDA_OSC")]))
    icon("pip_empty", pip([(1, "HUNDIDO"), (2, "HUNDIDO"), (3, "PIEDRA"), (4, "PIEDRA"), (5, "PIEDRA")]))
    icon("pip_vela", pip([(1, "VELA_BLANCA"), (2, "VELA"), (3, "VELA"), (4, "VELA"), (5, "BRASA")]))
    # Casillas de verificación.
    off = new(10, 10, "NICHO")
    ring(off, 0, "TINTA")
    ring(off, 1, "HUNDIDO", "BORDE_HUNDIDO")
    icon("check_off", off)
    on = off.copy()
    rect(on, 3, 3, 7, 7, "VELA")
    for k in range(3, 7):
        on.putpixel((k, 6), c("BRASA"))
        on.putpixel((6, k), c("BRASA"))
    on.putpixel((3, 3), c("VELA_BLANCA"))
    icon("check_on", on)
    # Cursor: llama de vela (4 cuadros + destello).
    cmap = {"r": "BRASA_OSC", "b": "BRASA", "y": "VELA", "w": "VELA_BLANCA"}
    strip = new(8 * 5, 12)
    for i, rows in enumerate(FLAME):
        stamp(strip, i * 8, 0, rows, cmap)
    stamp(strip, 32, 0, FLAME[1], {k: "VELA_BLANCA" for k in cmap})
    FRAMES["cursor_flame"] = (strip, (8, 12), 5, 8)


# Rampas de color de los íconos: base, luz, sombra.
RAMPS = {
    "bronce": ("BRONCE", "BRONCE_LUZ", "BRONCE_OSC"),
    "vela": ("VELA", "VELA_BLANCA", "BRASA"),
    "apagado": ("CENIZA_OSC", "CENIZA", "PIEDRA_LUZ"),
    "moneda": ("MONEDA", "MONEDA_LUZ", "MONEDA_OSC"),
    "alma": ("ALMA", "ALMA_LUZ", "ALMA_OSC"),
    "sangre": ("RUBRICA", "RUBRICA_CLARA", "RUBRICA_OSC"),
    "amatista": ("AMATISTA", "AMATISTA_LUZ", "AMATISTA_OSC"),
    # Afinidades de almas (hueso marfil, acero oscuro con brillo de hueso).
    "hueso": ("HUESO", "VELA_BLANCA", "CENIZA_OSC"),
    "acero": ("HIERRO_LUZ", "HUESO", "HIERRO_OSC"),
}
# Qué rampas se hornean por ícono (las demás no se usan).
DEFAULT_RAMPS = ("bronce", "vela", "apagado")
ICON_RAMPS = {
    "retiro": ("bronce", "vela", "apagado", "sangre"),
    "stat_vit": ("bronce", "vela", "apagado"), "stat_atq": ("bronce", "vela", "apagado"),
    "stat_esp": ("bronce", "vela", "apagado"), "stat_agi": ("bronce", "vela", "apagado"),
    "stat_sue": ("bronce", "vela", "apagado"),
    "monedas": ("moneda", "apagado"),
    "almas": ("alma", "vela", "apagado"),
    "hp": ("sangre", "apagado"),
    "exp": ("amatista", "apagado"),
    "piso": ("bronce", "vela"),
    "tiempo": ("bronce",),
    "muerte": ("sangre", "bronce", "apagado"),
    "victoria": ("moneda", "bronce"),
    # Afinidades (su color; apagado = nivel sin alcanzar), pactos y estados.
    "afin_hueso": ("hueso", "apagado"), "afin_sangre": ("sangre", "apagado"),
    "afin_sombra": ("amatista", "apagado"), "afin_espiritu": ("alma", "apagado"),
    "afin_acero": ("acero", "apagado"), "afin_fortuna": ("moneda", "apagado"),
    "pacto": ("alma", "vela", "apagado"),
    "estado_aturdido": ("vela",), "estado_marca": ("sangre",), "estado_debil": ("amatista",),
    "escudo": ("bronce", "vela"),
}


def color_icon(mask14, ramp):
    base, light, shade = RAMPS[ramp]
    m = Image.new("L", (16, 16), 0)
    m.paste(mask14, (1, 1))
    mk = m.load()
    img = new(16, 16)
    for y in range(16):
        for x in range(16):
            if mk[x, y]:
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < 16 and 0 <= ny < 16 and mk[nx, ny]:
                        img.putpixel((x, y), c("TINTA"))
                        break
                else:
                    continue
                break
    for y in range(16):
        for x in range(16):
            if not mk[x, y]:
                continue
            up = y == 0 or not mk[x, y - 1]
            down = y == 15 or not mk[x, y + 1]
            color = base
            if up:
                color = light
            if down:
                color = shade
            img.putpixel((x, y), c(color))
    return img


def icons():
    ids = sorted(json.loads(ICON_LIST.read_text(encoding="utf-8")).keys())
    result = {}
    for icon_id in ids:
        mask = Image.open(ICON_MASKS / (icon_id + ".png")).convert("L")
        for ramp in ICON_RAMPS.get(icon_id, DEFAULT_RAMPS):
            icon("%s_%s" % (icon_id, ramp), color_icon(mask, ramp))
        result[icon_id] = list(ICON_RAMPS.get(icon_id, DEFAULT_RAMPS))
    return result


def logo():
    text = json.loads(TEXTS_PATH.read_text(encoding="utf-8"))["app.title"]
    font = ImageFont.truetype(str(LOGO_FONT), 43)
    left, top, right, bottom = font.getbbox(text)
    w, h = right - left + 4, bottom - top + 4
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.fontmode = "1"
    d.text((1 - left, 1 - top), text, font=font, fill=255)
    mk = m.load()
    rows = [y for y in range(h) if any(mk[x, y] for x in range(w))]
    y0, y1 = rows[0], rows[-1]
    span = max(y1 - y0, 1)
    first_cols = []
    # Columnas de la primera letra: la del primer carácter según su ancho.
    first_w = font.getbbox(text[0])[2] - font.getbbox(text[0])[0]
    x_first = min(x for x in range(w) if any(mk[x, y] for y in range(h)))
    first_cols = range(x_first, x_first + first_w + 1)
    img = new(w + 1, h + 1)
    out = new(w + 1, h + 1)
    for y in range(h):
        for x in range(w):
            if not mk[x, y]:
                continue
            t = (y - y0) / span
            ramp = ("RUBRICA_CLARA", "RUBRICA", "RUBRICA_OSC") if x in first_cols else ("BRONCE_LUZ", "BRONCE", "BRONCE_OSC")
            color = ramp[0] if t < 0.30 else (ramp[2] if t > 0.72 else ramp[1])
            img.putpixel((x, y), c(color))
    # Contorno de 1 a (8 vecinos) y sombra (1,1) en tinta.
    for y in range(h + 1):
        for x in range(w + 1):
            near = False
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and mk[nx, ny]:
                        near = True
            shadow = 0 <= x - 1 < w and 0 <= y - 1 < h and mk[x - 1, y - 1]
            if near or shadow:
                out.putpixel((x, y), c("TINTA"))
    out.alpha_composite(img)
    icon("logo", out)
    return text


# --- Atlas ------------------------------------------------------------------------------------

GAP = 2      # a entre piezas
EXTRUDE = 1  # a de borde repetido alrededor de cada pieza


def pack(items):
    """Estanterías ordenadas por alto (desc) y nombre: determinista."""
    width = 512
    order = sorted(items, key=lambda kv: (-kv[1].size[1], kv[0]))
    x, y, shelf_h = GAP, GAP, 0
    places = {}
    for name, img in order:
        w, h = img.size[0] + 2 * EXTRUDE, img.size[1] + 2 * EXTRUDE
        if x + w + GAP > width:
            x, y, shelf_h = GAP, y + shelf_h + GAP, 0
        places[name] = (x + EXTRUDE, y + EXTRUDE)
        x += w + GAP
        shelf_h = max(shelf_h, h)
    height = y + shelf_h + GAP
    height = ((height + 15) // 16) * 16
    atlas = Image.new("RGBA", (width, height), CLEAR)
    for name, img in order:
        px, py = places[name]
        w, h = img.size
        # extrusión: bordes repetidos 1 a hacia afuera
        ext = Image.new("RGBA", (w + 2, h + 2), CLEAR)
        ext.paste(img, (1, 1))
        ext.paste(img.crop((0, 0, w, 1)), (1, 0))
        ext.paste(img.crop((0, h - 1, w, h)), (1, h + 1))
        ext.paste(ext.crop((1, 0, 2, h + 2)), (0, 0))
        ext.paste(ext.crop((w, 0, w + 1, h + 2)), (w + 1, 0))
        atlas.paste(ext, (px - 1, py - 1))
    return atlas, places


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv):
    preview = None
    for a in argv:
        if a.startswith("--preview="):
            preview = a.split("=", 1)[1]
    panel_iron(); panel_inset(); panel_hud()
    card("card", "TINTA", "BRONCE", "BRONCE_OSC", "NOTA")
    card("card_soul", "TINTA", "ALMA", "ALMA_OSC", "ALMA_FONDO")
    card("card_focus", "BRASA", "VELA", "BRASA_OSC", "NOTA")
    portrait_frame("portrait_frame", "TINTA", "BRONCE_LUZ", "BRONCE_OSC", "BRONCE_LUZ")
    portrait_frame("portrait_frame_active", "BRASA_OSC", "VELA", "BRASA", "VELA_BLANCA")
    rank_plaque(); keycap(); tooltip(); buttons(); menu_band(); tabs(); bars(); slots()
    ribbons(); separators(); scrolls(); small_sprites()
    icon_table = icons()
    title = logo()

    items = [(n, img) for n, (img, _) in SPRITES.items()]
    items += [(n, img) for n, img in ICONS.items()]
    items += [(n, strip) for n, (strip, _, _, _) in FRAMES.items()]
    atlas1x, places = pack(items)
    atlas = atlas1x.resize((atlas1x.size[0] * SCALE, atlas1x.size[1] * SCALE), Image.Resampling.NEAREST)

    def region(name, img):
        x, y = places[name]
        return [x * SCALE, y * SCALE, img.size[0] * SCALE, img.size[1] * SCALE]

    manifest = {
        "version": 1,
        "pixel_scale": SCALE,
        "palette_sha256": sha256(PALETTE_PATH),
        "generator_sha256": sha256(Path(__file__)),
        "atlas": ATLAS_RES,
        "size": [atlas.size[0], atlas.size[1]],
        "sprites": {},
        "frames": {},
        "icons": {},
        "singles": {},
        "logo": {},
    }
    for name in sorted(SPRITES):
        img, info = SPRITES[name]
        entry = {"region": region(name, img)}
        entry.update(info)
        manifest["sprites"][name] = entry
    for name in sorted(FRAMES):
        strip, (fw, fh), count, fps = FRAMES[name]
        manifest["frames"][name] = {"region": region(name, strip), "frame": [fw * SCALE, fh * SCALE], "count": count, "fps": fps}
    for icon_id in sorted(icon_table):
        manifest["icons"][icon_id] = {r: region("%s_%s" % (icon_id, r), ICONS["%s_%s" % (icon_id, r)]) for r in icon_table[icon_id]}
    for name in sorted(ICONS):
        if name == "logo" or any(name.startswith(i + "_") and name[len(i) + 1:] in icon_table[i] for i in icon_table):
            continue
        manifest["singles"][name] = region(name, ICONS[name])
    manifest["logo"] = {"region": region("logo", ICONS["logo"]), "text": title}

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT_DIR / "ui_atlas.png", optimize=False)
    (OUT_DIR / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    if preview:
        sheet = Image.new("RGBA", (atlas.size[0] * 2, atlas.size[1] * 2), c("CRIPTA"))
        sheet.alpha_composite(atlas.resize(sheet.size, Image.Resampling.NEAREST))
        sheet.save(preview)
    print("kit: %d piezas, %d íconos, %d tiras → %s (%dx%d)" % (
        len(SPRITES), len(ICONS), len(FRAMES), OUT_DIR / "ui_atlas.png", atlas.size[0], atlas.size[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
