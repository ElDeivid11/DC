"""El cuerpo de esqueleto que comparten el esbirro, el arquero y el guardián.

Dibuja la calavera, el tórax, la pelvis, la columna, brazos y piernas (líneas
de píxeles), pies y manos, de frente, de perfil, de espaldas y desarmado en el
piso. Lo propio de cada especie (bufanda, capucha, casco, aljaba, espada,
arco, escudo...) lo dibuja su Gear en «enganches» a lo largo del orden de
dibujo. También trae las animaciones que comparten (respirar, caminar, recibir
un golpe, derrumbarse, levantarse).
"""
import math

from pixel_kit import (HEAD, Canvas, Piece, art, bob, flip_x, jaw_open, lift, lunge, move, pose, recolor,
                       rot90, shift, squash, stretch)

CANVAS = Canvas(72, 64, 36, 58)

# --- Sellos del cuerpo ---------------------------------------------------------------------
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

# --- Poses base ------------------------------------------------------------------------------

FRONT = {
    "view": "s",
    "skull": (-7, -39), "jaw": (-5, -26), "eyes": 1,
    "ribs": (-5, -20), "spine": (-1, -13), "pelvis": (-5, -11),
    "leg_r": [(-3, -9), (-6, -6), (-6, -3)], "leg_l": [(2, -9), (5, -6), (5, -3)],
    "foot_r": (-9, -2), "foot_l": (5, -2),
    "arm_l": [(6, -19), (8, -15), (9, -11)],
    "arm_r": [(-7, -19), (-9, -15), (-11, -11)],
    "smear": None, "fx": None, "tail": 0,
}
SIDE = {
    "view": "e",
    "skull": (-5, -39), "jaw": (0, -26), "eyes": 1,
    "ribs": (-3, -20), "spine": (-3, -13), "pelvis": (-4, -11),
    "leg_n": [(-1, -9), (2, -6), (1, -3)], "leg_f": [(-2, -9), (-1, -6), (-4, -3)],
    "foot_n": (0, -2), "foot_f": (-5, -2),
    "arm_n": [(-1, -19), (-2, -15), (3, -11)], "arm_f": [(-2, -19), (-3, -15), (1, -12)],
    "smear": None, "fx": None, "tail": 0,
}


class Gear:
    """Lo que una especie le pone al esqueleto. Cada método es un enganche en
    el orden de dibujo; por defecto no dibuja nada."""
    skull = SKULL
    skull_side = SKULL_SIDE
    skull_back = SKULL_BACK
    # vendas (franjas de tela) en canillas y antebrazos: None o (claro, oscuro)
    wraps = None
    # de frente
    def behind(self, sk, P, out): pass        # detrás de todo (bufanda al viento, aljaba)
    def waist(self, sk, P, out): pass         # sobre la pelvis (cinturón, taparrabo)
    def chest(self, sk, P, out): pass         # sobre el tórax (bufanda, correas, hombreras)
    def left(self, sk, P, out): pass          # mano izquierda (de la pantalla: derecha) y lo que lleva
    def right(self, sk, P, out): pass         # mano derecha y su arma
    def head_under(self, sk, P, out): pass    # detrás de la calavera (capucha)
    def head(self, sk, P, out): pass          # sobre la calavera (capucha, casco)
    def fx(self, sk, P, out): pass            # efectos (estelas, destellos)
    # de perfil
    def side_behind(self, sk, P, out): pass
    def side_chest(self, sk, P, out): pass
    def side_near(self, sk, P, out): pass     # la mano cercana y su arma
    def side_head(self, sk, P, out): pass
    def side_head_under(self, sk, P, out): pass
    # de espaldas
    def back_first(self, sk, P, out): pass    # lo que lleva adelante (queda detrás para la cámara)
    def back_last(self, sk, P, out): pass     # lo que lleva en la espalda (aljaba, bufanda)
    def back_head(self, sk, P, out): pass
    # en el piso
    def pile_under(self, sk, P, out): pass
    def pile_items(self, sk, P, out): pass


