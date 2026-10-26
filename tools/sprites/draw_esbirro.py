"""Esqueleto esbirro en pixel art grueso, dibujado a mano píxel por píxel.

    python3 -I tools/sprites/draw_esbirro.py [--preview=/tmp/esbirro.png]

Escribe assets/sprites/enemies/esqueleto_esbirro.png, _glow.png y .json
(formato en tools/sprites/README.md).

Estilo: sprite chico (~38 px de alto) que en el juego se ve con píxeles
gordos, contorno negro y pocos colores, para que contraste fuerte con el
entorno 3D. Cada parte (calavera, mandíbula, tórax, pelvis, bufanda, escudo,
espada, pies, manos) es un «sello» dibujado a mano en ASCII; los huesos de
brazos y piernas son líneas de píxeles. Cada parte lleva su contorno de 1 px
y se apila en orden. Las animaciones mueven las partes de a píxeles enteros:
nada se rota ni se escala (como en los sprites de 8/16 bits).
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# Paleta corta: contorno, hueso en tres tonos, pupilas (brillan), bufanda,
# acero, oro, madera, cuero y la estela del golpe.
PAL = {
    "K": "#1a1020",  # contorno y huecos
    "W": "#f2ead2",  # hueso
    "B": "#c4b294",  # hueso en sombra
    "D": "#86727a",  # hueso en sombra profunda
    "E": "#ffffff",  # pupilas (máscara de brillo)
    "R": "#e04a3a", "r": "#92243a",  # bufanda
    "S": "#d4dce6", "s": "#7a8296",  # acero
    "G": "#f0b840", "g": "#a06428",  # oro
    "O": "#9a5a30", "o": "#5e3420",  # madera
    "L": "#5a382c",  # cuero
    "X": "#ffffff", "x": "#a8d8ff",  # estela
}
GLOW = "E"


def art(s):
    return [r for r in s.strip("\n").split("\n")]


def flip_x(a):
    w = max(len(r) for r in a)
    return [r.ljust(w, ".")[::-1] for r in a]


def flip_y(a):
    return a[::-1]


def recolor(a, table):
    return ["".join(table.get(c, c) for c in r) for r in a]


# --- Sellos ----------------------------------------------------------------------------
# '.' = transparente. El contorno exterior lo pone cada pieza; adentro, 'K'
# son los huecos (cuencas, nariz, entre costillas).

SKULL = art("""
....WWWWWW....
..WWWWWWWWWW..
.WWWWWWWWKWWB.
WWWWWWWWWWKWBB
WWWWWWWWWWKBBB
WWWWWWWWWWWWBB
WKKWWWWWWWWKKB
WKKKKWWWWKKKKB
WKKEKKWWKKEKKD
BWKEKKWWKKEKBD
.BWWWWKKWWWBD.
..BWWWWWWWBD..
""")
JAW = art("""
WKWKWKWKWK
BWWWWWWWWD
.BBBBBBBD.
""")
SKULL_SIDE = art("""
...WWWWWW.....
.WWWWWWWWWW...
WWWWWWWWWWWW..
WWKWWWWWWWWWW.
WWWKWWWWWWWWW.
WWKWWWWWWWWWWW
BWWWWWWWWKKWWW
BWWWWWWWKKKKKW
BWWWKWWWKKKEKW
.BWWWWWWBKKEKK
..BBWWWWWBWWWK
....BWWWKWKWKW
""")
JAW_SIDE = art("""
WKWKWKWK
BWWWWWWD
.BBBBBD.
""")
SKULL_BACK = art("""
....WWWWWW....
..WWWWWWWWWW..
.WWWWWWKWWWWB.
WWWWWWWWKWWWBB
WWWWWWWKWWWBBB
WWWWWWWWWWWWBB
WWWWWWWWWWWWBB
WWWWWWWWWWWWBD
BWWWWWWWWWWBBD
BBWWWWWWWWBBDD
.BBBWWWWBBBDD.
..BBBBBBBBDD..
""")
RIBS = art("""
BWWWWWWWWB
WKKKWWKKKB
BWWWWWWWWB
.KKKWWKKK.
.BWWWWWWB.
..KKWWKK..
..BWWWWB..
""")
RIBS_SIDE = art("""
WWWWWW.
WKKKWWB
WWWWWWB
WKKKKWB
.WWWWWB
.KKKWB.
..WWB..
""")
RIBS_BACK = art("""
BWWWBBWWWB
WWWBWWBWWB
BKKKWWKKKB
.KKKWWKKK.
.BWWWWWWB.
..KKWWKK..
..BWWWWB..
""")
SPINE = art("""
WB
KK
WB
""")
PELVIS = art("""
WWWBWWBWWB
.WWWKKWWB.
..BW..WB..
""")
PELVIS_SIDE = art("""
WWWWWB
.WWKWB
..BW.B
""")
PELVIS_BACK = art("""
WWWBWWBWWB
.WWWBBWWB.
..BW..WB..
""")
WRAP = art("""
RRRRRRRRRRRR
RRrRRRRRRrRR
.rrRRRRRRrr.
""")
WRAP_SIDE = art("""
RRRRRRR.
RrRRRRRR
.rrRRRr.
""")
# Puntas de la bufanda al viento (salen del lado izquierdo del cuello), tres
# cuadros de flameo.
TAILS = [art("""
RRR..........
RRRRR....RR..
.rRRRRRRRRRR.
..rrRRRRrRRRR
...rRRRRr.rRR
....rrRR...rR
......rR.....
"""), art("""
RRR..........
RRRRRR.......
.rRRRRRRR.RR.
..rrRRRRRRRRR
...rrRRRRr.RR
.....rRRR..rR
.......rR....
"""), art("""
RRR...........
RRRRR.........
.rRRRRRR..RR..
..rrRRRRRRRRRR
....rRRRRrr.rR
......rRRR....
........rR....
""")]
FOOT = art("""
WWWW
BBBB
""")
FOOT_SIDE = art("""
WWWWW
BBBBB
""")
HAND = art("""
WW
BD
""")
SHIELD = art("""
...SSS...
.SSOOOss.
.SOOoOOs.
SOOOoOOOs
SOOOoOOOs
SOOSSsOOs
SOOSssOOs
SOOOoOOOs
SOOOoOOOs
.sOOoOOs.
.ssOOOss.
...sss...
""")
SHIELD_BACK = art("""
...sss...
.ssooos..
.sooOoos.
soooOooos
soooOooos
sLLLLLLLs
sLLLLLLLs
soooOooos
soooOooos
.sooOoos.
..soooss.
...sss...
""")
# El escudo tirado en el piso (se ve casi de canto).
SHIELD_FLAT = art("""
..SSSSSss..
SOOOoOOOOss
.sssssssss.
""")
# Espadas: la mano agarra el mango en GRIP (columna, fila del sello).
SWORDS = {
    "ul": (art("""
