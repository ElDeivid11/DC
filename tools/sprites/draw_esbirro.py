"""Esqueleto esbirro dibujado en 2D (pixel art por piezas, ver cutout.py).

    python3 -I tools/sprites/draw_esbirro.py [--preview=/tmp/esbirro.png]

Escribe assets/sprites/enemies/esqueleto_esbirro.png, _glow.png y .json
(formato en tools/sprites/README.md). Cada parte del cuerpo es un dibujo plano
con sus sombras y brillos puestos a mano; la pose solo dice dónde va cada
parte. Coordenadas: px finales, y hacia arriba, origen en el piso entre los
pies; x positivo = derecha de la pantalla (de frente, la mano de la espada
queda a la izquierda).
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cutout import Frame, Palette, band, capsule, circle, ellipse  # noqa: E402

PAL = Palette({
    # hueso
    "hueso_luz": "#fff9e6", "hueso_claro": "#efe2c2", "hueso": "#d6c3a0", "hueso_sombra": "#a8927f",
    "hueso_oscuro": "#735d66", "hueso_linea": "#2a1b28", "grieta": "#6b5059",
    "hueco": "#3c2535", "hueco_oscuro": "#22141e",
    "cuenca": "#110910", "cuenca_borde": "#3e2238", "ojo": "#ffffff",
    # bufanda
    "rojo_luz": "#ff7d55", "rojo": "#db3b2f", "rojo_sombra": "#a3222f", "rojo_oscuro": "#6a1430", "rojo_linea": "#2c0919",
    # metal
    "acero_luz": "#f6fbfd", "acero_claro": "#cdd6e0", "acero": "#99a5b7", "acero_sombra": "#667085",
    "acero_oscuro": "#444a5d", "acero_linea": "#1d2030",
    "oro_luz": "#fff19c", "oro": "#f0b83b", "oro_sombra": "#b46e1f", "oro_linea": "#40200e",
    # madera y cuero
    "madera_luz": "#c07c47", "madera": "#965831", "madera_sombra": "#6f3e24", "madera_oscura": "#4a2617",
    "madera_linea": "#24110b", "cuero": "#5b382b", "cuero_luz": "#83543a",
    # estela del golpe
    "estela": "#ffffff", "estela_borde": "#bfe3ff",
})
GLOW = ("ojo",)
LINE = "hueso_linea"
BONE = ["hueso", "hueso_claro", "hueso_sombra", "hueso_luz"]

# Luz arriba a la izquierda: correr la forma hacia la luz deja la sombra abajo
# a la derecha, y al revés.
TO_LIGHT = (-1.0, 1.0)


def k(v, a):
    return (v[0] * a, v[1] * a)


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def rot(v, deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c)


def mirror(pts):
    return [(-x, y) for x, y in pts]


def ik(a, t, l1, l2, bend):
    """Codo/rodilla entre a y t (bend: +1 o -1 elige de qué lado dobla)."""
    dx, dy = t[0] - a[0], t[1] - a[1]
    d = max(1e-3, min(math.hypot(dx, dy), l1 + l2 - 0.01))
    cos_a = max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)))
    ang = math.atan2(dy, dx) + bend * math.acos(cos_a)
    return (a[0] + l1 * math.cos(ang), a[1] + l1 * math.sin(ang))


# --- Huesos sueltos --------------------------------------------------------------------

def tones(far=False):
    """(luz, base, sombra) del hueso. Lo del lado lejano va un tono más oscuro."""
    return ("hueso", "hueso_sombra", "hueso_oscuro") if far else ("hueso_claro", "hueso", "hueso_sombra")


def bone(f, a, b, r, knob=1.3, ends=(True, True), light=True, far=False):
    """Hueso largo: caña con nudos en las puntas, sombra abajo a la derecha."""
    hi, base, lo = tones(far)
    p = f.piece(LINE)
    polys = [capsule(a, b, r)]
    if ends[0]:
        polys.append(circle(a[0], a[1], r * knob))
    if ends[1]:
        polys.append(circle(b[0], b[1], r * knob))
    p.fill(polys, base)
    p.rim(polys, lo, k(TO_LIGHT, 1.3))
    if light:
        p.rim(polys, hi, k(TO_LIGHT, -1.0))
    return p


def knob(f, c, r, far=False):
    """Rótula o codo: bolita de hueso."""
    hi, base, lo = tones(far)
    p = f.piece(LINE)
    o = circle(c[0], c[1], r)
    p.fill(o, base)
    p.rim(o, lo, k(TO_LIGHT, 1.2))
    p.dot(c[0] - r * 0.35, c[1] + r * 0.35, hi if far else "hueso_luz")
    return p


# --- Calavera de frente ----------------------------------------------------------------

def grin_y(x):
    """Línea de la boca: una sonrisa que sube hacia las puntas."""
    return -16.0 + 2.4 * (x / 10.0) ** 2


def _xs(a, b, n):
    return [a + (b - a) * i / n for i in range(n + 1)]


CRANIUM = ellipse(0, 0.6, 16, 14.2)
FACE = [(-14.8, -1.0), (-15.0, -6.4), (-13.8, -9.6), (-11.2, -11.4), (-10.6, -13.0)] + \
       [(x, grin_y(x)) for x in _xs(-10, 10, 16)] + [(10.6, -13.0), (11.2, -11.4), (13.8, -9.6), (15.0, -6.4), (14.8, -1.0)]
SOCKET_L = [(-1.8, -4.4), (-7.0, -1.6), (-13.0, 1.0), (-14.0, -2.6), (-12.8, -6.8), (-9.4, -9.4),
            (-5.4, -9.6), (-2.6, -8.0), (-1.4, -6.0)]
SOCKET_R = mirror(SOCKET_L)
BROW_L = [(-1.6, -3.6), (-7.0, -0.8), (-12.8, 2.0)]
BROW_R = mirror(BROW_L)
NOSE_L = [(-0.5, -9.4), (-1.4, -9.0), (-2.8, -9.8), (-2.8, -11.4), (-1.2, -12.8), (-0.5, -12.2)]
NOSE_R = mirror(NOSE_L)
JAW = [(-10.5, -13.2)] + [(x, grin_y(x) + 1.5) for x in _xs(-10, 10, 16)] + \
      [(10.5, -13.2), (11.2, -16.6), (9.6, -20.0), (5.2, -21.8), (-5.2, -21.8), (-9.6, -20.0), (-11.2, -16.6)]
RIGHT_HALF = [(0.0, 30), (30, 30), (30, -30), (0.0, -30)]


def skull_front(f, pos, rot_deg=0.0, jaw=0.0, eyes=1.0):
    """pos = centro del cráneo. jaw = cuánto baja la mandíbula (px). eyes: 0 =
    apagados (dormido o muerto), 1 = encendidos; en el medio, una chispa."""
    jaw_pos = add(pos, rot((0, -jaw), rot_deg))
    # interior de la boca (se ve al abrir)
    m = f.piece(None, (pos[0], pos[1], rot_deg, 1, 1))
    m.fill(ellipse(0, -16.8 - jaw * 0.5, 9.0, 2.2 + jaw * 0.55), "cuenca")

    # mandíbula con los dientes de abajo
    j = f.piece(LINE, (jaw_pos[0], jaw_pos[1], rot_deg, 1, 1))
    j.fill(JAW, "hueso")
    j.rim(JAW, "hueso_sombra", k(TO_LIGHT, 2.6))
    j.rim(JAW, "hueso_oscuro", k(TO_LIGHT, 1.0), only=["hueso_sombra"])
    j.shade(ellipse(-3.5, -20.0, 3.2, 1.0), "hueso_claro", only=["hueso"])
    teeth = [(x, grin_y(x) + 0.8) for x in _xs(-9.4, 9.4, 12)] + [(x, grin_y(x) - 3.6) for x in _xs(9.0, -9.0, 12)]
    j.fill(teeth, "hueso_claro")
    j.shade(teeth, "hueso", clip=RIGHT_HALF)
    j.line([(x, grin_y(x) - 3.8) for x in _xs(-8.8, 8.8, 8)], "hueso_oscuro")
    for x in (-8.0, -4.8, -1.6, 1.6, 4.8, 8.0):
        j.line([(x, grin_y(x) - 0.6), (x, grin_y(x) - 3.2)], "hueso_oscuro")

    # cráneo y cara
    s = f.piece(LINE, (pos[0], pos[1], rot_deg, 1, 1))
    s.fill([CRANIUM, FACE], "hueso")
    # luz: media luna arriba a la izquierda y un brillo
    s.rim([CRANIUM], "hueso_claro", (4.0, -4.0))
    s.shade(ellipse(-7.5, 8.4, 3.4, 2.0, rot=35), "hueso_luz")
    # sombra: media luna abajo a la derecha, más oscura junto al borde
    s.rim([CRANIUM, FACE], "hueso_sombra", (-3.6, 3.2))
    s.rim([CRANIUM, FACE], "hueso_oscuro", (-1.2, 1.2), only=["hueso_sombra"])
    # mejillas hundidas bajo los pómulos
    for sd, c in ((-1, "hueso_sombra"), (1, "hueso_oscuro")):
        s.shade([(sd * 15.4, -9.6), (sd * 11.0, -11.0), (sd * 10.0, -14.6), (sd * 12.0, -14.6)], c)
        s.line([(sd * 14.4, -8.2), (sd * 11.6, -10.0), (sd * 9.0, -10.4)], "hueso_claro" if sd < 0 else "hueso_sombra")
    # cuencas con ceño: fondo negro, borde de abajo violeta, ceja clara encima
    for sock, brow in ((SOCKET_L, BROW_L), (SOCKET_R, BROW_R)):
        s.fill(sock, "cuenca")
        s.rim(sock, "cuenca_borde", (-1.4, 2.0), only=["cuenca"])
        s.line(brow, "hueso_luz" if brow is BROW_L else "hueso_claro", only=BONE)
    # arrugas del entrecejo
    s.line([(-0.8, -2.6), (-1.6, 0.2)], "hueso_sombra")
    s.line([(0.8, -2.6), (1.6, 0.2)], "hueso_sombra")
    # pupilas (brillan)
    if eyes >= 0.75:
        s.fill(ellipse(-6.4, -4.8, 2.0, 1.7), "ojo")
        s.fill(ellipse(6.4, -4.8, 2.0, 1.7), "ojo")
    elif eyes > 0.2:
        s.dot(-6.4, -4.8, "ojo")
        s.dot(6.4, -4.8, "ojo")
    # nariz
    s.fill([NOSE_L, NOSE_R], "cuenca")
    # dientes de arriba
    up = [(x, grin_y(x) - 0.5) for x in _xs(-9.8, 9.8, 12)] + [(x, grin_y(x) + 3.8) for x in _xs(9.4, -9.4, 12)]
    s.fill(up, "hueso_claro")
    s.shade(up, "hueso", clip=RIGHT_HALF)
    s.line([(x, grin_y(x) + 3.9) for x in _xs(-9.2, 9.2, 8)], "hueso_oscuro")
    for x in (-6.6, -3.3, 0.0, 3.3, 6.6):
        s.line([(x, grin_y(x) + 3.4), (x, grin_y(x) + 0.4)], "hueso_oscuro")
    # comisuras
    s.line([(-10.0, -13.6), (-11.2, -11.8)], "hueso_oscuro")
    s.line([(10.0, -13.6), (11.2, -11.8)], "hueso_oscuro")
    # grietas
    s.line([(4.0, 14.4), (6.0, 10.8), (5.0, 8.4), (8.0, 5.6)], "grieta")
    s.line([(6.0, 10.8), (8.6, 10.0)], "grieta")
    s.line([(-9.0, 11.6), (-7.0, 9.0), (-8.2, 6.8)], "grieta")
    return s


# --- Torso de frente -------------------------------------------------------------------

CAGE = [(-7.5, 9.6), (-10.4, 7.0), (-10.8, 2.5), (-10.0, -2.5), (-7.6, -5.6), (-2.0, -6.4),
        (2.0, -6.4), (7.6, -5.6), (10.0, -2.5), (10.8, 2.5), (10.4, 7.0), (7.5, 9.6)]
RIBS = [  # (altura en el esternón, cuánto se abre, cuánto cae al costado)
    (7.0, 10.4, 3.6), (3.4, 11.4, 4.6), (-0.2, 11.0, 5.0), (-3.8, 9.4, 4.4)]


def ribcage_front(f, pos, rot_deg=0.0):
    p = f.piece(LINE, (pos[0], pos[1], rot_deg, 1, 1))
    p.fill(CAGE, "hueco")
    p.shade([(4.0, 12), (14, 12), (14, -12), (4.0, -12)], "hueco_oscuro")
    ribs = []
    for i, (y0, w, drop) in enumerate(RIBS):
        for sd in (-1, 1):
            pts = [(sd * 1.2, y0), (sd * w * 0.4, y0 + 0.7), (sd * w * 0.72, y0 + 0.2),
                   (sd * w * 0.93, y0 - drop * 0.4), (sd * w, y0 - drop)]
            ribs.append(band(pts, 2.4, 1.6))
    clav = [band([(-1.4, 9.2), (-6.0, 10.6), (-11.2, 9.4)], 2.2), band([(1.4, 9.2), (6.0, 10.6), (11.2, 9.4)], 2.2)]
    stern = capsule((0, 9.0), (0, -4.0), 1.7, 1.2)
    float_ribs = [band([(sd * 4.0, -6.6), (sd * 6.6, -7.0), (sd * 8.4, -8.6)], 1.8, 1.4) for sd in (-1, 1)]
    p.fill(ribs + clav + [stern] + float_ribs, "hueso")
    ribs = ribs + float_ribs
    # cada costilla con su panza en sombra; el lado derecho más oscuro
    p.rim(ribs + clav, "hueso_sombra", (0, 1.1), only=["hueso"])
    p.rim(ribs + clav, "hueso_claro", (0, -1.0), only=["hueso"], clip=[(-14, 14), (2, 14), (2, -14), (-14, -14)])
    p.shade([(5.5, 14), (14, 14), (14, -14), (5.5, -14)], "hueso_sombra", only=["hueso"])
    p.rim(ribs, "hueso_oscuro", (-1.0, 0.8), only=["hueso_sombra"], clip=[(4, 14), (14, 14), (14, -14), (4, -14)])
    p.rim([stern], "hueso_sombra", (-1.0, 0.0), only=["hueso"])
    return p


def pelvis_front(f, pos, rot_deg=0.0):
    p = f.piece(LINE, (pos[0], pos[1], rot_deg, 1, 1))
    wing_l = ellipse(-6.6, 1.6, 6.2, 3.8, rot=-32)
    wing_r = ellipse(6.6, 1.6, 6.2, 3.8, rot=32)
    sac = [(-3.0, 4.2), (3.0, 4.2), (1.6, -3.0), (-1.6, -3.0)]
    pub = band([(-7.8, -1.2), (-5.4, -4.4), (-1.6, -5.4), (1.6, -5.4), (5.4, -4.4), (7.8, -1.2)], 3.0)
    polys = [wing_l, wing_r, sac, pub]
    p.fill(polys, "hueso")
    p.rim(polys, "hueso_claro", (1.2, -1.2))
    p.rim(polys, "hueso_sombra", (-1.8, 1.8))
    p.rim(polys, "hueso_oscuro", (-0.8, 0.8), only=["hueso_sombra"], clip=RIGHT_HALF)
    # el sacro, un poco hundido entre las alas
    p.line([(-2.4, 3.6), (-1.2, -2.0)], "hueso_sombra")
    p.line([(2.4, 3.6), (1.2, -2.0)], "hueso_sombra")
    p.fill([ellipse(-4.8, -2.6, 1.4, 1.0), ellipse(4.8, -2.6, 1.4, 1.0)], "hueco")
    return p


def spine(f, a, b, n=3):
    """Vértebras sueltas entre a (abajo) y b (arriba)."""
    p = f.piece(LINE)
    ang = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0])) - 90
    for i in range(n):
        t = (i + 0.5) / n
        c = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        p.fill(ellipse(c[0], c[1], 2.4, 0.9, rot=ang), "hueso")
    p.rim([ellipse(a[0] + (b[0] - a[0]) * (i + 0.5) / n, a[1] + (b[1] - a[1]) * (i + 0.5) / n, 2.4, 0.9, rot=ang)
           for i in range(n)], "hueso_sombra", (-0.8, 0.8))
    return p


# --- Manos y pies ----------------------------------------------------------------------

def fist(f, pos, rot_deg, side, far=False):
    """Puño cerrado alrededor de un mango que va por el eje y local: cuatro
    dedos apilados y el pulgar arriba. side = -1 lo espeja."""
    hi, base, lo = tones(far)
    p = f.piece(LINE, (pos[0], pos[1], rot_deg, side, 1))
    back = ellipse(-1.6, -0.6, 2.6, 3.2)
    p.fill(back, lo)
    fingers = [ellipse(1.2, y, 2.4, 1.0) for y in (1.6, -0.2, -2.0)]
    p.fill(fingers, base)
    p.rim(fingers, lo, (0, 0.9), only=[base])
    p.rim(fingers, hi, (0.9, -0.6), only=[base])
    thumb = ellipse(-1.0, 2.6, 2.0, 1.1, rot=10)
    p.fill(thumb, hi)
    return p


def foot_front(f, ankle, side, rot_deg=0.0):
    """Pie de frente, con la punta hacia afuera (side = -1 izquierda)."""
    base = add(ankle, rot((0, -4.4), rot_deg))
    p = f.piece(LINE, (base[0], base[1], rot_deg, side, 1))
    sole = [(-3.0, 0.0), (-3.4, 1.6), (-1.8, 3.4), (1.6, 3.8), (4.6, 2.6), (7.2, 1.4), (7.4, 0.0)]
    toes = [circle(x, 1.0, 1.15) for x in (1.0, 3.0, 5.0, 6.8)]
    p.fill([sole] + toes, "hueso")
    p.rim([sole] + toes, "hueso_sombra", (0, 1.0))
    for x in (2.0, 4.0, 6.0):
        p.line([(x, 0.0), (x, 1.4)], "hueso_oscuro")
    talus = circle(0, 4.4, 2.3)
    q = f.piece(LINE, (base[0], base[1], rot_deg, side, 1))
    q.fill(talus, "hueso")
    q.rim(talus, "hueso_sombra", (-1.0 * side, 1.0))
    return p


# --- Equipo ----------------------------------------------------------------------------

def sword(f, pos, rot_deg):
    """Espada corta: origen en el mango, hoja hacia +y local."""
    g = f.piece("oro_linea", (pos[0], pos[1], rot_deg, 1, 1))
    pom = circle(0, -5.0, 1.8)
    g.fill(pom, "oro")
    g.dot(-0.6, -4.4, "oro_luz")
    h = f.piece("madera_linea", (pos[0], pos[1], rot_deg, 1, 1))
    h.fill([(-1.2, -3.6), (1.2, -3.6), (1.2, 2.6), (-1.2, 2.6)], "cuero")
    h.line([(-1.0, 0.0), (-1.0, 2.0)], "cuero_luz")
    b = f.piece("acero_linea", (pos[0], pos[1], rot_deg, 1, 1))
    blade = [(-2.3, 3.6), (-2.1, 21.5), (0, 26.0), (2.1, 21.5), (2.3, 3.6)]
    b.fill(blade, "acero_claro")
    b.shade([(0, 2), (3, 2), (3, 30), (0, 30)], "acero")
    b.rim(blade, "acero_sombra", (-1.0, 0.0), only=["acero"])
    b.line([(-1.2, 6.0), (-1.2, 20.5)], "acero_luz")
    b.dot(-0.6, 23.5, "acero_luz")
    gu = f.piece("oro_linea", (pos[0], pos[1], rot_deg, 1, 1))
    guard = [band([(-5.6, 4.6), (-3.0, 3.4), (0, 3.0), (3.0, 3.4), (5.6, 4.6)], 2.4),
             circle(-5.6, 4.8, 1.3), circle(5.6, 4.8, 1.3)]
    gu.fill(guard, "oro")
    gu.rim(guard, "oro_sombra", (0, 1.0))
    gu.line([(-4.6, 4.6), (-2.0, 3.8)], "oro_luz")
    return b


def shield_front(f, pos, rot_deg=0.0, sx=1.0, sy=1.0):
    """Escudo redondo de madera con aro y umbo de hierro, visto de frente pero
    girado hacia afuera (un óvalo)."""
    t = (pos[0], pos[1], rot_deg, sx, sy)
    p = f.piece("acero_linea", t)
    outer = ellipse(0, 0, 9.6, 15.0)
    wood = ellipse(0.5, 0, 7.4, 12.8)
    p.fill(outer, "acero")
    p.rim(outer, "acero_claro", (1.4, -1.4))
    p.rim(outer, "acero_sombra", (-1.6, 1.0))
    p.fill(wood, "madera")
    p.shade([(3.0, 20), (12, 20), (12, -20), (3.0, -20)], "madera_sombra", only=["madera"])
    p.rim(wood, "madera_oscura", (1.0, -1.4), only=["madera", "madera_sombra"])
    for x in (-3.4, 0.6, 4.6):
        p.line([(x, 12.6), (x, -12.6)], "madera_oscura", only=["madera", "madera_sombra"])
    for x in (-5.6, -1.6):
        p.line([(x, 9.6), (x, -6.0)], "madera_luz", only=["madera"])
    for a in range(0, 360, 45):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        p.dot(8.5 * c, 13.9 * s, "acero_luz" if c < 0.2 and s > -0.2 else "acero_oscuro", only=["acero", "acero_claro", "acero_sombra"])
    u = f.piece("acero_linea", t)
    boss = ellipse(0.8, 0.0, 3.0, 3.5)
    u.fill(boss, "acero")
    u.rim(boss, "acero_sombra", (-1.2, 1.2))
    u.shade(ellipse(0.0, 0.9, 1.3, 1.3), "acero_claro")
    u.dot(-0.4, 1.4, "acero_luz")
    return p


def scarf_tails(f, anchor, phase=0.0, wind=1.0, rot_deg=0.0, mx=1.0):
    """Las dos puntas de la bufanda, que flamean hacia la izquierda (mx = -1:
    hacia la derecha). wind 0 = cuelgan."""
    def W(x, y):
        return add(anchor, rot((x * mx, y), rot_deg))

    droop = math.radians((1.0 - min(wind, 1.0)) * 70.0)
    tails = f.piece("rojo_linea")
    for (y0, ln, w0, w1, dy, ph) in ((2.6, 27.0, 5.0, 6.4, 5.0, 0.0), (-0.6, 20.0, 4.2, 5.2, -0.5, 1.6)):
        n = 12
        pts = []
        for i in range(n + 1):
            t = i / n
            wave = 3.2 * t * math.sin(phase * 2 * math.pi + ph - 5.6 * t) * max(wind, 0.25)
            reach = ln * t * (0.75 + 0.25 * min(wind, 1.2))
            pts.append(W(-7.0 - reach * math.cos(droop) + wave * math.sin(droop),
                         y0 + dy * t * wind - reach * math.sin(droop) + wave * math.cos(droop)))
        left, right = [], []
        for i, (x, y) in enumerate(pts):
            a = pts[min(i + 1, n)]
            b = pts[max(i - 1, 0)]
            dx, dyy = a[0] - b[0], a[1] - b[1]
            ln_ = math.hypot(dx, dyy) or 1.0
            nx, ny = -dyy / ln_, dx / ln_
            t = i / n
            w = (w0 + (w1 - w0) * t) / 2 * (1.0 + 0.18 * math.sin(phase * 2 * math.pi + ph * 2 - 9.0 * t))
            left.append((x + nx * w, y + ny * w))
            right.append((x - nx * w, y - ny * w))
        # punta rota en dos: una muesca hacia adentro en el extremo
        ex, ey = pts[-1][0] - pts[-2][0], pts[-1][1] - pts[-2][1]
        el = math.hypot(ex, ey) or 1.0
        mid = ((left[-1][0] + right[-1][0]) / 2, (left[-1][1] + right[-1][1]) / 2)
        tip = (mid[0] - ex / el * 2.4, mid[1] - ey / el * 2.4)
        poly = left + [tip] + right[::-1]
        tails.fill(poly, "rojo")
        tails.rim(poly, "rojo_sombra", (0.4 * mx, 1.6))
        tails.rim(poly, "rojo_luz", (0, -1.0), only=["rojo"])
        # pliegues: bandas oscuras que cruzan la tela donde la onda baja
        for i in range(2, n - 1):
            t = i / n
            if math.sin(phase * 2 * math.pi + ph - 5.6 * t) * wind < -0.55:
                tails.line([left[i], right[i]], "rojo_sombra", only=["rojo", "rojo_luz"])
    return tails


WRAP_FRONT = [(-11.0, 4.0), (-6.0, 5.8), (0, 6.2), (6.0, 5.6), (10.8, 3.4), (11.6, 0.6), (10.6, -1.0), (5.6, -3.4),
              (1.0, -5.4), (-1.0, -5.4), (-5.6, -3.6), (-10.8, -1.4), (-11.8, 0.8)]
WRAP_SIDE = [(-6.8, 3.4), (-1.0, 5.6), (5.0, 4.6), (7.6, 1.6), (6.8, -2.4), (1.6, -4.8), (-4.6, -3.8), (-7.6, -0.4)]


def scarf_wrap(f, neck, rot_deg=0.0, mx=1.0, shape=WRAP_FRONT, knot=(-9.6, 1.0), folds=True):
    """La vuelta de la bufanda al cuello, con el nudo del lado de las puntas."""
    def W(x, y):
        return add(neck, rot((x * mx, y), rot_deg))

    wrap = f.piece("rojo_linea")
    poly = [W(x, y) for x, y in shape]
    wrap.fill(poly, "rojo")
    wrap.rim(poly, "rojo_sombra", (-1.4, 2.2))
    wrap.rim(poly, "rojo_oscuro", (-0.8, 1.0), only=["rojo_sombra"])
    wrap.rim(poly, "rojo_luz", (1.4, -1.2), only=["rojo"])
    if folds:
        wrap.line([W(-8.6, 1.6), W(-4.0, 0.2), W(0.4, -2.6)], "rojo_sombra")
        wrap.line([W(3.0, 2.6), W(8.0, 1.4)], "rojo_sombra")
    else:
        wrap.line([W(-4.0, 2.4), W(1.0, 0.2), W(5.0, 0.6)], "rojo_sombra")
    if knot:
        kn = f.piece("rojo_linea")
        kc = W(*knot)
        kp = ellipse(kc[0], kc[1], 2.8, 3.2, rot=20 * mx + rot_deg)
        kn.fill(kp, "rojo")
        kn.rim(kp, "rojo_sombra", (-1.0, 1.2))
        kn.rim(kp, "rojo_luz", (0.8, -0.8), only=["rojo"])
    return wrap


def scarf_front(f, neck, phase=0.0, wind=1.0, rot_deg=0.0, mx=1.0):
    """Bufanda roja: vuelta al cuello + dos puntas que flamean al costado."""
    scarf_tails(f, neck, phase, wind, rot_deg, mx)
    return scarf_wrap(f, neck, rot_deg, mx)


# --- Pose de frente --------------------------------------------------------------------

FRONT = {
    "hip": (0.0, 29.0), "lean": 0.0,
    "head": (0.0, 0.0, 0.0), "jaw": 0.0,
    "hand_r": (-21.0, 35.0), "hand_l": (21.0, 37.0),
    "foot_r": (-16.5, 4.4), "foot_l": (16.5, 4.4),
    "sword": 38.0, "shield": (6.0, 0.0, 0.0, 1.0),
    "scarf": 0.0, "wind": 1.0,
}
ARM = (13.5, 13.0)
LEG = (13.5, 13.0)


def front_rig(P):
    """Pose de frente -> dónde va cada parte (el «rig»)."""
    hip = P["hip"]
    lean = P["lean"]
    chest = add(hip, rot((0, 21.0), lean))
    neck = add(hip, rot((0, 31.8), lean))
    hd = P["head"]
    head = add(add(neck, rot((0, 25.4), lean)), (hd[0], hd[1]))
    R = {
        "skull": (head[0], head[1], hd[2] + lean), "jaw": P["jaw"],
        "ribs": (chest[0], chest[1], lean), "pelvis": (hip[0], hip[1], lean * 0.3),
        "spine": (add(hip, rot((0, 3.4), lean)), add(chest, rot((0, -6.0), lean))),
        "scarf": (neck[0], neck[1], lean, P["scarf"], P["wind"]),
        "scale": P.get("scale", 1.0), "smear": P.get("smear"), "eyes": P.get("eyes", 1.0),
        "sword_front": P.get("sword_front", False),
    }
    for tag, side, foot in (("r", -1, P["foot_r"]), ("l", 1, P["foot_l"])):
        hj = add(hip, rot((side * 6.8, -2.0), lean * 0.3))
        kn = ik(hj, foot, LEG[0], LEG[1], side)
        R["thigh_" + tag] = (hj, kn)
        R["shin_" + tag] = (kn, foot)
        R["fib_" + tag] = (add(kn, (side * 2.0, 0)), add(foot, (side * 1.4, 0.6)))
        R["knee_" + tag] = kn
        R["foot_" + tag] = (foot[0], foot[1], 0.0)
    for tag, side, hand in (("r", -1, P["hand_r"]), ("l", 1, P["hand_l"])):
        sh = add(chest, rot((side * 11.6, 8.0), lean))
        el = ik(sh, hand, ARM[0], ARM[1], side)
        R["hum_" + tag] = (sh, el)
        R["fore_" + tag] = (el, hand)
        R["elbow_" + tag] = el
    R["hand_r"] = (P["hand_r"][0], P["hand_r"][1], P["sword"])
    R["sword"] = (P["hand_r"][0], P["hand_r"][1], P["sword"])
    sp = P["shield"]
    R["hand_l"] = (P["hand_l"][0], P["hand_l"][1], -10.0)
    R["shield"] = (P["hand_l"][0] + sp[0], P["hand_l"][1] + sp[1], sp[2], sp[3])
    return R


def pile_rig():
    """El esqueleto desarmado: un montón de huesos con la calavera arriba y la
    espada clavada al lado (dormant y último cuadro de death)."""
    return {
        "skull": (9.0, 18.5, -22.0), "jaw": 1.4, "eyes": 0.0,
        "ribs": (-8.0, 12.0, 64.0), "pelvis": (-3.0, 6.0, 12.0),
        "spine": ((-6.0, 4.0), (-16.0, 6.5)),
        "scarf": (-9.0, 12.5, 14.0, 0.35, 0.8),
        "thigh_r": ((-15.0, 3.0), (-2.0, 5.0)), "shin_r": ((-24.0, 2.2), (-11.0, 2.0)),
        "fib_r": ((-23.0, 4.6), (-12.0, 4.4)), "knee_r": (-12.0, 2.6), "foot_r": (-25.0, 4.4, 0.0),
        "thigh_l": ((14.0, 3.2), (2.0, 7.0)), "shin_l": ((10.0, 2.0), (23.0, 2.2)),
        "fib_l": ((11.0, 4.4), (22.0, 4.6)), "knee_l": (11.0, 2.6), "foot_l": (24.0, 4.4, 0.0),
        "hum_r": ((-18.0, 7.0), (-6.0, 10.0)), "fore_r": ((-9.0, 3.0), (-20.0, 6.5)), "elbow_r": (-7.0, 9.0),
        "hum_l": ((6.0, 11.0), (18.0, 8.0)), "fore_l": ((16.0, 4.0), (27.0, 3.0)), "elbow_l": (17.0, 6.5),
        "hand_r": (-22.0, 5.0, 100.0), "hand_l": (28.5, 4.0, -80.0),
        "sword": (-21.0, 25.0, 172.0), "shield": (19.0, 9.0, 74.0, 0.8),
        "scale": 1.0, "smear": None,
    }


def draw_front(f, R):
    for tag, side in (("r", -1), ("l", 1)):
        bone(f, *R["fib_" + tag], 1.0, knob=1.0, light=False)
        bone(f, *R["thigh_" + tag], 2.2, ends=(False, True))
        bone(f, *R["shin_" + tag], 1.9, ends=(False, True))
        x, y, r = R["foot_" + tag]
        foot_front(f, (x, y), side, r)
        knob(f, R["knee_" + tag], 2.5)
    pelvis_front(f, R["pelvis"][:2], R["pelvis"][2])
    spine(f, *R["spine"], 3)
    ribcage_front(f, R["ribs"][:2], R["ribs"][2])
    sx, sy, sr, ph, wind = R["scarf"]
    scarf_front(f, (sx, sy), ph, wind, sr)

    # brazo del escudo (derecha de la pantalla)
    bone(f, *R["hum_l"], 2.0, ends=(True, False))
    _forearm(f, *R["fore_l"])
    knob(f, R["elbow_l"], 2.2)
    hx, hy, hr = R["hand_l"]
    fist(f, (hx, hy), hr, -1)
    x, y, r, sc = R["shield"]
    shield_front(f, (x, y), r, sc, sc)

    if not R.get("sword_front"):
        _sword_arm(f, R)
    skull_front(f, R["skull"][:2], R["skull"][2], R["jaw"], R.get("eyes", 1.0))
    if R.get("smear"):
        smear(f, R["smear"])
    if R.get("sword_front"):
        _sword_arm(f, R)


def _sword_arm(f, R):
    """Brazo de la espada (izquierda de la pantalla)."""
    bone(f, *R["hum_r"], 2.0, ends=(True, False))
    _forearm(f, *R["fore_r"])
    knob(f, R["elbow_r"], 2.2)
    sword(f, R["sword"][:2], R["sword"][2])
    hx, hy, hr = R["hand_r"]
    fist(f, (hx, hy), hr, 1)


def smear(f, poly):
    """Estela blanca del golpe (el área que barrió la hoja)."""
    p = f.piece("estela_borde")
    p.fill(poly, "estela")
    p.rim(poly, "estela_borde", (0.0, 1.4))


BLADE = 25.0


def sweep(P0, P1, n=10):
    """Polígono que barre la hoja de la espada entre dos poses: la punta por
    afuera y, por adentro, un punto de la hoja que se acerca a la punta hacia
    el principio del barrido (la estela se afina atrás)."""
    tips, inner = [], []
    for i in range(n + 1):
        t = i / n
        P = lerp_pose(P0, P1, t)
        hand, ang = P["hand_r"], P["sword"]
        tips.append(add(hand, rot((0, BLADE + 0.5), ang)))
        inner.append(add(hand, rot((0, BLADE + 0.5 - 13.0 * t ** 1.3), ang)))
    return tips + inner[::-1]


def _forearm(f, a, b, far=False):
    """Radio y cúbito: dos huesitos paralelos."""
    d = (b[0] - a[0], b[1] - a[1])
    ln = math.hypot(*d) or 1.0
    n = (-d[1] / ln * 1.1, d[0] / ln * 1.1)
    bone(f, add(a, n), add(b, n), 0.95, knob=1.15, light=False, far=far)
    bone(f, add(a, k(n, -1)), add(b, k(n, -1)), 1.05, knob=1.15, far=far)


def render_rig(R, size=(120, 128), origin=(60, 120)):
    """Vista previa de un rig suelto (para probar poses): -> (RGBA, brillo)."""
    f = Frame(size[0], size[1], origin, PAL, R["scale"])
    draw_any(f, R)
    return f.render(GLOW)


def draw_any(f, R):
    {"s": draw_front, "e": draw_side, "n": draw_back}[R.get("view", "s")](f, R)


# --- Vista de perfil (mira a la derecha de la pantalla) -------------------------------
# La mano de la espada queda del lado cercano; el escudo, del lado lejano.

CRANIUM_S = ellipse(-1.0, 0.8, 15.2, 14.0)
FACE_S = [(4.0, 2.0), (11.0, 3.0), (14.6, 0.0), (15.6, -4.6), (17.2, -7.2), (17.4, -10.2), (16.8, -13.8),
          (8.4, -14.0), (4.0, -12.4), (0.0, -9.6)]
SOCKET_S = [(5.0, 0.4), (9.4, -1.0), (13.8, -3.8), (14.4, -6.4), (12.4, -9.0), (8.2, -9.2), (5.0, -6.2)]
BROW_S = [(4.6, 1.6), (9.4, 0.2), (14.6, -2.8)]
NOSE_S = [(15.4, -6.4), (17.8, -7.4), (17.8, -10.0), (15.2, -9.4)]
HINGE_S = (1.0, -9.0)
JAW_S = [(-1.6, -7.4), (2.4, -8.0), (3.4, -13.6), (8.4, -13.8), (16.4, -13.8), (16.8, -18.0), (15.2, -21.6),
         (9.2, -22.8), (2.4, -22.0), (-0.6, -18.8), (-2.0, -12.0)]


def skull_side(f, pos, rot_deg=0.0, jaw=0.0, eyes=1.0):
    """Calavera de perfil. pos = centro del cráneo; la mandíbula gira en su
    bisagra (jaw en px de apertura, ~5° por px)."""
    hw = add(pos, rot(HINGE_S, rot_deg))
    m = f.piece(None, (pos[0], pos[1], rot_deg, 1, 1))
    m.fill(ellipse(11.0, -14.8, 5.6, 1.2 + jaw * 0.9), "cuenca")
    j = f.piece(LINE, (hw[0], hw[1], rot_deg + jaw * 5.0, 1, 1))
    hx, hy = HINGE_S
    jl = [(x - hx, y - hy) for x, y in JAW_S]
    j.fill(jl, "hueso")
    j.rim(jl, "hueso_sombra", k(TO_LIGHT, 2.4))
    j.rim(jl, "hueso_oscuro", k(TO_LIGHT, 1.0), only=["hueso_sombra"])
    teeth = [(8.8 - hx, -13.6 - hy), (16.4 - hx, -13.6 - hy), (16.4 - hx, -18.2 - hy), (8.8 - hx, -18.2 - hy)]
    j.fill(teeth, "hueso_claro")
    j.line([(8.8 - hx, -18.4 - hy), (16.2 - hx, -18.4 - hy)], "hueso_oscuro")
    for x in (11.0, 13.8):
        j.line([(x - hx, -15.2 - hy), (x - hx, -17.8 - hy)], "hueso_oscuro")
    j.line([(2.0 - hx, -9.0 - hy), (2.6 - hx, -13.0 - hy)], "hueso_sombra")

    s = f.piece(LINE, (pos[0], pos[1], rot_deg, 1, 1))
    s.fill([CRANIUM_S, FACE_S], "hueso")
    s.rim([CRANIUM_S], "hueso_claro", (4.0, -4.0))
    s.shade(ellipse(-7.0, 8.6, 3.6, 2.0, rot=35), "hueso_luz")
    s.rim([CRANIUM_S, FACE_S], "hueso_sombra", (-3.4, 3.2))
    s.rim([CRANIUM_S, FACE_S], "hueso_oscuro", (-1.2, 1.2), only=["hueso_sombra"])
    # pómulo (arco que va de la cuenca al oído) con su sombra abajo
    s.shade([(-1.0, -9.0), (10.0, -10.4), (13.0, -12.4), (4.0, -12.8), (-0.6, -11.0)], "hueso_sombra")
    s.line([(-1.0, -8.2), (5.0, -9.2), (11.0, -9.6)], "hueso_claro")
    # oído
    s.line([(-1.0, -5.0), (0.0, -5.0)], "cuenca")
    s.line([(-1.0, -6.0), (0.0, -6.0)], "cuenca")
    # cuenca con ceño, pupila adelante
    s.fill(SOCKET_S, "cuenca")
    s.rim(SOCKET_S, "cuenca_borde", (-1.4, 2.0), only=["cuenca"])
    s.line(BROW_S, "hueso_luz", only=BONE)
    if eyes >= 0.75:
        s.fill(ellipse(11.2, -4.8, 1.6, 1.6), "ojo")
    elif eyes > 0.2:
        s.dot(11.2, -4.8, "ojo")
    s.fill(NOSE_S, "cuenca")
    # dientes de arriba
    up = [(8.6, -10.6), (16.9, -10.4), (16.9, -14.0), (8.6, -14.0)]
    s.fill(up, "hueso_claro")
    s.line([(8.8, -10.6), (16.6, -10.4)], "hueso_oscuro")
    for x in (12.4, 15.2):
        s.line([(x, -11.0), (x, -13.6)], "hueso_oscuro")
    # grietas
    s.line([(-5.0, 14.0), (-3.0, 10.0), (-5.0, 7.0), (-2.6, 4.6)], "grieta")
    s.line([(-3.0, 10.0), (0.0, 9.4)], "grieta")
    return s


CAGE_S = ellipse(0.4, -0.5, 8.2, 10.2, rot=-10)


def ribcage_side(f, pos, rot_deg=0.0):
    """Tórax de perfil: columna atrás (izquierda), costillas que bajan hacia el
    esternón (derecha)."""
    p = f.piece(LINE, (pos[0], pos[1], rot_deg, 1, 1))
    p.fill(CAGE_S, "hueco")
    p.shade([(1.0, 14), (14, 14), (14, -14), (1.0, -14)], "hueco_oscuro")
    ribs = []
    for y0 in (7.2, 3.6, 0.0, -3.6):
        ribs.append(band([(-6.8, y0 + 1.4), (-3.0, y0 + 2.4), (2.0, y0 + 1.0), (6.0, y0 - 2.0), (8.2, y0 - 4.4)], 2.4, 1.7))
    ribs.append(band([(-6.4, -5.6), (-2.4, -5.8), (1.8, -7.6)], 1.9, 1.4))
    stern = capsule((7.0, 8.0), (8.6, -2.8), 1.5, 1.2)
    p.fill(ribs + [stern], "hueso")
    p.rim(ribs, "hueso_sombra", (0, 1.1), only=["hueso"])
    p.rim(ribs, "hueso_claro", (0, -1.0), only=["hueso"], clip=[(-14, 14), (1, 14), (1, -14), (-14, -14)])
    p.shade([(5.0, 14), (14, 14), (14, -14), (5.0, -14)], "hueso_sombra", only=["hueso"])
    q = f.piece(LINE, (pos[0], pos[1], rot_deg, 1, 1))
    verts = [ellipse(-7.4, y, 1.6, 1.2) for y in (9.0, 6.2, 3.4, 0.6, -2.2, -5.0, -7.8)]
    q.fill(verts, "hueso")
    q.rim(verts, "hueso_sombra", (-0.8, 0.8))
    return p


def pelvis_side(f, pos, rot_deg=0.0):
    p = f.piece(LINE, (pos[0], pos[1], rot_deg, 1, 1))
    ilium = ellipse(-0.6, 2.6, 5.8, 4.0, rot=25)
    sac = ellipse(-5.0, 1.0, 2.0, 3.6, rot=-20)
    pub = band([(0.4, -1.4), (3.2, -3.2), (5.8, -4.4)], 2.6)
    isch = band([(-0.4, -1.4), (-2.8, -3.6), (-3.8, -5.4)], 2.8)
    low = band([(-3.8, -5.4), (0.8, -6.2), (5.8, -4.4)], 2.0)
    polys = [ilium, sac, pub, isch, low]
    p.fill(polys, "hueso")
    p.rim(polys, "hueso_claro", (1.0, -1.0))
    p.rim(polys, "hueso_sombra", (-1.6, 1.6))
    p.shade(ellipse(0.4, 3.0, 3.2, 1.6, rot=25), "hueso_sombra")
    p.fill(ellipse(1.0, -4.2, 1.6, 0.9), "hueco")
    return p


def foot_side(f, ankle, rot_deg=0.0, far=False):
    """Pie de perfil, la punta hacia la derecha."""
    hi, base, lo = tones(far)
    b = add(ankle, rot((0, -4.4), rot_deg))
    p = f.piece(LINE, (b[0], b[1], rot_deg, 1, 1))
    sole = [(-3.0, 0.0), (-3.4, 2.0), (-1.2, 4.0), (2.4, 3.6), (5.6, 2.2), (8.6, 1.4), (9.0, 0.0)]
    p.fill(sole, base)
    p.rim(sole, lo, (0, 1.0))
    p.rim(sole, hi, (0.8, -0.8), only=[base])
    for x in (5.2, 7.2):
        p.line([(x, 0.0), (x, 1.4)], lo if not far else "hueso_oscuro")
    q = f.piece(LINE, (b[0], b[1], rot_deg, 1, 1))
    t = circle(0.2, 4.4, 2.2)
    q.fill(t, base)
    q.rim(t, lo, (-1.0, 1.0))
    return p


SIDE = {
    "hip": (-3.0, 28.5), "lean": -14.0,
    "head": (0.0, 0.0, 0.0), "jaw": 0.0,
    "hand_n": (12.0, 34.0), "hand_f": (7.0, 37.0),
    "foot_n": (6.0, 4.4), "foot_f": (-9.0, 4.4),
    "sword": -32.0, "scarf": 0.0, "wind": 1.0,
}


def side_rig(P):
    hip, lean = P["hip"], P["lean"]
    chest = add(hip, rot((0, 20.5), lean))
    neck = add(hip, rot((0, 30.5), lean))
    hd = P["head"]
    head = add(neck, (2.0 + hd[0], 25.0 + hd[1]))
    R = {"view": "e", "skull": (head[0], head[1], hd[2]), "jaw": P["jaw"], "eyes": P.get("eyes", 1.0),
         "ribs": (chest[0], chest[1], lean), "pelvis": (hip[0], hip[1], lean * 0.4),
         "spine": (add(hip, rot((-3.6, 3.0), lean)), add(chest, rot((-7.0, -7.4), lean))),
         "scarf": (neck[0], neck[1], lean * 0.5, P["scarf"], P["wind"]),
         "scale": P.get("scale", 1.0)}
    for tag, foot, dz in (("n", P["foot_n"], 0.0), ("f", P["foot_f"], -1.5)):
        hj = add(hip, (0.6 + dz, -1.6))
        kn = ik(hj, foot, LEG[0], LEG[1], 1)
        R["thigh_" + tag] = (hj, kn)
        R["shin_" + tag] = (kn, foot)
        R["fib_" + tag] = (add(kn, (-1.6, -0.6)), add(foot, (-1.4, 0.8)))
        R["knee_" + tag] = add(kn, (0.9, 0.3))
        R["foot_" + tag] = (foot[0], foot[1], 0.0)
    for tag, hand, dz in (("n", P["hand_n"], 0.0), ("f", P["hand_f"], -2.0)):
        sh = add(chest, rot((0.5 + dz, 7.6), lean))
        el = ik(sh, hand, ARM[0], ARM[1], -1)
        R["hum_" + tag] = (sh, el)
        R["fore_" + tag] = (el, hand)
        R["elbow_" + tag] = el
    R["hand_n"] = (P["hand_n"][0], P["hand_n"][1], P["sword"])
    R["sword"] = (P["hand_n"][0], P["hand_n"][1], P["sword"])
    R["hand_f"] = (P["hand_f"][0], P["hand_f"][1], 0.0)
    R["shield"] = (P["hand_f"][0] + 2.4, P["hand_f"][1], 0.0, 1.0)
    return R


def _leg_side(f, R, tag, far=False):
    bone(f, *R["fib_" + tag], 1.0, knob=1.0, light=False, far=far)
    bone(f, *R["thigh_" + tag], 2.2, ends=(False, True), far=far)
    bone(f, *R["shin_" + tag], 1.9, ends=(False, True), far=far)
    x, y, r = R["foot_" + tag]
    foot_side(f, (x, y), r, far)
    knob(f, R["knee_" + tag], 2.4, far)


def draw_side(f, R):
    # lado lejano: brazo del escudo y pierna, un tono más oscuros
    bone(f, *R["hum_f"], 1.9, ends=(True, False), far=True)
    _forearm(f, *R["fore_f"], far=True)
    knob(f, R["elbow_f"], 2.0, far=True)
    fist(f, R["hand_f"][:2], R["hand_f"][2], 1, far=True)
    _leg_side(f, R, "f", far=True)
    sx, sy, sr, ph, wind = R["scarf"]
    scarf_tails(f, (sx + 1.0, sy), ph, wind, sr)
    pelvis_side(f, R["pelvis"][:2], R["pelvis"][2])
    spine(f, *R["spine"], 3)
    ribcage_side(f, R["ribs"][:2], R["ribs"][2])
    _leg_side(f, R, "n")
    # lado cercano: brazo de la espada
    bone(f, *R["hum_n"], 2.0, ends=(True, False))
    _forearm(f, *R["fore_n"])
    knob(f, R["elbow_n"], 2.2)
    scarf_wrap(f, (sx, sy), sr, 1.0, WRAP_SIDE, knot=(-6.0, 1.0), folds=False)
    skull_side(f, R["skull"][:2], R["skull"][2], R["jaw"], R.get("eyes", 1.0))
    sword(f, R["sword"][:2], R["sword"][2])
    hx, hy, hr = R["hand_n"]
    fist(f, (hx, hy), hr, 1)


# --- Vista de espaldas -----------------------------------------------------------------
# Es la pose de frente espejada (la espada queda a la derecha de la pantalla)
# con los dibujos de atrás: nuca, columna y omóplatos, talones, dorso del escudo.

def skull_back(f, pos, rot_deg=0.0):
    s = f.piece(LINE, (pos[0], pos[1], rot_deg, 1, 1))
    nape = ellipse(0, -8.0, 12.4, 10.6)
    s.fill([CRANIUM, nape], "hueso")
    s.rim([CRANIUM], "hueso_claro", (4.0, -4.0))
    s.shade(ellipse(-7.0, 8.4, 3.4, 2.0, rot=35), "hueso_luz")
    s.rim([CRANIUM, nape], "hueso_sombra", (-3.6, 3.2))
    s.rim([CRANIUM, nape], "hueso_oscuro", (-1.2, 1.2), only=["hueso_sombra"])
    # la nuca: un reborde debajo del cráneo y las puntas de la mandíbula
    s.line([(-10.0, -6.4), (-4.0, -9.0), (4.0, -9.0), (10.0, -6.4)], "hueso_sombra")
    s.line([(-9.0, -7.6), (-3.6, -10.0)], "hueso_claro")
    s.shade(ellipse(-11.4, -13.0, 2.0, 3.6), "hueso_sombra")
    s.shade(ellipse(11.4, -13.0, 2.0, 3.6), "hueso_oscuro")
    s.line([(-3.0, 13.6), (-1.0, 9.4), (-3.4, 6.4), (-0.6, 3.0)], "grieta")
    s.line([(-1.0, 9.4), (2.4, 8.6)], "grieta")
    s.line([(8.0, 9.0), (10.0, 5.6), (9.0, 3.0)], "grieta")
    return s


def ribcage_back(f, pos, rot_deg=0.0):
    p = f.piece(LINE, (pos[0], pos[1], rot_deg, 1, 1))
    p.fill(CAGE, "hueco")
    p.shade([(4.0, 12), (14, 12), (14, -12), (4.0, -12)], "hueco_oscuro")
    ribs = []
    for (y0, w, drop) in RIBS:
        for sd in (-1, 1):
            pts = [(sd * 1.6, y0 + 0.6), (sd * w * 0.42, y0 + 1.2), (sd * w * 0.74, y0 + 0.4),
                   (sd * w * 0.93, y0 - drop * 0.4), (sd * w, y0 - drop)]
            ribs.append(band(pts, 2.4, 1.6))
    ribs += [band([(sd * 1.6, -6.4), (sd * 5.6, -6.6), (sd * 8.2, -8.4)], 1.8, 1.4) for sd in (-1, 1)]
    p.fill(ribs, "hueso")
    p.rim(ribs, "hueso_sombra", (0, 1.1), only=["hueso"])
    p.rim(ribs, "hueso_claro", (0, -1.0), only=["hueso"], clip=[(-14, 14), (2, 14), (2, -14), (-14, -14)])
    p.shade([(5.5, 14), (14, 14), (14, -14), (5.5, -14)], "hueso_sombra", only=["hueso"])
    # columna: vértebras con su apófisis
    q = f.piece(LINE, (pos[0], pos[1], rot_deg, 1, 1))
    verts = [ellipse(0, y, 1.9, 1.2) for y in (9.6, 6.6, 3.6, 0.6, -2.4, -5.4, -8.4)]
    q.fill(verts, "hueso")
    q.rim(verts, "hueso_sombra", (-0.8, 0.8))
    q.rim(verts, "hueso_claro", (0.6, -0.6), only=["hueso"])
    # omóplatos
    for sd in (-1, 1):
        o = f.piece(LINE, (pos[0], pos[1], rot_deg, 1, 1))
        sc = [(sd * 3.4, 9.4), (sd * 10.8, 9.6), (sd * 9.8, 4.4), (sd * 6.4, -0.8), (sd * 3.8, 4.2)]
        o.fill(sc, "hueso")
        o.rim(sc, "hueso_sombra", (-1.2, 1.2))
        o.rim(sc, "hueso_claro", (1.0, -1.0), only=["hueso"])
        o.line([(sd * 4.2, 7.0), (sd * 10.2, 8.6)], "hueso_oscuro" if sd > 0 else "hueso_sombra")
    return p


def pelvis_back(f, pos, rot_deg=0.0):
    p = f.piece(LINE, (pos[0], pos[1], rot_deg, 1, 1))
    wing_l = ellipse(-6.6, 1.6, 6.2, 3.8, rot=-32)
    wing_r = ellipse(6.6, 1.6, 6.2, 3.8, rot=32)
    sac = [(-3.4, 4.6), (3.4, 4.6), (1.4, -4.4), (-1.4, -4.4)]
    low = band([(-7.6, -1.4), (-4.6, -3.8), (-1.4, -4.6), (1.4, -4.6), (4.6, -3.8), (7.6, -1.4)], 2.6)
    polys = [wing_l, wing_r, sac, low]
    p.fill(polys, "hueso")
    p.rim(polys, "hueso_claro", (1.2, -1.2))
    p.rim(polys, "hueso_sombra", (-1.8, 1.8))
    p.rim(polys, "hueso_oscuro", (-0.8, 0.8), only=["hueso_sombra"], clip=RIGHT_HALF)
    p.shade(sac, "hueso_sombra", only=["hueso", "hueso_claro"])
    for y in (2.4, 0.0, -2.2):
        p.dot(-1.2, y, "hueso_oscuro")
        p.dot(1.0, y, "hueso_oscuro")
    return p


def foot_back(f, ankle, side, rot_deg=0.0):
    """Talón visto de atrás; los dedos asoman hacia afuera."""
    b = add(ankle, rot((0, -4.4), rot_deg))
    p = f.piece(LINE, (b[0], b[1], rot_deg, side, 1))
    toes = [(1.6, 0.0), (6.4, 0.0), (6.6, 1.4), (2.6, 2.6)]
    p.fill(toes, "hueso_sombra")
    q = f.piece(LINE, (b[0], b[1], rot_deg, side, 1))
    heel = ellipse(0.0, 1.9, 3.0, 2.0)
    talus = circle(0.0, 4.4, 2.2)
    q.fill([heel, talus], "hueso")
    q.rim([heel, talus], "hueso_sombra", (-1.0 * side, 1.0))
    return p


def shield_back(f, pos, rot_deg=0.0, sx=1.0, sy=1.0):
    """Dorso del escudo: tablas en sombra, el aro y la correa donde va la mano."""
    t = (pos[0], pos[1], rot_deg, sx, sy)
    p = f.piece("acero_linea", t)
    outer = ellipse(0, 0, 9.6, 15.0)
    wood = ellipse(-0.5, 0, 7.6, 13.0)
    p.fill(outer, "acero_sombra")
    p.rim(outer, "acero", (1.4 * (1 if sx > 0 else -1), -1.4))
    p.fill(wood, "madera_sombra")
    p.rim(wood, "madera", (1.6 * (1 if sx > 0 else -1), -1.6), only=["madera_sombra"])
    for x in (-4.4, -0.4, 3.6):
        p.line([(x, 12.8), (x, -12.8)], "madera_oscura", only=["madera", "madera_sombra"])
    st = f.piece("madera_linea", t)
    strap = band([(-7.0, 1.6), (0.0, 0.6), (7.0, 1.0)], 2.2)
    st.fill(strap, "cuero")
    st.line([(-6.0, 2.0), (6.0, 1.4)], "cuero_luz")
    return p


def mirror_rig(R):
    """Espeja un rig de frente (x -> -x) para la vista de espaldas."""
    out = {}
    for key, v in R.items():
        if isinstance(v, tuple) and len(v) == 2 and isinstance(v[0], tuple):
            out[key] = ((-v[0][0], v[0][1]), (-v[1][0], v[1][1]))
        elif isinstance(v, tuple) and key not in ("smear",):
            if len(v) == 2:
                out[key] = (-v[0], v[1])
            else:
                out[key] = (-v[0], v[1], -v[2]) + tuple(v[3:])
        else:
            out[key] = v
    out["view"] = "n"
    return out


def draw_back(f, R):
    # lo que el esqueleto tiene adelante queda detrás de él: espada y escudo
    sword(f, R["sword"][:2], R["sword"][2])
    x, y, r, sc = R["shield"]
    shield_back(f, (x, y), r, -sc, sc)
    for tag, side in (("r", 1), ("l", -1)):
        bone(f, *R["fib_" + tag], 1.0, knob=1.0, light=False)
        bone(f, *R["thigh_" + tag], 2.2, ends=(False, True))
        bone(f, *R["shin_" + tag], 1.9, ends=(False, True))
        fx, fy, fr = R["foot_" + tag]
        foot_back(f, (fx, fy), side, fr)
        knob(f, R["knee_" + tag], 1.9)
    pelvis_back(f, R["pelvis"][:2], R["pelvis"][2])
    spine(f, *R["spine"], 3)
    ribcage_back(f, R["ribs"][:2], R["ribs"][2])
    for tag, side in (("l", -1), ("r", 1)):
        bone(f, *R["hum_" + tag], 2.0, ends=(True, False))
        _forearm(f, *R["fore_" + tag])
        knob(f, R["elbow_" + tag], 2.2)
        hx, hy, hr = R["hand_" + tag]
        fist(f, (hx, hy), hr, -side)
    skull_back(f, R["skull"][:2], R["skull"][2])
    sx, sy, sr, ph, wind = R["scarf"]
    scarf_wrap(f, (sx, sy), sr, -1.0)
    scarf_tails(f, (sx, sy), ph, wind, sr, -1.0)


# --- Animación -------------------------------------------------------------------------

def lerp(a, b, t):
    if a is None or b is None or isinstance(a, bool) or isinstance(b, bool):
        return b if t >= 0.5 else a
    if isinstance(a, (tuple, list)):
        return tuple(lerp(x, y, t) for x, y in zip(a, b))
    return a + (b - a) * t


def lerp_pose(A, B, t):
    out = dict(A)
    for key, v in B.items():
        out[key] = lerp(A.get(key, v), v, t) if key in A else v
    return out


def cyc(u, ph=0.0):
    """0 -> 1 -> 0 en un ciclo (u de 0 a 1)."""
    return (1 - math.cos(2 * math.pi * (u - ph))) / 2


def pose(base, **kw):
    out = dict(base)
    out.update(kw)
    return out


GUARD = pose(FRONT, hip=(0.0, 27.6), foot_r=(-18.0, 4.4), foot_l=(18.0, 4.4), hand_r=(-18.0, 44.0), sword=16.0,
             hand_l=(18.0, 40.0), shield=(4.5, 0.0, 0.0, 1.05), jaw=0.3)
HURT = pose(GUARD, lean=-8.0, head=(1.0, 1.0, -10.0), jaw=2.6, hand_r=(-24.0, 41.0), hand_l=(22.0, 42.0), sword=62.0,
            scale=0.96, hip=(0.0, 28.0))


def idle(u):
    b = cyc(u)
    return pose(FRONT, hip=(0.0, 29.0 - 1.0 * b), head=(0.0, 1.0 * (b - cyc(u, 0.15)), 0.0), jaw=0.7 * cyc(u, 0.1),
                hand_r=(-21.0, 35.0 - 1.0 * cyc(u, 0.08)), sword=38.0 + 3.0 * math.sin(2 * math.pi * u),
                hand_l=(21.0, 37.0 - 1.0 * cyc(u, 0.08)), scarf=u)


def combat(u):
    b = cyc(u)
    return pose(GUARD, hip=(0.0, 27.6 - 1.0 * b), head=(0.0, 1.0 * (b - cyc(u, 0.15)), 0.0), jaw=0.3 + 0.6 * cyc(u, 0.1),
                hand_r=(-18.0, 44.0 - 1.0 * cyc(u, 0.1)), sword=16.0 + 4.0 * math.sin(2 * math.pi * u),
                hand_l=(18.0, 40.0 - 1.0 * cyc(u, 0.1)), scarf=u, wind=1.1)


def idle_side(u):
    b = cyc(u)
    return pose(SIDE, hip=(-3.0, 28.5 - 1.0 * b), head=(0.0, 1.0 * (b - cyc(u, 0.15)), 0.0), jaw=0.7 * cyc(u, 0.1),
                hand_n=(12.0, 34.0 - 1.0 * cyc(u, 0.08)), sword=-32.0 + 3.0 * math.sin(2 * math.pi * u),
                hand_f=(7.0, 37.0 - 1.0 * cyc(u, 0.08)), scarf=u)


def walk_side(u):
    """De perfil: cada pie avanza levantado y vuelve apoyado; los brazos van
    al revés que las piernas."""
    a = 2 * math.pi * u
    xn, ln_ = -1.5 - 8.0 * math.cos(a), 4.5 * max(0.0, math.sin(a))
    xf, lf = -1.5 + 8.0 * math.cos(a), 4.5 * max(0.0, -math.sin(a))
    return pose(SIDE, hip=(-3.0, 27.4 + 1.6 * abs(math.sin(a))), lean=-15.0 - 2.0 * abs(math.sin(a)),
                foot_n=(xn, 4.4 + ln_), foot_f=(xf, 4.4 + lf),
                head=(0.0, -0.8 * abs(math.sin(a - 0.4)), 0.0),
                hand_n=(12.0 + 3.0 * math.cos(a), 34.0 + 1.0 * math.sin(a)), sword=-32.0 + 6.0 * math.cos(a),
                hand_f=(7.0 - 3.0 * math.cos(a), 37.0), jaw=0.5 * abs(math.sin(a)), scarf=2 * u, wind=1.3)


def walk(u):
    """De frente, hacia la cámara: pasos alternados con balanceo."""
    sw = math.sin(2 * math.pi * u)
    lift_r, lift_l = max(0.0, sw) * 4.0, max(0.0, -sw) * 4.0
    return pose(FRONT, hip=(1.4 * sw, 28.0 + 1.2 * abs(sw)), lean=-2.5 * sw,
                foot_r=(-16.0 + 0.6 * lift_r, 4.4 + lift_r), foot_l=(16.0 - 0.6 * lift_l, 4.4 + lift_l),
                head=(0.0, -0.6 * abs(math.sin(2 * math.pi * (u - 0.06))), -2.0 * sw),
                hand_r=(-21.0, 35.0 - 2.2 * sw), sword=38.0 + 5.0 * sw, hand_l=(21.0, 37.0 + 2.2 * sw),
                jaw=0.5 * abs(sw), scarf=2 * u, wind=1.25)


ATTACK = [
    pose(GUARD, hip=(0.0, 26.6), lean=6.0, hand_r=(-22.0, 56.0), sword=70.0, jaw=0.5),
    pose(GUARD, hip=(0.0, 26.0), lean=9.0, hand_r=(-22.0, 66.0), sword=42.0, head=(0.0, 0.0, 6.0), jaw=1.0),
    pose(GUARD, hip=(0.0, 26.0), lean=10.0, hand_r=(-19.0, 70.0), sword=26.0, head=(0.0, 0.0, 8.0), jaw=1.4, scale=1.03),
    pose(GUARD, hip=(0.0, 27.0), lean=-6.0, hand_r=(2.0, 54.0), sword=-75.0, jaw=2.6, scale=1.10, sword_front=True),
    pose(GUARD, hip=(0.0, 26.0), lean=-10.0, hand_r=(12.0, 33.0), sword=-140.0, jaw=3.0, scale=1.15, sword_front=True),
    pose(GUARD, hip=(0.0, 26.4), lean=-8.0, hand_r=(10.0, 31.0), sword=-150.0, jaw=2.0, scale=1.12, sword_front=True),
    pose(GUARD, hip=(0.0, 27.0), lean=-3.0, hand_r=(-8.0, 38.0), sword=-20.0, jaw=1.0, scale=1.05),
    GUARD,
]
ATTACK_2 = [
    pose(GUARD, hip=(0.0, 26.8), lean=-6.0, hand_r=(4.0, 50.0), sword=-80.0, jaw=0.5, sword_front=True),
    pose(GUARD, hip=(0.0, 26.4), lean=-9.0, hand_r=(10.0, 52.0), sword=-95.0, head=(0.0, 0.0, -6.0), jaw=1.0, sword_front=True),
    pose(GUARD, hip=(0.0, 26.2), lean=-10.0, hand_r=(11.0, 53.0), sword=-100.0, head=(0.0, 0.0, -7.0), jaw=1.3, scale=1.03, sword_front=True),
    pose(GUARD, hip=(0.0, 27.0), lean=4.0, hand_r=(-10.0, 50.0), sword=40.0, jaw=2.6, scale=1.10, sword_front=True),
    pose(GUARD, hip=(0.0, 26.0), lean=9.0, hand_r=(-24.0, 46.0), sword=92.0, jaw=3.0, scale=1.15, sword_front=True),
    pose(GUARD, hip=(0.0, 26.4), lean=7.0, hand_r=(-25.0, 43.0), sword=104.0, jaw=2.0, scale=1.12),
    pose(GUARD, hip=(0.0, 27.0), lean=3.0, hand_r=(-21.0, 42.0), sword=50.0, jaw=1.0, scale=1.05),
    GUARD,
]
# Cuadros con estela: (índice, desde qué pose barre la hoja).
SWEEPS = {"attack": {3: 2, 4: 3}, "attack_2": {3: 2, 4: 3}}
HIT = [HURT, pose(HURT, lean=-6.0, head=(1.0, 0.5, -8.0), jaw=2.0, scale=0.97),
       pose(GUARD, lean=-2.0, head=(0.0, 0.0, -3.0), jaw=1.0, scale=0.99), GUARD]
HIT_2 = [pose(GUARD, hip=(0.0, 26.4), head=(0.0, 6.0, 10.0), jaw=3.0, scale=0.98, hand_r=(-22.0, 40.0), sword=50.0),
         pose(GUARD, hip=(0.0, 26.8), head=(1.0, 10.0, 18.0), jaw=2.6, hand_r=(-22.0, 41.0), sword=46.0),
         pose(GUARD, hip=(0.0, 27.0), head=(0.0, 5.0, 8.0), jaw=1.4),
         pose(GUARD, hip=(0.0, 27.0), head=(0.0, -1.2, 0.0))]

# Al morir, cada parte cae con su retraso (0..1 del derrumbe); la calavera, última.
FALL_DELAY = {"sword": 0.0, "foot": 0.0, "shin": 0.0, "fib": 0.0, "knee": 0.02, "thigh": 0.04, "pelvis": 0.06,
              "spine": 0.08, "hum": 0.1, "fore": 0.1, "elbow": 0.1, "hand": 0.12, "ribs": 0.12, "shield": 0.14,
              "scarf": 0.2, "skull": 0.28, "jaw": 0.28}


def _delay(key):
    return FALL_DELAY.get(key.split("_")[0], 0.1)


def _blend_val(a, b, t):
    if isinstance(a, tuple) and len(a) == 2 and isinstance(a[0], tuple):
        # hueso (a, b): centro, ángulo y largo
        ca = ((a[0][0] + a[1][0]) / 2, (a[0][1] + a[1][1]) / 2)
        cb = ((b[0][0] + b[1][0]) / 2, (b[0][1] + b[1][1]) / 2)
        aa = math.atan2(a[1][1] - a[0][1], a[1][0] - a[0][0])
        ab = math.atan2(b[1][1] - b[0][1], b[1][0] - b[0][0])
        da = (ab - aa + math.pi) % (2 * math.pi) - math.pi
        la, lb = math.dist(*a), math.dist(*b)
        c, ang, ln = lerp(ca, cb, t), aa + da * t, lerp(la, lb, t)
        h = (math.cos(ang) * ln / 2, math.sin(ang) * ln / 2)
        return ((c[0] - h[0], c[1] - h[1]), (c[0] + h[0], c[1] + h[1]))
    return lerp(a, b, t)


def blend_rig(R0, R1, t, fall=True):
    """Pasa de un rig a otro parte por parte (fall: cae acelerando; si no,
    sube frenando, para levantarse)."""
    out = {}
    for key, b in R1.items():
        a = R0.get(key, b)
        if key in ("scale", "smear", "sword_front", "eyes"):
            out[key] = lerp(a, b, t)
            continue
        d = _delay(key) if fall else 0.28 - _delay(key)
        p = max(0.0, min(1.0, (t - d) / (1.0 - 0.28)))
        p = p ** 1.5 if fall else 1 - (1 - p) ** 2
        out[key] = _blend_val(a, b, p)
    return out


def death(i, n=10):
    R_hurt = front_rig(pose(HURT, lean=-10.0, hip=(0.0, 26.0), head=(1.0, 1.0, -14.0), jaw=3.0))
    if i == 0:
        return front_rig(HURT)
    if i == 1:
        return R_hurt
    t = 0.12 + 0.88 * (i - 2) / (n - 3)
    R = blend_rig(R_hurt, pile_rig(), t)
    x, y, r = R["skull"]
    if t < 1.0:
        R["skull"] = (x, y, r + 30.0 * math.sin(math.pi * t))
    else:
        R["skull"] = (x, y, r)
    R["eyes"] = 1.0 if t < 0.35 else (0.5 if t < 0.6 else 0.0)
    return R


def spawn(i, n=12):
    pile = pile_rig()
    if i <= 1:
        return dict(pile, eyes=0.0 if i == 0 else 0.5)
    if i == 2:
        R = dict(pile, eyes=1.0)
        x, y, r = R["skull"]
        R["skull"] = (x - 1.0, y + 1.0, r + 6.0)
        return R
    rise = front_rig(pose(GUARD, lean=-8.0, hip=(0.0, 25.0), hand_r=(-22.0, 50.0), sword=60.0, jaw=1.6,
                          head=(0.0, 1.0, -6.0)))
    if i < n - 2:
        t = (i - 2) / (n - 4)
        R = blend_rig(pile, rise, t, fall=False)
        R["eyes"] = 1.0
        return R
    return front_rig(GUARD) if i == n - 1 else rise


# nombre -> (cuadros, se repite, duración en s, {dirección: función i -> rig})
def _poses(seq):
    return {"s": lambda i: front_rig(seq[i])}


def _turned(front, side):
    """De frente, de perfil (e) y de espaldas (n, la de frente espejada); el
    juego espeja e y usa la más cercana para las demás."""
    return {"s": lambda i: front_rig(front(i)), "e": lambda i: side_rig(side(i)),
            "n": lambda i: mirror_rig(front_rig(front(i)))}


ANIMS = {
    "idle": (6, True, 1.4, _turned(lambda i: idle(i / 6), lambda i: idle_side(i / 6))),
    "walk": (8, True, 0.9, _turned(lambda i: walk(i / 8), lambda i: walk_side(i / 8))),
    "combat": (6, True, 1.1, {"s": lambda i: front_rig(combat(i / 6))}),
    "attack": (8, False, 0.9, _poses(ATTACK)),
    "attack_2": (8, False, 0.9, _poses(ATTACK_2)),
    "hit": (4, False, 0.45, _poses(HIT)),
    "hit_2": (4, False, 0.45, _poses(HIT_2)),
    "death": (10, False, 1.3, {"s": death}),
    "spawn": (12, False, 1.5, {"s": spawn}),
    "dormant": (1, True, 1.0, {"s": lambda i: pile_rig()}),
}


def anim_rig(name, i, d="s"):
    count, loop, length, fns = ANIMS[name]
    R = fns[d](i)
    sw = SWEEPS.get(name, {})
    if d == "s" and i in sw:
        seq = ATTACK if name == "attack" else ATTACK_2
        R["smear"] = sweep(seq[sw[i]], seq[i])
    return R


# --- Hoja -----------------------------------------------------------------------------

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "sprites" / "enemies"
SPECIES = "esqueleto_esbirro"
CANVAS = (150, 140)
ORIGIN = (75, 134)
COLUMNS = 16
PPM = 64


def build(preview=None):
    frames, meta_anims = [], {}
    for name, (count, loop, length, fns) in ANIMS.items():
        entry = {"loop": loop, "fps": round(count / length, 2), "dirs": {}}
        for d in fns:
            for i in range(count):
                R = anim_rig(name, i, d)
                f = Frame(CANVAS[0], CANVAS[1], ORIGIN, PAL, R["scale"])
                draw_any(f, R)
                rgba, glow = f.render(GLOW)
                if rgba[0, :, 3].any() or rgba[:, 0, 3].any() or rgba[:, -1, 3].any():
                    print(f"  aviso: {name}/{d}/{i} toca el borde del cuadro")
                entry["dirs"].setdefault(d, []).append(len(frames))
                frames.append((rgba, glow))
        meta_anims[name] = entry
    alpha = np.zeros((CANVAS[1], CANVAS[0]), dtype=bool)
    for rgba, _ in frames:
        alpha |= rgba[..., 3] > 0
    ys, xs = np.nonzero(alpha)
    x0, x1 = max(0, xs.min() - 1), min(CANVAS[0], xs.max() + 2)
    y0, y1 = max(0, ys.min() - 1), min(CANVAS[1], ys.max() + 2)
    frames = [(rgba[y0:y1, x0:x1], glow[y0:y1, x0:x1]) for rgba, glow in frames]
    fw, fh = x1 - x0, y1 - y0
    pivot = [ORIGIN[0] - x0, ORIGIN[1] - y0]
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
            "columns": COLUMNS, "pivot": [int(pivot[0]), int(pivot[1])], "pixels_per_meter": PPM, "anims": meta_anims}
    (OUT_DIR / f"{SPECIES}.json").write_text(json.dumps(meta, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{SPECIES}: {len(frames)} cuadros de {fw}x{fh}, {len(meta_anims)} animaciones")
    if preview:
        zoom = 2
        rows = [ids for e in meta_anims.values() for ids in e["dirs"].values()]
        cells = max(len(r) for r in rows)
        out = Image.new("RGBA", (cells * fw * zoom, len(rows) * fh * zoom), (60, 52, 44, 255))
        for r, ids in enumerate(rows):
            for c, k in enumerate(ids):
                cell = Image.fromarray(frames[k][0], "RGBA").resize((fw * zoom, fh * zoom), Image.NEAREST)
                out.alpha_composite(cell, (c * fw * zoom, r * fh * zoom))
        out.save(preview)
        print(f"vista previa: {preview}")


if __name__ == "__main__":
    args = sys.argv[1:]
    prev = next((a.split("=", 1)[1] for a in args if a.startswith("--preview=")), None)
    build(prev)