class Skeleton:
    def __init__(self, gear, canvas=CANVAS):
        self.gear = gear
        self.cv = canvas

    def at(self, p):
        return self.cv.at(p)

    def mirror_x(self, key, P, w):
        """Esquina de un sello de ancho w espejado respecto del centro (vista de
        espaldas)."""
        x, y = P[key]
        return (self.cv.cx - x - w + 1, self.cv.ground + y)

    # -- partes --

    def _wrap(self, p, a, b, near):
        """Vendas sobre un tramo ya dibujado: franjas alternadas de tela."""
        if not self.gear.wraps:
            return
        hi, lo = self.gear.wraps
        if not near:
            hi = lo
        n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
        for t in range(1, n + 1):
            x = round(a[0] + (b[0] - a[0]) * t / n)
            y = round(a[1] + (b[1] - a[1]) * t / n)
            for (px, py) in ((x, y), (x + 1, y), (x, y + 1)):
                if (px, py) in p.px:
                    p.px[(px, py)] = hi if (py + t) % 2 else lo

    def leg(self, out, pts, near=True, mirror=False):
        hi, lo = ("W", "B") if near else ("B", "D")
        if mirror:
            pts = [(-x, y) for x, y in pts]
        p = Piece()
        a, k, f = [self.at(q) for q in pts]
        p.line(a, k, hi)
        p.line(k, f, hi, lo)
        self._wrap(p, k, f, near)
        p.dot(k[0], k[1], hi).dot(k[0] + 1, k[1], lo)
        out.append(p)

    def arm(self, out, pts, near=True, mirror=False, color=None):
        c = color or ("W" if near else "B")
        if mirror:
            pts = [(-x, y) for x, y in pts]
        p = Piece()
        s_, e, h = [self.at(q) for q in pts]
        p.line(s_, e, c)
        p.line(e, h, c)
        self._wrap(p, e, h, near)
        out.append(p)

    def hand(self, out, pt, mirror=False):
        x, y = pt
        if mirror:
            x = -x
        hx, hy = self.at((x, y))
        out.append(Piece().stamp(HAND, hx - 1, hy - 1))

    def skull_art(self, P, base):
        g = self.gear
        art_ = {"side": g.skull_side, "side_l": flip_x(g.skull_side), "back": g.skull_back}.get(P.get("skull_art"), base)
        form = P.get("form", 0)
        if form < 0:
            return squash(art_), 1
        if form > 0:
            return stretch(art_), -1
        return art_, 0

    def head(self, out, P, skull, jaw, jaw_w, at=None):
        at = at or self.at
        skull, dy = self.skull_art(P, skull)
        sx, sy = at(P["skull"])
        jx, jy = at(P["jaw"])
        if sy + 13 < jy <= sy + 16:
            # boca abierta: el hueco entre los dientes
            mouth = Piece(None)
            for y in range(sy + 12, jy):
                for x in range(jx + 1, jx + jaw_w - 1):
                    mouth.dot(x, y, "K")
            out.append(mouth)
        out.append(Piece(shape="cyl").stamp(jaw, jx, jy))
        if P["eyes"] < 1:
            skull = recolor(skull, {"E": "K"})
        out.append(Piece(shape="dome").stamp(skull, sx, sy + dy))

    # -- vistas --

    def build(self, P):
        if P.get("pile") is not None:
            return self.pile(P)
        return {"s": self.front, "e": self.side, "n": self.back}[P["view"]](P)

    def frame(self, P):
        return self.cv.to_rgba(*self.cv.render(self.build(P)))

    def front(self, P):
        g, out = self.gear, []
        g.behind(self, P, out)
        self.leg(out, P["leg_r"])
        self.leg(out, P["leg_l"])
        out.append(Piece().stamp(FOOT, *self.at(P["foot_r"])))
        out.append(Piece().stamp(flip_x(FOOT), *self.at(P["foot_l"])))
        out.append(Piece(shape="cyl").stamp(PELVIS, *self.at(P["pelvis"])))
        g.waist(self, P, out)
        out.append(Piece(shape="cyl").stamp(SPINE, *self.at(P["spine"])))
        out.append(Piece(shape="cyl").stamp(RIBS, *self.at(P["ribs"])))
        g.chest(self, P, out)
        if not P.get("left_front"):
            self.arm(out, P["arm_l"])
            g.left(self, P, out)
        if not P.get("weapon_front"):
            self.arm(out, P["arm_r"])
            g.right(self, P, out)
        g.head_under(self, P, out)
        self.head(out, P, g.skull, JAW, 10)
        g.head(self, P, out)
        # lo que pasa por delante de la cabeza (un arma en alto, un arco tenso)
        if P.get("left_front"):
            self.arm(out, P["arm_l"])
            g.left(self, P, out)
        if P.get("weapon_front"):
            self.arm(out, P["arm_r"])
            g.right(self, P, out)
        g.fx(self, P, out)
        return out

    def back(self, P):
        """De espaldas: la pose de frente espejada, con los sellos de atrás."""
        g, out = self.gear, []
        g.back_first(self, P, out)
        self.leg(out, P["leg_r"], mirror=True)
        self.leg(out, P["leg_l"], mirror=True)
        out.append(Piece().stamp(flip_x(FOOT), *self.mirror_x("foot_r", P, 4)))
        out.append(Piece().stamp(FOOT, *self.mirror_x("foot_l", P, 4)))
        for key, art_, w in (("pelvis", PELVIS_BACK, 10), ("spine", SPINE, 2), ("ribs", RIBS_BACK, 10)):
            out.append(Piece(shape="cyl").stamp(art_, *self.mirror_x(key, P, w)))
        for key in ("arm_l", "arm_r"):
            self.arm(out, P[key], mirror=True)
            self.hand(out, P[key][2], mirror=True)
        art_, dy = self.skull_art(pose(P, skull_art=None), g.skull_back)
        bx, by = self.mirror_x("skull", P, 14)
        out.append(Piece(shape="dome").stamp(art_, bx, by + dy))
        g.back_head(self, P, out)
        g.back_last(self, P, out)
        return out

    def side(self, P):
        g, out = self.gear, []
        self.arm(out, P["arm_f"], near=False)
        self.leg(out, P["leg_f"], near=False)
        out.append(Piece().stamp(recolor(FOOT_SIDE, {"W": "B", "B": "D"}), *self.at(P["foot_f"])))
        g.side_behind(self, P, out)
        out.append(Piece(shape="cyl").stamp(PELVIS_SIDE, *self.at(P["pelvis"])))
        out.append(Piece(shape="cyl").stamp(SPINE, *self.at(P["spine"])))
        out.append(Piece(shape="cyl").stamp(RIBS_SIDE, *self.at(P["ribs"])))
        self.leg(out, P["leg_n"])
        out.append(Piece().stamp(FOOT_SIDE, *self.at(P["foot_n"])))
        g.side_chest(self, P, out)
        g.side_head_under(self, P, out)
        self.head(out, P, g.skull_side, JAW_SIDE, 7)
        g.side_head(self, P, out)
        self.arm(out, P["arm_n"])
        g.side_near(self, P, out)
        return out

    def pile(self, P):
        g, out = self.gear, []
        g.pile_under(self, P, out)
        for b0, b1 in P["bones"]:
            p = Piece()
            (x0, y0), (x1, y1) = self.at(b0), self.at(b1)
            p.line((x0, y0), (x1, y1), "W")
            p.dot(x0, y0 + 1, "B").dot(x1, y1 + 1, "B").dot(x0 - 1, y0, "W").dot(x1 + 1, y1, "W")
            out.append(p)
        out.append(Piece(shape="cyl").stamp(rot90(RIBS), *self.at(P["ribs"])))
        out.append(Piece(shape="cyl").stamp(PELVIS, *self.at(P["pelvis"])))
        g.pile_items(self, P, out)
        out.append(Piece(shape="cyl").stamp(JAW, *self.at(P["jaw"])))
        skull, dy = self.skull_art(P, g.skull)
        if P["eyes"] < 1:
            skull = recolor(skull, {"E": "K"})
        px_, py_ = self.at(P["skull"])
        out.append(Piece(shape="dome").stamp(skull, px_, py_ + dy))
        g.fx(self, P, out)
        return out


