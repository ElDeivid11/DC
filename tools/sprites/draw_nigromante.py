"""Nigromante (jefe; diseño de David) en pixel art grueso.

Corona de cuernos de hueso, túnica morada de cuello alto con ribete de oro,
hombreras de calavera, collar de dientes, faja, ruedo negro hecho jirones y
botas; un báculo retorcido con cráneo de carnero y una llama; detrás, un
espectro (brilla tenue con el color de ojos, ver SPIRIT en pixel_kit) y, a
los pies, dos esqueletitos (uno con cuchillo). Solo de frente: el jefe
siempre mira al equipo.

El cuerpo no es el esqueleto común: se arma con sellos y líneas gruesas, y
el ruedo de la túnica se dibuja por código (alto variable: así se derrumba
en un montón de tela y se levanta de él).

Escribe assets/sprites/enemies/nigromante.png, _glow.png, _normal.png y .json,
y el círculo de invocación de su sala (nigromante_circulo.png).
Uso: python3 -I tools/sprites/draw_nigromante.py [--preview=hoja.png] [--gif=anim.gif]
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
from pixel_kit import (OUT_DIR, Canvas, Piece, art, crescent, flip_x, lit_gif, move, pose, recolor,  # noqa: E402
                       reel, smear_piece, write_sheet)

SPECIES = "nigromante"
PPM = 24
SELF_LIGHT = 0.3
CANVAS = Canvas(120, 92, 60, 86)

# --- Sellos ----------------------------------------------------------------------------------

SKULL = art("""
....WWWWWWWW....
..WWWWWWWWWWWW..
.WWWWWWWWWWWWWB.
WWWWWWWWWWWWWWBB
WWKKKKWWWWKKKKBB
WKKKKKKWWKKKKKKB
WKKEEKKWWKKEEKKB
WKKEEKKWWKKEEKKD
BWKKKKWKKWKKKKBD
BWWWWWWKKWWWWWBD
.BWWWWWWWWWWWBD.
.BWKWKWKWKWKWBD.
""")
JAW = art("""
WKWKWKWKWKWK
BWWWWWWWWWWD
.BBBBBBBBBD.
""")
CROWN_BAND = art("""
CCcCCCCWWCCCCcCC
cCCCcCWKKWcCCCcC
ccccccccccccccc.
""")
# Cuernos de la corona: (columna en la banda, alto, se abre hacia...)
SPIKES = [(0, 5, -1), (3, 7, -1), (7, 10, 0), (11, 7, 1), (14, 5, 1)]
COLLAR = art("""
G............................G
GG..........................GG
GqG........................GqG
GqqG......................GqqG
GqqqG....................GqqqG
.GqqqG..................GqqqG.
.GPqqqG................GqqqPG.
.GPqqqqG..............GqqqqPG.
..GPqqqqG............GqqqqPG..
..GPPqqqqG..........GqqqqPPG..
...GPPqqqqG........GqqqqPPG...
...GPPPqqqqG......GqqqqPPPG...
....GPPPqqqqGGGGGGqqqqPPPG....
....GPPPPPqqqqqqqqqqPPPPPG....
""")
TORSO = art("""
...PPPPPPPPPPPPPP...
..PPPPPPkkkkkPPPPQ..
.PPPPPPPkkkkkPPPPQQ.
PPPPPPPPPkkkPPPPPQQQ
PPPPPPPPPkkkPPPPPQQQ
PPPPPPPPPPkPPPPPPQQQ
QPPPPPPPPPkPPPPPPQQq
QPPPPPPPPPPPPPPPPQQq
QPPPPPPPPPPPPPPPPQqq
QQPPPPPPPPPPPPPPQQqq
QQPPPPPPPPPPPPPPQqqq
""")
NECKLACE = art("""
nn............nn
.nnn........nnn.
.W.nnnnnnnnnn.W.
...W.WnWWnW.W...
.....W.WW.W.....
.......WW.......
""")
PAULDRON = art("""
..WWWWW..
.WWWWWWWB
WWWWWWWWB
WKKWWWKKB
WKKWKWKKD
.BWWWWWD.
..BWBWB..
""")
SASH = art("""
NNNNNNNNNNNNNNNNNNNNNN
nNNNNNNNNNNNNNNNNNNNNn
nnnnnnnnnnnnnnnnnnnnnn
""")
SASH_KNOT = art("""
NNN
NnN
NN.
Nn.
N..
n..
""")
BOOT = art("""
.qQQQ.
qQQQQQ
GGGqqq
""")
CLAW = art("""
WWWW.
WWWWW
WBWBW
W.W.B
""")
GRIP = art("""
WWW
BWB
""")
POINT = art("""
WWW.
WBWW
W...
""")
CUFF = art("""
GGGG
gggg
""")
RAM = art("""
..cCCC......CCCc..
.cCcccC....CcccCc.
cCc...CWWWWC...cCc
Cc...WWWWWWWW...cC
Cc..cWKKWWKKWc..cC
cC..CWKKWWKKWC..Cc
.cC..WWWKKWWW..Cc.
..cc..BWWWWB..cc..
.......BWWB.......
""")
FLAMES = [
    art("""
...E...
..EEE..
..EEE..
...E...
"""),
    art("""
....E....
...EE....
...EEE...
..EEEEE..
..EEFEE..
...EEE...
"""),
    art("""
.....E....
....EE....
....EEE...
...EEEE.E.
..EEEEEEE.
..EEEFFEE.
..EEFFFEE.
...EEEEE..
"""),
    art("""