S..........
SS.........
.SS........
..sSS......
...sSS.....
....sSS....
.....sSSg..
......sGG..
......gGL..
.........L.
..........G
"""), (8, 8)),
    "u": (art("""
.S.
SSs
SSs
SSs
SSs
SSs
SSs
SSs
GGG
.L.
.L.
.G.
"""), (1, 9)),
    "l": (art("""
.........G..
.SSSSSSSSGLL
SSsssssssG.G
.........G..
"""), (10, 1)),
}


def sword_art(name):
    """'ul', 'u', 'l' y sus espejos: 'ur', 'r', 'dl', 'dr', 'd'."""
    base = {"ul": "ul", "ur": "ul", "dl": "ul", "dr": "ul", "u": "u", "d": "u", "l": "l", "r": "l"}[name]
    a, (gx, gy) = SWORDS[base]
    w, h = max(len(r) for r in a), len(a)
    if name in ("ur", "dr", "r"):
        a, gx = flip_x(a), w - 1 - gx
    if name in ("dl", "dr", "d"):
        a, gy = flip_y(a), h - 1 - gy
    return a, (gx, gy)


# --- Composición -----------------------------------------------------------------------

W, H = 64, 58
CX, GROUND = 32, 54  # centro y fila del piso (la de abajo de los pies)


class Piece:
    """Una capa: píxeles con su color y, alrededor, su contorno (1 px)."""

    def __init__(self, outline="K"):
        self.px = {}
        self.outline = outline

    def stamp(self, a, x, y):
        for j, row in enumerate(a):
            for i, ch in enumerate(row):
                if ch != ".":
                    self.px[(x + i, y + j)] = ch
        return self

    def line(self, a, b, ch, ch2=None):
        """Línea de píxeles; ch2 = segundo píxel al costado (huesos de 2 px)."""
        (x0, y0), (x1, y1) = a, b
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for t in range(n + 1):
            x = round(x0 + (x1 - x0) * t / n)
            y = round(y0 + (y1 - y0) * t / n)
            self.px[(x, y)] = ch
            if ch2:
                if abs(x1 - x0) > abs(y1 - y0):
                    self.px[(x, y + 1)] = ch2
                else:
                    self.px[(x + 1, y)] = ch2
        return self

    def dot(self, x, y, ch):
        self.px[(x, y)] = ch
        return self


def render(pieces):
    grid = np.full((H, W), ".", dtype="<U1")
    for p in pieces:
        solid = np.zeros((H, W), bool)
        for (x, y) in p.px:
            if 0 <= x < W and 0 <= y < H:
                solid[y, x] = True
        if p.outline:
            pad = np.pad(solid, 1)
            ring = ~solid & (pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:])
            grid[ring] = p.outline
        for (x, y), ch in p.px.items():
            if 0 <= x < W and 0 <= y < H:
                grid[y, x] = ch
    return grid


def to_rgba(grid):
    rgba = np.zeros((H, W, 4), np.uint8)
    for ch, hexc in PAL.items():
        m = grid == ch
        rgba[m, :3] = [int(hexc[i:i + 2], 16) for i in (1, 3, 5)]
        rgba[m, 3] = 255
    return rgba, grid == GLOW


# --- Pose ------------------------------------------------------------------------------
# Todo en píxeles relativos a (CX, GROUND): x a la derecha, y hacia abajo
# (negativo = arriba del piso). Los sellos se ubican por su esquina de arriba
# a la izquierda; los miembros son polilíneas (hombro-codo-mano,
# cadera-rodilla-tobillo).

FRONT = {
    "view": "s",
    "skull": (-7, -39), "jaw": (-5, -26), "eyes": 1,
    "wrap": (-6, -23), "tails": (-19, -25), "tail": 0,
    "ribs": (-5, -20), "spine": (-1, -13), "pelvis": (-5, -11),
    "leg_r": [(-3, -9), (-6, -6), (-6, -3)], "leg_l": [(2, -9), (5, -6), (5, -3)],
    "foot_r": (-9, -2), "foot_l": (5, -2),
    "arm_l": [(6, -19), (8, -15), (9, -11)], "shield": (7, -18),
    "arm_r": [(-7, -19), (-9, -15), (-11, -11)], "sword": "ul",
    "smear": None, "sword_front": False, "fx": None,
}
SIDE = {
    "view": "e",
    "skull": (-5, -39), "jaw": (0, -26), "eyes": 1,
    "wrap": (-4, -23), "tails": (-16, -25), "tail": 0,
    "ribs": (-3, -20), "spine": (-3, -13), "pelvis": (-4, -11),
    "leg_n": [(-1, -9), (2, -6), (1, -3)], "leg_f": [(-2, -9), (-1, -6), (-4, -3)],
    "foot_n": (0, -2), "foot_f": (-5, -2),
    "arm_n": [(-1, -19), (-2, -15), (3, -11)], "arm_f": [(-2, -19), (-3, -15), (1, -12)],
    "sword": "ur", "smear": None, "fx": None, "sword_front": False,
}
HEAD = ("skull", "jaw")
LEGS = ("leg_r", "leg_l", "leg_n", "leg_f")
FEET = ("foot_r", "foot_l", "foot_n", "foot_f")


def _move(v, dx, dy):
    if isinstance(v, list):
        return [(x + dx, y + dy) for x, y in v]
    return (v[0] + dx, v[1] + dy)


def shift(P, dx, dy, keys):
    """Corre esas partes (de las piernas, solo la cadera)."""
    Q = dict(P)
    for k in keys:
        if k not in Q:
            continue
        if k in LEGS:
            Q[k] = [_move(Q[k][0], dx, dy)] + Q[k][1:]
        else:
            Q[k] = _move(Q[k], dx, dy)
    return Q


def upper(P):
    """Las partes que se mueven con el cuerpo (no los pies)."""
    return [k for k in P if isinstance(P[k], (tuple, list)) and k not in FEET and k not in LEGS and k != "smear"]


def bob(P, dy, head=0, dx=0):
    """Agacha el cuerpo dy píxeles (también las caderas; las rodillas, la
    mitad; los pies no). head: la cabeza, además."""
    Q = shift(P, dx, dy, upper(P) + [k for k in LEGS if k in P])
    for k in LEGS:
        if k in Q:
            Q[k] = [Q[k][0], _move(Q[k][1], 0, dy // 2)] + Q[k][2:]
    return shift(Q, 0, head, HEAD) if head else Q


def pose(P, **kw):
    Q = dict(P)
    Q.update(kw)
    return Q


def lift(P, foot, dy, dx=0):
    """Levanta un pie (y su tobillo) dy píxeles."""
    leg = {"foot_r": "leg_r", "foot_l": "leg_l", "foot_n": "leg_n", "foot_f": "leg_f"}[foot]
    Q = dict(P)
    Q[foot] = _move(P[foot], dx, -dy)
    hip, knee, ankle = P[leg]
    Q[leg] = [hip, _move(knee, dx // 2, -(dy // 2)), _move(ankle, dx, -dy)]
    return Q


def at(p):
    return (CX + p[0], GROUND + p[1])


def build(P):
    if P.get("pile") is not None:
        return _pile(P)
    return {"s": _front, "e": _side, "n": _back}[P["view"]](P)


def _head(P, pieces, skull, jaw, jaw_w):
    sx, sy = at(P["skull"])
    jx, jy = at(P["jaw"])
    if sy + 13 < jy <= sy + 16:
        # boca abierta: el hueco entre los dientes
        mouth = Piece(None)
        for y in range(sy + 12, jy):
            for x in range(jx + 1, jx + jaw_w - 1):
                mouth.dot(x, y, "K")
        pieces.append(mouth)
    pieces.append(Piece().stamp(jaw, jx, jy))
    if P["eyes"] < 1:
        skull = recolor(skull, {"E": "K"})
    pieces.append(Piece().stamp(skull, sx, sy))


def _leg(pieces, pts, near=True):
    hi, lo = ("W", "B") if near else ("B", "D")
    p = Piece()
    a, k, f = [at(q) for q in pts]
    p.line(a, k, hi)
    p.line(k, f, hi, lo)
    p.dot(k[0], k[1], hi).dot(k[0] + 1, k[1], lo)
    pieces.append(p)


def _arm(pieces, pts, near=True):
    c = "W" if near else "B"
    p = Piece()
    s_, e, h = [at(q) for q in pts]
    p.line(s_, e, c)
    p.line(e, h, c)
    pieces.append(p)


def _sword(pieces, hand, name):
    a, (gx, gy) = sword_art(name)
    hx, hy = at(hand)
    pieces.append(Piece().stamp(a, hx - gx, hy - gy))
    pieces.append(Piece().stamp(HAND, hx - 1, hy - 1))


def _fx(pieces, P):
    if P.get("smear"):
        p = Piece("x")
        for (x, y) in P["smear"]:
            p.dot(CX + x, GROUND + y, "X")
        pieces.append(p)
    if P.get("fx") == "star":
        # golpe de escudo: un destello delante del escudo
        x0, y0 = at(P["shield"])
        p = Piece("x")
        cx, cy = x0 + 4, y0 + 5
        for d in range(-6, 7):
            if abs(d) > 1:
                p.dot(cx + d, cy, "X").dot(cx, cy + d, "X")
        for d in (-4, -3, 3, 4):
            p.dot(cx + d, cy + d, "X").dot(cx + d, cy - d, "X")
        pieces.append(p)


def _front(P):
    pieces = [Piece().stamp(TAILS[P["tail"] % 3], *at(P["tails"]))]
    _leg(pieces, P["leg_r"])
    _leg(pieces, P["leg_l"])
    pieces.append(Piece().stamp(FOOT, *at(P["foot_r"])))
    pieces.append(Piece().stamp(flip_x(FOOT), *at(P["foot_l"])))
    pieces.append(Piece().stamp(PELVIS, *at(P["pelvis"])))
    pieces.append(Piece().stamp(SPINE, *at(P["spine"])))
    pieces.append(Piece().stamp(RIBS, *at(P["ribs"])))
    pieces.append(Piece().stamp(WRAP, *at(P["wrap"])))
    _arm(pieces, P["arm_l"])
    pieces.append(Piece().stamp(HAND, *_move(at(P["arm_l"][2]), -1, -1)))
    pieces.append(Piece().stamp(SHIELD, *at(P["shield"])))
    if not P["sword_front"]:
        _arm(pieces, P["arm_r"])
        _sword(pieces, P["arm_r"][2], P["sword"])
    _head(P, pieces, SKULL, JAW, 10)
    if P["sword_front"]:
        _arm(pieces, P["arm_r"])
        _sword(pieces, P["arm_r"][2], P["sword"])
    _fx(pieces, P)
    return pieces


MIRROR_SWORD = {"ul": "ur", "ur": "ul", "dl": "dr", "dr": "dl", "l": "r", "r": "l", "u": "u", "d": "d"}


def _back(P):
    """De espaldas: la pose de frente espejada, con los sellos de atrás. La
    espada y el escudo quedan delante del esqueleto, o sea detrás para la
    cámara."""
    def mp(v):
        return [(-x, y) for x, y in v]

    def mx(key, w):
        x, y = P[key]
        return (CX - x - w + 1, GROUND + y)

    pieces = []
    _sword(pieces, mp([P["arm_r"][2]])[0], MIRROR_SWORD[P["sword"]])
    pieces.append(Piece().stamp(SHIELD_BACK, *mx("shield", 9)))
    _leg(pieces, mp(P["leg_r"]))
    _leg(pieces, mp(P["leg_l"]))
    pieces.append(Piece().stamp(flip_x(FOOT), *mx("foot_r", 4)))
    pieces.append(Piece().stamp(FOOT, *mx("foot_l", 4)))
    for key, art_, w in (("pelvis", PELVIS_BACK, 10), ("spine", SPINE, 2), ("ribs", RIBS_BACK, 10)):
        pieces.append(Piece().stamp(art_, *mx(key, w)))
    for key in ("arm_l", "arm_r"):
        _arm(pieces, mp(P[key]))
        hx, hy = at(mp([P[key][2]])[0])
        pieces.append(Piece().stamp(HAND, hx - 1, hy - 1))
    pieces.append(Piece().stamp(SKULL_BACK, *mx("skull", 14)))
    pieces.append(Piece().stamp(flip_x(WRAP), *mx("wrap", 12)))
    pieces.append(Piece().stamp(flip_x(TAILS[P["tail"] % 3]), *mx("tails", 14)))
    return pieces


def _side(P):
    pieces = []
    _arm(pieces, P["arm_f"], near=False)
    _leg(pieces, P["leg_f"], near=False)
    pieces.append(Piece().stamp(recolor(FOOT_SIDE, {"W": "B", "B": "D"}), *at(P["foot_f"])))
    pieces.append(Piece().stamp(TAILS[P["tail"] % 3], *at(P["tails"])))
    pieces.append(Piece().stamp(PELVIS_SIDE, *at(P["pelvis"])))
    pieces.append(Piece().stamp(SPINE, *at(P["spine"])))
    pieces.append(Piece().stamp(RIBS_SIDE, *at(P["ribs"])))
    _leg(pieces, P["leg_n"])
    pieces.append(Piece().stamp(FOOT_SIDE, *at(P["foot_n"])))
    pieces.append(Piece().stamp(WRAP_SIDE, *at(P["wrap"])))
    _head(P, pieces, SKULL_SIDE, JAW_SIDE, 7)
    _arm(pieces, P["arm_n"])
    _sword(pieces, P["arm_n"][2], P["sword"])
    return pieces


# --- El montón de huesos (dormido, y el final de la muerte) ---------------------------

def rot90(a):
    """Gira un sello 90° (en sentido horario)."""
    w = max(len(r) for r in a)
    rows = [r.ljust(w, ".") for r in a]
    return ["".join(rows[len(rows) - 1 - j][i] for j in range(len(rows))) for i in range(w)]


SCARF_PILE = art("""
..RRRRR...
.RRrRRRRR.
RRr..rRRRR
.r.....rR.
""")
PILE = {
    "pile": 1, "view": "s", "eyes": 0,
    "skull": (-5, -17), "jaw": (6, -5),
    "ribs": (-11, -10), "pelvis": (-4, -5), "shield": (4, -5), "sword": (-19, 1),
    "scarf": (-10, -7),
    "bones": [((-13, -2), (-4, -3)), ((-6, -2), (3, -1)), ((2, -3), (11, -2)), ((-9, -5), (-1, -2)),
              ((5, -6), (13, -4))],
    "smear": None, "fx": None,
}


def _pile(P):
    pieces = []
    # la espada clavada en diagonal: la punta (abajo a la izquierda del sello)
    # en P["sword"]
    a, _ = sword_art("dl")
    tx, ty = at(P["sword"])
    pieces.append(Piece().stamp(a, tx, ty - len(a) + 1))
    for b0, b1 in P["bones"]:
        p = Piece()
        (x0, y0), (x1, y1) = at(b0), at(b1)
        p.line((x0, y0), (x1, y1), "W")
        p.dot(x0, y0 + 1, "B").dot(x1, y1 + 1, "B").dot(x0 - 1, y0, "W").dot(x1 + 1, y1, "W")
        pieces.append(p)
    pieces.append(Piece().stamp(rot90(RIBS), *at(P["ribs"])))
    pieces.append(Piece().stamp(PELVIS, *at(P["pelvis"])))
    pieces.append(Piece().stamp(SHIELD_FLAT, *at(P["shield"])))
    pieces.append(Piece().stamp(SCARF_PILE, *at(P["scarf"])))
    pieces.append(Piece().stamp(JAW, *at(P["jaw"])))
    skull = SKULL if P["eyes"] >= 1 else recolor(SKULL, {"E": "K"})
    pieces.append(Piece().stamp(skull, *at(P["skull"])))
    _fx(pieces, P)
    return pieces


def frame(P):
    return to_rgba(render(build(P)))


# --- Estela del golpe ------------------------------------------------------------------

def crescent(c, r, a0, a1, w):
    """Medialuna de píxeles alrededor de c (relativo a CX, GROUND), de radio r,
    entre los ángulos a0 y a1 (grados, 0 = derecha, 90 = arriba), más gruesa
    (w px) hacia a1."""
    import math
    out = set()
    lo, hi = min(a0, a1), max(a0, a1)
    for y in range(-r - 2, r + 3):
        for x in range(-r - 2, r + 3):
            d = math.hypot(x, y)
            ang = math.degrees(math.atan2(-y, x))
            for k in (-360, 0, 360):
                if lo <= ang + k <= hi:
                    t = (ang + k - a0) / (a1 - a0)
                    th = 0.6 + (w - 0.6) * max(0.0, min(1.0, t))
                    if r - th <= d <= r:
                        out.add((c[0] + x, c[1] + y))
    return sorted(out)


# --- Animaciones -----------------------------------------------------------------------

GUARD = bob(pose(FRONT, foot_r=(-10, -2), foot_l=(6, -2), leg_r=[(-3, -9), (-7, -6), (-7, -3)],
                 leg_l=[(2, -9), (6, -6), (6, -3)], arm_r=[(-7, -19), (-11, -17), (-12, -20)],
                 arm_l=[(6, -19), (7, -15), (7, -12)], shield=(5, -19)), 1)
HURT = pose(shift(GUARD, 1, -2, HEAD), jaw=_move(GUARD["jaw"], 1, 0), arm_r=[(-7, -18), (-12, -19), (-14, -23)])
HURT = shift(HURT, 0, 2, ("jaw",))


def jaw_open(P, d):
    return pose(P, jaw=_move(P["jaw"], 0, d))


def idle(P, i):
    return [P, bob(pose(P, tail=1), 1), jaw_open(bob(pose(P, tail=2), 1), 1), pose(P, tail=1)][i]


def walk_front(P, i):
    a = bob(P, 1)
    return [a, bob(lift(pose(P, tail=1, arm_r=_move(P["arm_r"], 0, -1)), "foot_r", 2), 0, dx=1),
            bob(pose(P, tail=2), 1),
            bob(lift(pose(P, tail=1, arm_l=_move(P["arm_l"], 0, -1)), "foot_l", 2), 0, dx=-1)][i]


def walk_side(P, i):
    fwd, back = 3, -3
    frames = [
        bob(pose(lift(lift(P, "foot_n", 0, fwd), "foot_f", 0, back), tail=0,
                 arm_n=_move(P["arm_n"], -1, 0), arm_f=_move(P["arm_f"], 1, 0)), 1),
        pose(lift(P, "foot_f", 2, 0), tail=1),
        bob(pose(lift(lift(P, "foot_n", 0, back), "foot_f", 0, fwd), tail=2,
                 arm_n=_move(P["arm_n"], 1, 0), arm_f=_move(P["arm_f"], -1, 0)), 1),
        pose(lift(P, "foot_n", 2, 0), tail=1),
    ]
    return frames[i]


SWING_C = (-7, -19)
ATTACK = [
    jaw_open(pose(shift(GUARD, -1, 0, HEAD), arm_r=[(-7, -19), (-11, -24), (-10, -30)], sword="u"), 1),
    jaw_open(bob(pose(shift(GUARD, -1, 0, HEAD), arm_r=[(-7, -19), (-11, -25), (-9, -31)], sword="u", tail=1), -1), 1),
    jaw_open(bob(pose(GUARD, arm_r=[(-7, -19), (-3, -22), (2, -22)], sword="r", sword_front=True, tail=2,
                      smear=crescent(SWING_C, 22, 115, 20, 3)), 1), 2),
    jaw_open(bob(pose(shift(GUARD, 1, 0, HEAD), arm_r=[(-7, -19), (-1, -15), (5, -12)], sword="dr", sword_front=True,
                      tail=1, smear=crescent(SWING_C, 22, 60, -40, 4)), 2), 2),
    jaw_open(bob(pose(shift(GUARD, 1, 0, HEAD), arm_r=[(-7, -19), (-1, -15), (5, -12)], sword="dr", sword_front=True,
                      tail=0, smear=crescent(SWING_C, 22, 0, -45, 2)), 2), 1),
    GUARD,
]
ATTACK_2 = [
    pose(shift(GUARD, -1, 0, HEAD), arm_l=[(6, -19), (10, -16), (11, -13)], shield=(9, -20)),
    jaw_open(pose(shift(GUARD, -1, -1, HEAD), arm_l=[(6, -19), (10, -16), (12, -14)], shield=(10, -20), tail=1), 1),
    jaw_open(bob(pose(shift(GUARD, 1, 0, HEAD), arm_l=[(6, -19), (3, -17), (0, -14)], shield=(-4, -20), tail=2,
                      fx="star"), 2), 2),
    jaw_open(bob(pose(shift(GUARD, 1, 0, HEAD), arm_l=[(6, -19), (3, -17), (0, -14)], shield=(-4, -20), tail=1,
                      fx="star"), 2), 2),
    jaw_open(pose(GUARD, arm_l=[(6, -19), (5, -16), (3, -13)], shield=(2, -19)), 1),
    GUARD,
]
HIT = [HURT, jaw_open(shift(GUARD, 1, -1, HEAD), 1), GUARD]
HIT_2 = [jaw_open(shift(GUARD, 0, -5, ("skull",)), 1), jaw_open(shift(GUARD, 1, -8, ("skull",)), 1),
         shift(GUARD, 0, 1, HEAD)]


def _fall(P, dy_body, skull, extra):
    """Un cuadro del derrumbe: el cuerpo baja dy_body, la calavera va a skull."""
    Q = bob(P, dy_body)
    Q = pose(Q, skull=skull, jaw=(skull[0] + 2, skull[1] + 13), **extra)
    return Q


DEATH = [
    HURT,
    pose(bob(GUARD, 3, head=2), arm_r=[(-7, -16), (-11, -12), (-12, -8)], sword="dl",
         arm_l=[(6, -16), (8, -12), (9, -8)], shield=(6, -15), jaw=_move(bob(GUARD, 3, head=2)["jaw"], 0, 1)),
    pose(_fall(GUARD, 6, (-6, -28), {}), arm_r=[(-7, -12), (-11, -8), (-13, -4)], sword="l",
         arm_l=[(6, -12), (9, -9), (11, -5)], shield=(6, -11),
         leg_r=[(-3, -4), (-8, -4), (-10, -2)], leg_l=[(2, -4), (7, -4), (9, -2)],
         foot_r=(-12, -2), foot_l=(8, -2)),
    pose(PILE, eyes=1, skull=(-5, -20), jaw=(-3, -8)),
    pose(PILE, eyes=0.5, skull=(-5, -19)),
    PILE,
]
SPAWN = [
    PILE,
    pose(PILE, eyes=1),
    pose(PILE, eyes=1, skull=(-4, -18), jaw=(5, -6)),
    pose(PILE, eyes=1, skull=(-5, -20), jaw=(-3, -8)),
    pose(DEATH[2], eyes=1),
    pose(DEATH[1], eyes=1),
    jaw_open(bob(pose(GUARD, arm_r=[(-7, -19), (-11, -24), (-12, -29)], sword="u", tail=2), -1), 2),
    GUARD,
]

# nombre -> (se repite, duración en s, {dirección: lista de poses})
ANIMS = {
    "idle": (True, 1.4, {"s": [idle(FRONT, i) for i in range(4)], "e": [idle(SIDE, i) for i in range(4)],
                         "n": [idle(pose(FRONT, view="n"), i) for i in range(4)]}),
    "walk": (True, 0.8, {"s": [walk_front(FRONT, i) for i in range(4)], "e": [walk_side(SIDE, i) for i in range(4)],
                         "n": [walk_front(pose(FRONT, view="n"), i) for i in range(4)]}),
    "combat": (True, 1.1, {"s": [idle(GUARD, i) for i in range(4)]}),
    "attack": (False, 0.9, {"s": ATTACK}),
    "attack_2": (False, 0.9, {"s": ATTACK_2}),
    "hit": (False, 0.45, {"s": HIT}),
    "hit_2": (False, 0.45, {"s": HIT_2}),
    "death": (False, 1.3, {"s": DEATH}),
    "spawn": (False, 1.5, {"s": SPAWN}),
    "dormant": (True, 1.0, {"s": [PILE]}),
}


# --- Hoja -----------------------------------------------------------------------------

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "sprites" / "enemies"
SPECIES = "esqueleto_esbirro"
COLUMNS = 16
# Unos 38 px para 1,6 m: cada píxel del sprite mide ~4 cm en el mundo, el
# triple que un texel del entorno (64 px/m). Ese salto es el contraste.
PPM = 24
# Luz pareja (todo el cuadro con la misma luz, colores planos) y un poco de
# luz propia: se lee aunque el pasillo esté oscuro (ver EnemySprite).
FLAT_LIGHT = True
SELF_LIGHT = 0.3


def build_sheet(preview=None):
    frames, meta_anims = [], {}
    for name, (loop, length, dirs) in ANIMS.items():
        count = len(dirs["s"])
        entry = {"loop": loop, "fps": round(count / length, 2), "dirs": {}}
        for d, seq in dirs.items():
            assert len(seq) == count, (name, d)
            for i, P in enumerate(seq):
                rgba, glow = frame(P)
                if rgba[0, :, 3].any() or rgba[:, 0, 3].any() or rgba[:, -1, 3].any() or rgba[-1, :, 3].any():
                    print(f"  aviso: {name}/{d}/{i} toca el borde del cuadro")
                entry["dirs"].setdefault(d, []).append(len(frames))
                frames.append((rgba, glow))
        meta_anims[name] = entry
    alpha = np.zeros((H, W), dtype=bool)
    for rgba, _ in frames:
        alpha |= rgba[..., 3] > 0
    ys, xs = np.nonzero(alpha)
    x0, x1 = max(0, xs.min() - 1), min(W, xs.max() + 2)
    y0, y1 = max(0, ys.min() - 1), min(H, ys.max() + 2)
    frames = [(rgba[y0:y1, x0:x1], glow[y0:y1, x0:x1]) for rgba, glow in frames]
    fw, fh = x1 - x0, y1 - y0
    pivot = [CX - x0, GROUND - y0]
    rows = (len(frames) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * fw, rows * fh), (0, 0, 0, 0))
    glow_sheet = Image.new("L", (COLUMNS * fw, rows * fh), 0)
    for n, (rgba, glow) in enumerate(frames):
        x, y = (n % COLUMNS) * fw, (n // COLUMNS) * fh
        sheet.paste(Image.fromarray(rgba, "RGBA"), (x, y))
        glow_sheet.paste(Image.fromarray(np.where(glow, 255, 0).astype(np.uint8), "L"), (x, y))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT_DIR / f"{SPECIES}.png", optimize=True)
    glow_sheet.save(OUT_DIR / f"{SPECIES}_glow.png", optimize=True)
    meta = {"version": 1, "sheet": f"{SPECIES}.png", "glow": f"{SPECIES}_glow.png", "frame": [int(fw), int(fh)],
            "columns": COLUMNS, "pivot": [int(pivot[0]), int(pivot[1])], "pixels_per_meter": PPM,
            "flat_light": FLAT_LIGHT, "self_light": SELF_LIGHT, "anims": meta_anims}
    (OUT_DIR / f"{SPECIES}.json").write_text(json.dumps(meta, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{SPECIES}: {len(frames)} cuadros de {fw}x{fh}, {len(meta_anims)} animaciones")
    if preview:
        zoom = 4
        rows_ = [ids for e in meta_anims.values() for ids in e["dirs"].values()]
        cells = max(len(r) for r in rows_)
        out = Image.new("RGBA", (cells * fw * zoom, len(rows_) * fh * zoom), (60, 52, 44, 255))
        for r, ids in enumerate(rows_):
            for c, k in enumerate(ids):
                cell = Image.fromarray(frames[k][0], "RGBA").resize((fw * zoom, fh * zoom), Image.NEAREST)
                out.alpha_composite(cell, (c * fw * zoom, r * fh * zoom))
        out.save(preview)
        print(f"vista previa: {preview}")


if __name__ == "__main__":
    args = sys.argv[1:]
    build_sheet(next((a.split("=", 1)[1] for a in args if a.startswith("--preview=")), None))