# --- Animaciones que comparten -------------------------------------------------------------

def idle(P, i):
    """Respira: baja el cuerpo, la cabeza baja un poco después y sube última;
    la mandíbula se abre un pelo al soltar el aire. 8 cuadros."""
    seq = [P, P, bob(P, 1), bob(P, 1, head=1), jaw_open(bob(P, 1, head=1), 1), bob(P, 0, head=1), P, P]
    return pose(seq[i], tail=i)


def walk_front(P, i):
    """Hacia la cámara (o de espaldas): apoyo, levanta un pie, lo pasa alto
    (el cuerpo se estira y se balancea al otro lado), y lo mismo con el otro.
    6 cuadros."""
    r_up = pose(P, arm_r=move(P["arm_r"], 0, -1), arm_l=move(P["arm_l"], 0, 1))
    l_up = pose(P, arm_l=move(P["arm_l"], 0, -1), arm_r=move(P["arm_r"], 0, 1))
    seq = [bob(P, 1), bob(lift(r_up, "foot_r", 1), 0, dx=1), bob(lift(r_up, "foot_r", 3), -1, dx=1),
           bob(P, 1), bob(lift(l_up, "foot_l", 1), 0, dx=-1), bob(lift(l_up, "foot_l", 3), -1, dx=-1)]
    return pose(seq[i], tail=i)