......E.....
.....EE.....
..E..EEE....
..EE.EEEE...
...EEEEEEE..
..EEEEEEEEE.
..EEEFFFEEE.
..EEFFFFFEE.
...EEFFFEE..
....EEEEE...
"""),
]

# El espectro: calavera, mandíbula, tórax; los brazos son líneas.
G_SKULL = art("""
....FFFFFF....
..FFFFFFFFFF..
.FFFFFFFFFFFFf
FFFFFFFFFFFFFf
FKKKKFFFFKKKKf
FKKEKKFFKKEKKf
FKKKKFFFFKKKKf
fFFFFFFKKFFFFf
.fFFFFFFFFFFf.
..FKFKFKFKFf..
""")
G_JAW = art("""
FKFKFKFKF
.fffffff.
""")
G_RIBS = art("""
FFFFFfFFFFF
FKKKFfFKKKF
.FFFFfFFFF.
.KKKFfFKKK.
..FFFfFFF..
..KKFfFKK..
...FFfFF...
.....f.....
....FfF....
.....f.....
""")

MINI_SKULL = art("""
..WWWWW..
.WWWWWWWB
WWWWWWWWB
WKKWWWKKB
WKEKWKEKB
.BKKWKKBD
..BWWWBD.
""")
MINI_JAW = art("""
WKWKW
.BBB.
""")
MINI_RIBS = art("""
WWWWW
KWKWK
.WWW.
""")
KNIFE = {"u": (art("""
S.
SS
SS
Ss
gg
o.
"""), (0, 5)), "f": (art("""
...SS
..SSs
.SSs.
gg...
o....
"""), (0, 4)), "d": (art("""
o.
gg
SS
SS
Ss
S.
"""), (0, 0))}
DIRT = art("""
..nnnn..
.nNNNNn.
nNNnNNNn
""")


# --- Dibujo -------------------------------------------------------------------------------

def thick(p, a, b, w, ch, edge=None):
    """Línea de w píxeles de ancho (de costado si va vertical, hacia abajo si
    va horizontal); edge = color de la última franja (sombra)."""
    (x0, y0), (x1, y1) = a, b
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    vertical = abs(y1 - y0) >= abs(x1 - x0)
    for t in range(n + 1):
        x = round(x0 + (x1 - x0) * t / n)
        y = round(y0 + (y1 - y0) * t / n)
        for k in range(w):
            c = edge if edge and k == w - 1 else ch
            p.px[(x + k, y) if vertical else (x, y + k)] = c
    return p


def dither_piece(p, phase=0, keep=None):
    """Deja un píxel sí y uno no (los de keep, siempre)."""
    p.px = {(x, y): c for (x, y), c in p.px.items() if (x + y + phase) % 2 == 0 or (keep and c in keep)}
    return p


def ring(c, r, w=2):
    """Píxeles de un anillo de radio r (relativo al piso)."""
    out = []
    for y in range(-r - 1, r + 2):
        for x in range(-r - 1, r + 2):
            if r - w < math.hypot(x, y) <= r:
                out.append((c[0] + x, c[1] + y))
    return out


class Necro:
    def __init__(self, canvas=CANVAS):
        self.cv = canvas

    def at(self, p):
        return self.cv.at(p)

    def frame(self, P):
        return self.cv.to_rgba(*self.cv.render(self.build(P)))

    def build(self, P):
        out = []
        for fx in P.get("fx_back") or []:
            self.effect(fx, out)
        if P.get("ghost"):
            self.ghost(P["ghost"], out)
        if P.get("heap") is not None:
            self.heap(P, out)
        else:
            self.body(P, out)
        for key in ("mini_l", "mini_r"):
            if P.get(key):
                self.mini(P[key], out, flip=key == "mini_r")
        for fx in P.get("fx") or []:
            self.effect(fx, out)
        return out

    # -- el cuerpo --

    def body(self, P, out):
        bx, by = P.get("body", (0, 0))
        waist = -18 + by
        top = waist - 11
        # botas (debajo del ruedo)
        out.append(Piece().stamp(BOOT, *self.at((-7, -3))))
        out.append(Piece().stamp(flip_x(BOOT), *self.at((1, -3))))
        self.skirt(out, bx, waist, P.get("hem", 0))
        if P.get("staff") and P.get("hand_l") != "grip":
            self.staff(P, out)
        out.append(Piece(shape="cyl").stamp(TORSO, *self.at((bx - 10, top))))
        # faja con el nudo y las puntas colgando
        out.append(Piece(shape="cyl").stamp(SASH, *self.at((bx - 11, waist - 1))))
        out.append(Piece().stamp(SASH_KNOT, *self.at((bx + 4, waist + 1))))
        hx, hy = P.get("head", (0, 0))
        out.append(Piece().stamp(COLLAR, *self.at((bx - 15, top - 11 + hy // 2))))
        out.append(Piece(shape="cyl").stamp(NECKLACE, *self.at((bx - 8, top + 1))))
        self.arm(P, out, "arm_r", (bx - 10, top + 2), P.get("hand_r", "claw"))
        self.arm(P, out, "arm_l", (bx + 9, top + 2), P.get("hand_l", "grip"))
        out.append(Piece(shape="dome").stamp(PAULDRON, *self.at((bx - 15, top - 2))))
        out.append(Piece(shape="dome").stamp(flip_x(PAULDRON), *self.at((bx + 6, top - 2))))
        if P.get("staff") and P.get("hand_l") == "grip":
            self.staff(P, out)
            gx, gy = move((bx + 9, top + 2), *P["arm_l"][-1])
            out.append(Piece().stamp(GRIP, *self.at((gx - 1, gy - 1))))
        self.head(P, out, (bx + hx, top + hy))

    def grip_point(self, P):
        """Dónde agarra el báculo la mano izquierda (relativo al piso)."""
        bx, by = P.get("body", (0, 0))
        return move((bx + 9, -27 + by), *P["arm_l"][-1])

    def skirt(self, out, bx, waist, hem):
        """Túnica de la cintura al piso: morada arriba, negra y en jirones
        abajo, con el paño del frente (ribete de oro) encima."""
        p = Piece(shape="cyl")
        h = -waist - 1
        teeth = [2, 0, 1, 3, 1, 0, 2, 1, 3, 0, 1, 2, 0, 3, 1, 2, 0, 1, 3, 1, 0, 2, 1, 0, 2, 3, 1, 0, 2, 1]
        for row in range(h + 1):
            y = waist + row
            t = row / max(h, 1)
            half = round(10 + 4 * t)
            x0 = round(bx * (1 - t)) - half
            x1 = round(bx * (1 - t)) + half - 1
            for x in range(x0, x1 + 1):
                # jirones: a cada columna le falta un poco de ruedo
                if y > -1 - teeth[(x + 15 + hem) % len(teeth)]:
                    continue
                c = "Q" if row < h - 6 else "k"
                if x in (x0, x1) and c == "Q":
                    c = "q"
                p.dot(*self.at((x, y)), c)
        out.append(p)
        f = Piece()
        length = max(h - 4, 2)
        for row in range(length):
            y = waist + 1 + row
            w = 4 if row < length - 3 else 3 - (row - (length - 3))
            x0 = round(bx * (1 - row / max(h, 1))) - w
            for x in range(x0, x0 + 2 * w):
                f.dot(*self.at((x, y)), "G" if x in (x0, x0 + 2 * w - 1) else "P")
        out.append(f)

    def arm(self, P, out, key, shoulder, hand):
        elbow, wrist = [move(shoulder, *v) for v in P[key]]
        p = Piece()
        thick(p, self.at(shoulder), self.at(elbow), 4, "P", "Q")
        thick(p, self.at(elbow), self.at(wrist), 4, "P", "Q")
        out.append(p)
        wx, wy = self.at(wrist)
        if hand == "grip":
            return
        out.append(Piece().stamp(CUFF, wx - (1 if key == "arm_l" else 0), wy))
        art_ = {"claw": CLAW, "point": POINT, "fist": GRIP}[hand]
        if key == "arm_l":
            art_ = flip_x(art_)
        out.append(Piece().stamp(art_, wx - (1 if key == "arm_l" else 0), wy + 2))
        if P.get("palm") and key == "arm_r":
            self.effect(("orb", move(wrist, 2, 5), P["palm"]), out)

    def head(self, P, out, top):
        tx, ty = top
        jaw = P.get("jaw", 0)
        sx, sy = self.at((tx - 8, ty - 12))
        jx, jy = sx + 2, sy + 11 + jaw
        if jaw > 0:
            mouth = Piece(None)
            for y in range(sy + 11, jy):
                for x in range(jx + 1, jx + 11):
                    mouth.dot(x, y, "K")
            out.append(mouth)
        out.append(Piece(shape="cyl").stamp(JAW, jx, jy))
        self.skull(P, out, (sx, sy))

    def skull(self, P, out, xy):
        sx, sy = xy
        skull = SKULL if P.get("eyes", 1) else recolor(SKULL, {"E": "K"})
        out.append(Piece(shape="dome").stamp(skull, sx, sy))
        if P.get("crown_at"):
            cx, cy = self.at(P["crown_at"])
        else:
            dx, dy = P.get("crown", (0, 0))
            cx, cy = sx + dx, sy - 1 + dy
        crown = Piece()
        for col, hgt, lean in SPIKES:
            base = (cx + col, cy)
            tip = (cx + col + lean * (hgt // 3), cy - hgt)
            crown.line((base[0] + 1, base[1]), (tip[0] + 1, tip[1] + 2), "c")
            crown.line(base, tip, "C")
        crown.stamp(CROWN_BAND, cx, cy)
        out.append(crown)

    def staff(self, P, out):
        (x0, y0), (x1, y1) = P["staff"]
        a, b = self.at((x0, y0)), self.at((x1, y1))
        p = Piece()
        n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
        flat = abs(b[0] - a[0]) > abs(b[1] - a[1])
        for t in range(n + 1):
            x = round(a[0] + (b[0] - a[0]) * t / n)
            y = round(a[1] + (b[1] - a[1]) * t / n)
            twist = (t // 3) % 2
            p.dot(x, y, "O" if twist else "o").dot(*((x, y + 1) if flat else (x + 1, y)), "o" if twist else "O")
        out.append(p)
        rx, ry = b[0] - 8, b[1] - 8
        out.append(Piece(shape="dome").stamp(RAM, rx, ry))
        size = P.get("flame", 1)
        if size > 0:
            fl = FLAMES[min(size, len(FLAMES)) - 1]
            if P.get("flame_t", 0) % 2:
                fl = flip_x(fl)
            fw, fh = len(fl[0]), len(fl)
            out.append(Piece("f", "flat").stamp(fl, b[0] - fw // 2 + 1, ry - fh + 2))

    def heap(self, P, out):
        """Un montón de túnica en el piso, con la calavera (y la corona) encima
        y el báculo tirado al lado: el jefe dormido o muerto."""
        if P.get("staff"):
            self.staff(P, out)
        h = P["heap"]
        teeth = [1, 0, 2, 1, 0, 1, 2, 0, 1, 0, 2, 1]
        p = Piece(shape="cyl")
        for y in range(-h, 0):
            t = (y + h) / max(h, 1)
            half = round(6 + 12 * math.sqrt(t))
            for x in range(-half, half):
                if y > -1 - teeth[(x + 20) % len(teeth)] and abs(x) > half - 6:
                    continue
                c = "k" if y > -4 else ("q" if x in (-half, half - 1) or y == -h else "Q")
                p.dot(*self.at((x, y)), c)
        out.append(p)
        # el paño del frente, arrugado, con su ribete
        f = Piece()
        for y in range(-h + 3, -2):
            w = 3 + (y + h) // 3
            x0 = 3 - (y + h) // 2
            for x in range(x0, x0 + w):
                f.dot(*self.at((x, y)), "G" if x in (x0, x0 + w - 1) else "P")
        out.append(f)
        out.append(Piece(shape="dome").stamp(PAULDRON, *self.at((-19, -8))))
        out.append(Piece(shape="dome").stamp(flip_x(PAULDRON), *self.at((10, -7))))
        sx, sy = self.at(P["skull_at"])
        out.append(Piece(shape="cyl").stamp(JAW, sx + 2, sy + 11 + P.get("jaw", 0)))
        self.skull(P, out, (sx, sy))

    # -- el espectro --

    def ghost(self, G, out):
        gx, gy = G.get("at", (-15, -43))
        jaw = G.get("jaw", 0)
        aura = Piece(None, "flat")
        body = Piece("f", "flat")
        # cola: jirones que se pierden hacia abajo
        for i in range(G.get("tail", 16)):
            w = max(4 - i // 4, 1)
            for k in range(-w, w + 1):
                aura.dot(*self.at((gx + k + (1 if i % 4 == 1 else -1 if i % 4 == 3 else 0), gy + 10 + i)), "f")
        sh_l, sh_r = (gx - 6, gy + 1), (gx + 6, gy + 1)
        arms = {
            "idle": [((-7, 6), (-12, 13)), ((6, 4), (10, 8))],
            "up": [((-9, -5), (-12, -14)), ((9, -5), (12, -14))],
            "wide": [((-11, 0), (-18, -4)), ((11, 0), (18, -4))],
            "reach": [((-7, 6), (-12, 13)), ((10, 2), (21, 8))],
        }[G.get("arms", "idle")]
        for sh, (el, hd) in zip((sh_l, sh_r), arms):
            e, h = move(sh, *el), move(sh, *hd)
            body.line(self.at(sh), self.at(e), "F", "f")
            body.line(self.at(e), self.at(h), "F")
            # garras: cuatro dedos largos
            hx, hy = self.at(h)
            sx = 1 if hd[0] > 0 else -1
            up = -1 if hd[1] < el[1] else 1
            for dx, dy in ((sx * 1, up * 4), (sx * 3, up * 3), (sx * 4, up * 1), (sx * 4, -up)):
                body.line((hx, hy), (hx + dx, hy + dy), "F")
        body.stamp(G_RIBS, *self.at((gx - 5, gy)))
        body.stamp(G_JAW, *self.at((gx - 4, gy - 3 + jaw)))
        skull = Piece("f", "flat").stamp(G_SKULL, *self.at((gx - 7, gy - 12)))
        if jaw:
            mouth = Piece(None, "flat")
            for y in range(gy - 3, gy - 3 + jaw):
                for x in range(gx - 3, gx + 4):
                    mouth.dot(*self.at((x, y)), "K")
            out.append(mouth)
        # aura: dos píxeles alrededor de todo, en trama
        solid = set(body.px) | set(skull.px)
        for (x, y) in list(solid):
            for dx in (-2, -1, 0, 1, 2):
                for dy in (-2, -1, 0, 1, 2):
                    q = (x + dx, y + dy)
                    if q not in solid and abs(dx) + abs(dy) <= 2:
                        aura.px[q] = "f"
        phase = G.get("phase", 0)
        dither_piece(aura, phase)
        if G.get("alpha", 1) < 1:
            # medio formado: también el cuerpo en trama (sin contorno)
            for p in (body, skull):
                dither_piece(p, phase, keep="E")
                p.outline = None
            if G.get("alpha", 1) <= 0:
                aura.px = {}
        out.extend([aura, body, skull])

    # -- los esqueletitos --

    def mini(self, M, out, flip=False):
        mx, my = M["at"]
        kind = M.get("pose", "stand")
        sink = M.get("sink", 0)
        s = -1 if flip else 1
        if kind == "pile":
            self.mini_pile(M, out, s)
            return
        # partes relativas al piso del esqueletito; x crece hacia afuera (s)
        P = {"skull": (-4, -17), "jaw": (-2, -11), "ribs": (-2, -9), "pelvis": (-2, -6),
             "arm_o": [(-3, -9), (-5, -6)], "arm_i": [(3, -9), (5, -6)],
             "leg_o": [(-1, -5), (-2, -1)], "leg_i": [(1, -5), (2, -1)]}
        if kind == "crouch":
            P.update({"skull": (-4, -14), "jaw": (-2, -8), "ribs": (-2, -7), "pelvis": (-2, -4),
                      "arm_o": [(-3, -7), (-6, -3)], "arm_i": [(3, -7), (6, -4)],
                      "leg_o": [(-1, -3), (-4, -1)], "leg_i": [(1, -3), (4, -1)]})
        elif kind == "raise":
            P.update({"arm_o": [(-3, -9), (-5, -14)], "arm_i": [(3, -9), (5, -13)]})
        elif kind == "stab":
            P = {k: (move(v, 1, 1) if isinstance(v, tuple) else [move(q, 1, 1) for q in v]) for k, v in P.items()}
            P.update({"arm_o": [(-2, -8), (3, -5)], "arm_i": [(4, -8), (7, -6)],
                      "leg_o": [(0, -4), (-3, -1)], "leg_i": [(2, -4), (4, -1)]})
        elif kind == "jump":
            P = {k: (move(v, 0, -4) if isinstance(v, tuple) else [move(q, 0, -4) for q in v]) for k, v in P.items()}
            P.update({"arm_o": [(-3, -13), (-6, -18)], "arm_i": [(3, -13), (6, -17)],
                      "leg_o": [(-1, -9), (-3, -6)], "leg_i": [(1, -9), (3, -6)]})
        elif kind == "cower":
            P.update({"skull": (-4, -13), "jaw": (-2, -7), "ribs": (-2, -7), "pelvis": (-2, -4),
                      "arm_o": [(-3, -7), (-2, -12)], "arm_i": [(3, -7), (2, -12)],
                      "leg_o": [(-1, -3), (-4, -1)], "leg_i": [(1, -3), (4, -1)]})
        bob = M.get("bob", 0)
        if bob:
            for k in ("skull", "jaw", "ribs", "pelvis"):
                P[k] = move(P[k], 0, bob)
            for k in ("arm_o", "arm_i"):
                P[k] = [move(q, 0, bob) for q in P[k]]
            for k in ("leg_o", "leg_i"):
                P[k] = [move(P[k][0], 0, bob), P[k][1]]
        P["jaw"] = move(P["jaw"], 0, M.get("jaw", 0))

        def X(v):
            x, y = v
            return self.at((mx + s * x, my + y + sink))

        def stamp_at(a, key):
            x, y = P[key]
            if s < 0:
                x = -x - len(a[0]) + 1
                a = flip_x(a)
            return a, self.at((mx + x, my + y + sink))

        pieces = []
        for leg in ("leg_o", "leg_i"):
            a, b = P[leg]
            foot = move(b, -1, 0) if leg == "leg_o" else move(b, 1, 0)
            pieces.append(Piece().line(X(a), X(b), "W").dot(*X(foot), "B"))
        a, xy = stamp_at(art("WWWWW"), "pelvis")
        pieces.append(Piece(shape="cyl").stamp(a, *xy))
        a, xy = stamp_at(MINI_RIBS, "ribs")
        pieces.append(Piece(shape="cyl").stamp(a, *xy))
        for arm_ in ("arm_i", "arm_o"):
            a, b = P[arm_]
            pieces.append(Piece().line(X(a), X(b), "W" if arm_ == "arm_o" else "B"))
        if M.get("knife"):
            k_art, (gx, gy) = KNIFE[M["knife"]]
            if s < 0:
                k_art, gx = flip_x(k_art), len(k_art[0]) - 1 - gx
            hx, hy = X(P["arm_o"][1])
            pieces.append(Piece().stamp(k_art, hx - gx, hy - gy))
        a, xy = stamp_at(MINI_JAW, "jaw")
        pieces.append(Piece(shape="cyl").stamp(a, *xy))
        sk = MINI_SKULL if M.get("eyes", 1) else recolor(MINI_SKULL, {"E": "K"})
        a, xy = stamp_at(sk, "skull")
        pieces.append(Piece(shape="dome").stamp(a, *xy))
        if sink:
            # lo que queda bajo el piso no se ve; encima, un montículo de tierra
            gy = self.at((0, my))[1]
            for p in pieces:
                p.px = {q: c for q, c in p.px.items() if q[1] < gy - 1}
            pieces.append(Piece().stamp(DIRT, *self.at((mx - 4, my - 3))))
        out.extend(pieces)

    def mini_pile(self, M, out, s):
        mx, my = M["at"]
        for (a, b) in (((-5, -1), (0, -2)), ((1, -1), (5, -1)), ((-3, -3), (2, -4))):
            p = Piece()
            p.line(self.at((mx + s * a[0], my + a[1])), self.at((mx + s * b[0], my + b[1])), "W")
            out.append(p)
        out.append(Piece(shape="cyl").stamp(MINI_RIBS, *self.at((mx - 2, my - 4))))
        sk = MINI_SKULL if M.get("eyes", 0) else recolor(MINI_SKULL, {"E": "K"})
        dy = M.get("skull_dy", 0)
        out.append(Piece(shape="dome").stamp(sk if s > 0 else flip_x(sk), *self.at((mx - 4 + s, my - 9 + dy))))

    # -- efectos --

    def effect(self, fx, out):
        kind = fx[0]
        if kind == "orb":
            # bola de energía: núcleo que brilla a pleno y halo de espíritu
            _, c, r = fx
            core = Piece("F", "flat")
            halo = Piece(None, "flat")
            for y in range(-r - 2, r + 3):
                for x in range(-r - 2, r + 3):
                    d = math.hypot(x, y)
                    if d <= r * 0.55:
                        core.dot(*self.at((c[0] + x, c[1] + y)), "E")
                    elif d <= r:
                        core.dot(*self.at((c[0] + x, c[1] + y)), "F")
                    elif d <= r + 2 and (x + y) % 2 == 0:
                        halo.dot(*self.at((c[0] + x, c[1] + y)), "f")
            out.extend([halo, core])
        elif kind == "ring":
            # onda que se abre: anillo de espíritu, en trama si ya se apaga
            _, c, r, solid = fx
            p = Piece(None, "flat")
            for i, q in enumerate(ring(c, r, 2 if solid else 3)):
                if solid or (q[0] + q[1]) % 2 == 0:
                    p.dot(*self.at(q), "F" if solid else "f")
            out.append(p)
        elif kind == "smear":
            out.append(smear_piece(self.cv, fx[1]))
        elif kind == "sparks":
            _, c, r = fx
            p = Piece(None, "flat")
            for k in range(8):
                a = k * math.pi / 4 + 0.4
                x, y = c[0] + round(math.cos(a) * r), c[1] - round(math.sin(a) * r)
                p.dot(*self.at((x, y)), "E")
                if r > 3:
                    p.dot(*self.at((x - round(math.cos(a)), y + round(math.sin(a)))), "F")
            out.append(p)


NC = Necro()
SK = NC  # para las herramientas de vista previa

# --- Poses ---------------------------------------------------------------------------------

GHOST = {"at": (-15, -43), "arms": "idle", "alpha": 1, "phase": 0}
MINI_L = {"at": (-25, 0), "pose": "stand", "knife": "u"}
MINI_R = {"at": (28, 0), "pose": "crouch"}
BASE = {
    "body": (0, 0), "head": (0, 0), "jaw": 0, "eyes": 1, "hem": 0,
    "arm_r": [(-3, 6), (-4, 12)], "hand_r": "claw",
    "arm_l": [(3, 6), (8, 9)], "hand_l": "grip",
    "staff": ((17, 0), (17, -40)), "flame": 2, "flame_t": 0,
    "ghost": GHOST, "mini_l": MINI_L, "mini_r": MINI_R,
}


def gh(P, **kw):
    """Cambia el espectro de una pose."""
    G = dict(P["ghost"] or GHOST)
    if "dy" in kw:
        G["at"] = move(G["at"], 0, kw.pop("dy"))
    if "dx" in kw:
        G["at"] = move(G["at"], kw.pop("dx"), 0)
    G.update(kw)
    return pose(P, ghost=G)


def mn(P, key, **kw):
    """Cambia un esqueletito de una pose."""
    M = dict(P[key])
    if "dx" in kw or "dy" in kw:
        M["at"] = move(M["at"], kw.pop("dx", 0), kw.pop("dy", 0))
    M.update(kw)
    return pose(P, **{key: M})


def body(P, dx, dy, staff=True):
    """Corre el cuerpo (no el ruedo ni los pies); el báculo va con la mano."""
    bx, by = P.get("body", (0, 0))
    Q = pose(P, body=(bx + dx, by + dy))
    if staff and P.get("staff") and P.get("hand_l") == "grip":
        (x0, y0), (x1, y1) = P["staff"]
        Q["staff"] = ((x0 + dx, y0 + dy if y0 + dy <= 0 else 0), (x1 + dx, y1 + dy))
    return Q


def hold(P, wrist, lift=0, tilt=0):
    """Mano del báculo en wrist (relativo al hombro); el báculo pasa por ahí,
    levantado lift píxeles y con la punta corrida tilt."""
    Q = pose(P, arm_l=[(3, 6), wrist], hand_l="grip")
    gx, gy = NC.grip_point(Q)
    bottom = (gx - tilt // 3, min(0, -lift))
    top = (gx + tilt, -40 - lift)
    return pose(Q, staff=(bottom, top))


def idle_frame(i, n=8, P=BASE):
    breath = [0, 0, 0, 1, 1, 1, 0, 0][i * 8 // n]
    Q = body(P, 0, breath)
    Q = pose(Q, head=(0, 1 if i * 8 // n in (4, 5) else 0), hem=i // 2, flame_t=i, flame=2 + (i % 3 == 0))
    Q = gh(Q, dy=[0, 0, -1, -1, -1, 0, 0, 1][i * 8 // n], phase=i // 2 % 2)
    Q = mn(Q, "mini_l", bob=[0, 0, 1, 1, 0, 0, 1, 1][i * 8 // n], jaw=1 if i == 5 else 0)
    Q = mn(Q, "mini_r", bob=[0, 1, 1, 0, 0, 1, 1, 0][i * 8 // n], jaw=1 if i == 2 else 0)
    return Q


IDLE = [idle_frame(i) for i in range(8)]

GUARD = pose(gh(BASE, arms="wide", dy=-2), arm_r=[(-5, 3), (-9, 0)], hand_r="claw", palm=2, flame=3,
             mini_l=dict(MINI_L, pose="crouch", knife="f"), mini_r=dict(MINI_R, pose="crouch"))
GUARD = hold(GUARD, (8, 7), lift=2)


def combat_frame(i):
    Q = body(GUARD, 0, [0, 0, 1, 1, 1, 0, 0, 0][i])
    Q = pose(Q, hem=i // 2, flame_t=i, flame=3 + (i % 4 == 1), palm=2 + (i % 4 == 2),
             jaw=1 if i in (3, 4) else 0)
    Q = gh(Q, dy=[0, -1, -1, -1, 0, 0, 1, 1][i], phase=i // 2 % 2)
    Q = mn(Q, "mini_l", bob=[0, 1, 1, 0, 0, 1, 1, 0][i], jaw=i % 4 == 0)
    Q = mn(Q, "mini_r", bob=[1, 1, 0, 0, 1, 1, 0, 0][i], jaw=i % 4 == 2)
    return Q


COMBAT = [combat_frame(i) for i in range(8)]


def walk_frame(i):
    """Se desliza: el cuerpo sube y baja, el ruedo flamea, el báculo acompaña
    y los esqueletitos van dando saltitos."""
    Q = body(BASE, 0, [0, -1, -1, 0, 1, 1][i])
    Q = pose(Q, hem=i * 2, flame_t=i, flame=2)
    Q = gh(Q, dx=[0, 1, 1, 0, -1, -1][i], phase=i % 2)
    Q = mn(Q, "mini_l", bob=[0, -2, -3, -2, 0, 1][i], dy=0)
    Q = mn(Q, "mini_r", pose="stand", bob=[-2, 0, 1, 0, -2, -3][i])
    return Q


WALK = [walk_frame(i) for i in range(6)]


def attack():
    """Báculo en alto, la llama crece, lo baja de golpe y sale una bola de
    fuego espectral hacia el equipo."""
    up1 = pose(hold(BASE, (8, 4), lift=5), flame=3, jaw=1)
    up2 = gh(pose(hold(body(BASE, 0, -1), (8, 1), lift=8), flame=4, flame_t=1, jaw=2), arms="up", dy=-2)
    up3 = pose(up2, flame_t=2, palm=None)
    swing = gh(pose(hold(body(BASE, 1, 1), (9, 6), lift=2, tilt=6), flame=1, jaw=1), arms="reach")
    fire1 = pose(swing, fx=[("orb", (22, -46), 3)], flame=0)
    fire2 = pose(swing, fx=[("orb", (14, -38), 5)], flame=0)
    fire3 = pose(swing, fx=[("orb", (6, -30), 8), ("sparks", (6, -30), 11)], flame=0)
    fire4 = pose(swing, fx=[("ring", (5, -29), 12, False)], flame=1, jaw=0)
    back = pose(hold(BASE, (8, 7), lift=1), flame=2)
    return [up1, up2, up3, swing, fire1, fire2, fire3, fire4, back, BASE]


def minions_attack():
    """Señala al equipo y los esqueletitos se tiran encima: salto y cuchillazo."""
    point = pose(BASE, arm_r=[(-5, 2), (-10, -1)], hand_r="point", jaw=1)
    crouch = mn(mn(point, "mini_l", pose="crouch"), "mini_r", pose="crouch")
    jump = mn(mn(point, "mini_l", pose="jump", knife="u", dx=2, dy=-2), "mini_r", pose="jump", dx=-2, dy=-2)
    high = mn(mn(pose(point, jaw=2), "mini_l", pose="jump", knife="f", dx=5, dy=-6),
              "mini_r", pose="jump", dx=-5, dy=-6)
    stab = mn(mn(pose(point, jaw=2), "mini_l", pose="stab", knife="d", dx=9, dy=0),
              "mini_r", pose="stab", dx=-9, dy=0)
    stab = pose(stab, fx=[("smear", crescent((-14, -10), 8, 200, 330, 3)),
                          ("smear", crescent((17, -10), 8, 210, 340, 3))])
    stab2 = pose(stab, fx=[("smear", crescent((-14, -10), 8, 260, 330, 2))])
    back = mn(mn(pose(BASE, jaw=1), "mini_l", pose="jump", dx=3, dy=-3), "mini_r", pose="jump", dx=-3, dy=-3)
    land = mn(mn(BASE, "mini_l", pose="crouch"), "mini_r", pose="crouch")
    return [point, crouch, jump, high, stab, stab2, back, land, BASE]


def wail():
    """Habilidad (golpea a todo el equipo): abre los brazos, el espectro se
    alza y grita, y una onda de espíritu se abre hacia afuera."""
    spread = pose(hold(BASE, (9, 2), lift=4), arm_r=[(-6, 0), (-10, -4)], hand_r="claw", jaw=1, flame=3)
    spread = mn(mn(spread, "mini_l", pose="cower"), "mini_r", pose="cower")
    rise = gh(pose(spread, jaw=2), arms="up", dy=-4, dx=4)
    scream = gh(pose(rise, flame=4), arms="wide", dy=-6, dx=8, jaw=2)
    seq = [spread, rise, scream]
    for k, r in enumerate((8, 14, 20, 27, 34)):
        fx = [("ring", (0, -30), r, k < 2)]
        if k >= 1:
            fx.append(("ring", (0, -30), r - 7, False))
        seq.append(gh(pose(scream, fx_back=fx, flame_t=k), phase=k % 2, dy=-6 + (k % 2)))
    calm = gh(pose(spread, jaw=0, flame=2), arms="idle", dy=-2, dx=2)
    seq += [calm, gh(calm, dy=-1, dx=1), BASE]
    return seq


def taunt():
    """Se ríe: la cabeza para atrás, la mandíbula que castañetea, los hombros
    que saltan; el espectro y los esqueletitos se ríen con él."""
    laugh = pose(hold(BASE, (8, 6), lift=2), arm_r=[(-4, 4), (-5, 8)], hand_r="fist", head=(0, -1), flame=3)
    seq = []
    for i in range(10):
        j = [0, 2, 0, 2, 1, 2, 0, 2, 1, 0][i]
        Q = body(laugh, 0, [0, -1, 0, -1, 0, -1, 0, -1, 0, 0][i])
        Q = pose(Q, jaw=j, flame_t=i, hem=i // 2, head=(0, -1 if j else 0))
        Q = gh(Q, jaw=1 if j == 2 else 0, dy=-1 if j else 0, arms="wide" if 2 <= i <= 7 else "idle")
        Q = mn(Q, "mini_l", pose="jump" if i in (2, 3, 6, 7) else "stand", knife="u", jaw=1 if j else 0)
        Q = mn(Q, "mini_r", pose="jump" if i in (1, 4, 5, 8) else "crouch", jaw=1 if j else 0)
        seq.append(Q)
    seq[-1] = BASE
    return seq


def hurt_pose(P):
    Q = pose(body(P, 0, -1), head=(1, -1), jaw=2, crown=(1, -1), flame=1)
    Q = gh(Q, alpha=0, phase=1)
    Q = mn(mn(Q, "mini_l", pose="cower", knife=None), "mini_r", pose="cower")
    return Q


HURT = hurt_pose(BASE)


def hit():
    return [HURT, pose(body(BASE, 1, 1), jaw=1, flame=1), body(BASE, -1, 0), BASE]


def crown_pop():
    """La corona sale volando del golpe y vuelve a caer en su lugar."""
    a = pose(HURT, crown=(2, -5))
    b = pose(HURT, crown=(4, -9), jaw=1)
    c = pose(body(BASE, 1, 1), crown=(3, -4), jaw=1)
    d = pose(BASE, crown=(1, 1), jaw=0, head=(0, 1))
    return [a, b, c, d, BASE]


# El montón: la túnica caída, la calavera encima, el báculo tirado.
PILE = {"heap": 12, "skull_at": (-9, -24), "eyes": 0, "jaw": 0, "crown": (1, 0),
        "staff": ((-26, -1), (14, -1)), "flame": 0, "ghost": None,
        "mini_l": {"at": (-25, 0), "pose": "pile"}, "mini_r": {"at": (28, 0), "pose": "pile"}}


def collapse(dy, drop=0):
    """El cuerpo hundiéndose en la túnica (dy píxeles), con los brazos caídos."""
    Q = pose(body(BASE, 0, dy, staff=False), arm_r=[(-2, 5), (-2, 9)], arm_l=[(2, 5), (3, 9)],
             hand_r="claw", hand_l="claw", jaw=1, head=(0, drop))
    return Q


def death():
    """Tiembla, se hunde en la túnica, el báculo cae, la calavera rueda sobre
    el montón y se apaga; el espectro se va hacia arriba y los esqueletitos
    se desarman."""
    f1 = pose(body(HURT, 1, 1), flame=1)
    f2 = gh(pose(body(HURT, -1, 2), staff=((17, 0), (22, -39)), flame=1), dy=-3, alpha=0)
    f3 = gh(pose(collapse(4), staff=((17, 0), (27, -36)), flame=1), dy=-6, alpha=0, phase=1)
    f3 = mn(mn(f3, "mini_l", pose="cower", knife=None, jaw=1), "mini_r", pose="cower", jaw=1)
    f4 = gh(pose(collapse(7, 1), staff=((17, 0), (32, -27)), flame=0, eyes=1), dy=-10, alpha=0, tail=8)
    f4 = mn(mn(f4, "mini_l", pose="pile", eyes=1), "mini_r", pose="pile", eyes=1)
    f5 = gh(pose(collapse(11, 1), staff=((14, -1), (36, -12)), flame=0), dy=-14, alpha=0, phase=1, tail=4)
    f5 = mn(mn(f5, "mini_l", pose="pile", eyes=1), "mini_r", pose="pile", eyes=0)
    f6 = gh(pose(PILE, skull_at=(-9, -32), eyes=1, jaw=2), dy=-18, alpha=0, tail=0)
    f7 = pose(PILE, skull_at=(-9, -23), eyes=1, crown=(1, 2))
    f8 = pose(PILE, skull_at=(-9, -27), eyes=1, crown=(1, -1))
    f9 = pose(PILE, eyes=1)
    f10 = pose(PILE, eyes=1, skull_at=(-8, -24))
    return [HURT, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, PILE]


def spawn():
    """La entrada del jefe: en el montón se encienden los ojos, la túnica se
    levanta con él adentro, recoge el báculo (que se enciende), aparece el
    espectro y los esqueletitos salen de la tierra; se ríe y queda en guardia."""
    seq = [PILE, pose(PILE, eyes=1),
           pose(PILE, eyes=1, skull_at=(-10, -25), crown=(0, -1)),
           pose(PILE, eyes=1, skull_at=(-8, -24), flame=1)]
    staffs = [((14, -1), (36, -12)), ((17, 0), (32, -27)), ((17, 0), (25, -37)), None]
    for k, dy in enumerate((11, 7, 4, 1)):
        Q = pose(collapse(dy), staff=staffs[k], flame=1 + k // 2, eyes=1, jaw=0)
        if staffs[k] is None:
            Q = hold(pose(Q, arm_r=BASE["arm_r"]), (8, 7), lift=1)
        Q = gh(Q, alpha=0, dy=10 - 3 * k, phase=k % 2, tail=4 + 4 * k) if k >= 1 else pose(Q, ghost=None)
        Q = mn(mn(Q, "mini_l", pose="raise", sink=17 - 4 * k, knife=None), "mini_r", pose="raise", sink=18 - 4 * k)
        seq.append(Q)
    rise = pose(hold(BASE, (9, 2), lift=4), arm_r=[(-6, 0), (-10, -4)], hand_r="claw", jaw=2, flame=4, palm=2)
    rise = gh(rise, arms="wide", dy=-3)
    seq.append(mn(mn(rise, "mini_l", pose="raise", sink=2, knife="u"), "mini_r", pose="raise", sink=1))
    seq.append(mn(mn(pose(rise, flame_t=1, jaw=1), "mini_l", pose="jump"), "mini_r", pose="jump"))
    seq.append(pose(rise, flame_t=2, jaw=2, head=(0, -1)))
    seq.append(BASE)
    return seq


DORMANT = pose(PILE, mini_l=None, mini_r=None)

ANIMS = {
    "idle": (True, 1.4, {"s": IDLE}),
    "walk": (True, 0.75, {"s": WALK}),
    "combat": (True, 1.0, {"s": COMBAT}),
    "attack": (False, 1.1, {"s": attack()}),
    "attack_2": (False, 1.0, {"s": minions_attack()}),
    "ability": (False, 1.5, {"s": wail()}),
    "taunt": (False, 1.25, {"s": taunt()}),
    "hit": (False, 0.45, {"s": hit()}),
    "hit_2": (False, 0.6, {"s": crown_pop()}),
    "death": (False, 1.7, {"s": death()}),
    "spawn": (False, 1.9, {"s": spawn()}),
    "dormant": (True, 1.0, {"s": [DORMANT]}),
}


# --- El círculo de invocación (piso de la sala del jefe) ----------------------------------

CIRCLE_SIZE = 64
# Runas entre los dos anillos: trazos sueltos de 3x4 (1 = trazo).
RUNES = [
    ["1.1", "111", "1.1", "1.1"], ["11.", "1.1", "11.", "1.."], [".1.", "111", ".1.", "1.1"],
    ["1..", "11.", "1.1", "1.."], ["111", ".1.", ".1.", "11."], ["1.1", ".1.", "1.1", "1.1"],
    ["11.", ".11", "11.", ".1."], [".11", "1..", ".1.", "11."],
]


def write_circle(path=None):
    """Círculo de runas, blanco sobre transparente (el juego lo tiñe con el
    color de ojos del jefe y lo enciende en la presentación): anillo doble,
    estrella de siete puntas, runas y un anillo chico al centro."""
    n = CIRCLE_SIZE
    img = np.zeros((n, n), np.uint8)
    c = (n - 1) / 2

    def ring_px(r, val, w=1.0):
        for y in range(n):
            for x in range(n):
                if r - w < math.hypot(x - c, y - c) <= r:
                    img[y, x] = max(img[y, x], val)

    def seg(a, b, val):
        (x0, y0), (x1, y1) = a, b
        k = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for t in range(k + 1):
            x = round(x0 + (x1 - x0) * t / k)
            y = round(y0 + (y1 - y0) * t / k)
            img[y, x] = max(img[y, x], val)

    ring_px(31.5, 255, 1.2)
    ring_px(29.5, 150, 0.9)
    ring_px(21.5, 255, 1.2)
    ring_px(7.5, 200, 1.0)
    pts = [(c + 21 * math.cos(-math.pi / 2 + k * 2 * math.pi / 7), c + 21 * math.sin(-math.pi / 2 + k * 2 * math.pi / 7))
           for k in range(7)]
    for k in range(7):
        seg(pts[k], pts[(k + 3) % 7], 200)
    for k, rune in enumerate(RUNES):
        a = -math.pi / 2 + (k + 0.5) * 2 * math.pi / 8
        rx, ry = round(c + 25.5 * math.cos(a)) - 1, round(c + 25.5 * math.sin(a)) - 2
        for j, row in enumerate(rune):
            for i, ch in enumerate(row):
                if ch == "1":
                    img[ry + j, rx + i] = 255
    rgba = np.zeros((n, n, 4), np.uint8)
    rgba[..., :3] = img[..., None]
    rgba[..., 3] = np.where(img > 0, 255, 0)
    out = path or OUT_DIR / f"{SPECIES}_circulo.png"
    Image.fromarray(rgba, "RGBA").save(out, optimize=True)
    print(f"círculo: {out}")


def main(args):
    opts = dict(a[2:].split("=", 1) for a in args if a.startswith("--") and "=" in a)
    write_sheet(SPECIES, ANIMS, NC.frame, CANVAS, PPM, SELF_LIGHT, preview=opts.get("preview"))
    write_circle()
    if opts.get("gif"):
        plan = reel(ANIMS, ["dormant", "spawn", ("combat", 2), "attack", "attack_2", "ability", "taunt", "hit",
                            "hit_2", ("idle", 2), ("walk", 2), "death"])
        lit_gif(opts["gif"], plan, NC.frame, zoom=4, eye=(0.75, 0.45, 1.0))


if __name__ == "__main__":
    main(sys.argv[1:])