def walk_side(P, i):
    """De perfil: cada pie avanza en el aire y vuelve apoyado (un círculo);
    el cuerpo baja con los pies abiertos y sube al pasar; los brazos van al
    revés que las piernas. 6 cuadros."""
    a = 2 * math.pi * i / 6
    xn, ln_ = round(3 * math.cos(a)), round(max(0.0, -math.sin(a)) * 3)
    xf, lf = round(-3 * math.cos(a)), round(max(0.0, math.sin(a)) * 3)
    Q = lift(lift(P, "foot_n", ln_, xn), "foot_f", lf, xf)
    Q = pose(Q, arm_n=move(P["arm_n"], -round(math.cos(a)), 0), arm_f=move(P["arm_f"], round(math.cos(a)), 0))
    return pose(bob(Q, 1 if abs(math.cos(a)) > 0.6 else -1 if abs(math.cos(a)) < 0.2 else 0), tail=i)


def hit(G, hurt):
    """Golpe: retrocede con la boca abierta y se sacude."""
    return [hurt, jaw_open(shift(lunge(G, -1, 0), 0, -1, ("skull",)), 1), lunge(G, 1, 0), G]


def hit_skull(G):
    """La calavera salta del golpe, da una vuelta en el aire y cae aplastada."""
    J = jaw_open(G, 1)
    return [pose(shift(J, 0, -3, ("skull",)), form=1),
            pose(shift(J, 1, -7, ("skull",)), skull_art="side"),
            pose(shift(J, 1, -9, ("skull",)), skull_art="back"),
            pose(shift(J, 0, -6, ("skull",)), skull_art="side_l"),
            pose(shift(G, 0, 1, ("skull",)), form=-1),
            G]


def death(hurt, crumble, pile):
    """Se derrumba, la calavera cae, rebota en el montón y se apaga."""
    return [hurt, crumble[0], crumble[1], crumble[2],
            pose(pile, eyes=1, skull=move(pile["skull"], 0, -7), jaw=move(pile["skull"], 2, 6)),
            pose(pile, eyes=1, form=-1),
            pose(pile, eyes=1, skull=move(pile["skull"], 0, -3)),
            pose(pile, eyes=1),
            pose(pile, eyes=0, skull=move(pile["skull"], 1, 0)),
            pile]


def spawn(crumble, pile, rise, guard):
    """Del montón: se encienden los ojos, tiemblan los huesos, la calavera sube
    y el cuerpo se arma; grita estirado y queda en guardia."""
    return [pile,
            pose(pile, eyes=1),
            pose(pile, eyes=1, skull=move(pile["skull"], -1, 0), jaw=move(pile["jaw"], -1, -1)),
            pose(pile, eyes=1, skull=move(pile["skull"], 1, -1), jaw=move(pile["jaw"], 0, 0)),
            pose(pile, eyes=1, skull=move(pile["skull"], 0, -7), jaw=move(pile["skull"], 2, 6), form=1),
            crumble[2], crumble[1], crumble[0],
            rise,
            pose(bob(guard, 1), form=-1),
            guard]


def crumble_poses(G, buckle_kw, knees_kw, flat_kw):
    """Tres cuadros del esqueleto viniéndose abajo: se le doblan las rodillas,
    se arrodilla y queda tirado con la calavera cayendo. *_kw: lo de cada
    especie en cada cuadro (dónde quedan el arma, el escudo...)."""
    from pixel_kit import arm as _arm
    buckle = pose(_arm(_arm(bob(G, 2, head=1), "arm_r", (-3, 4), (-5, 8)), "arm_l", (2, 4), (3, 8)), **buckle_kw)
    knees = pose(_arm(_arm(bob(G, 4, head=1), "arm_r", (-3, 4), (-6, 8)), "arm_l", (3, 4), (5, 7)),
                 leg_r=[(-3, -6), (-8, -5), (-8, -3)], leg_l=[(2, -6), (7, -5), (7, -3)], **knees_kw)
    flat = pose(bob(G, 6), skull=(-6, -28), jaw=(-4, -15), arm_r=[(-7, -12), (-11, -8), (-13, -4)],
                arm_l=[(6, -12), (9, -9), (11, -5)],
                leg_r=[(-3, -4), (-8, -4), (-10, -2)], leg_l=[(2, -4), (7, -4), (9, -2)],
                foot_r=(-12, -2), foot_l=(8, -2), **flat_kw)
    return [jaw_open(buckle, 2), knees, flat]
