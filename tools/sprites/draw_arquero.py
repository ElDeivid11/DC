"""Esqueleto arquero en pixel art grueso (diseño de David): capucha verde,
cicatriz roja pintada, hombrera con púa, aljaba, cinturón con hebilla,
taparrabo morado, vendas, musgo y un arco de rama retorcida.

    python3 -I tools/sprites/draw_arquero.py [--preview=/tmp/hoja.png] [--gif=/tmp/anim.gif]

Escribe assets/sprites/enemies/esqueleto_picaro.* (la especie se llama así en
data/species.json). El cuerpo sale de skeleton.py.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import skeleton as sk  # noqa: E402
from pixel_kit import (HEAD, Piece, arm, art, bob, jaw_open, lit_gif, lunge, move, pose, reel,  # noqa: E402
                       rot90, shift, write_sheet)


def patch(a, pixels):
    """Copia de un sello con algunos píxeles cambiados: {(col, fila): color}."""
    rows = [list(r) for r in a]
    for (x, y), c in pixels.items():
        rows[y][x] = c
    return ["".join(r) for r in rows]


# --- Sellos ----------------------------------------------------------------------------

# La calavera con la cicatriz roja sobre el ojo derecho (de la pantalla) y
# musgo en la frente.
SKULL = patch(sk.SKULL, {(11, 4): "R", (12, 5): "R", (11, 5): "R", (12, 6): "r", (3, 3): "M", (4, 3): "M"})
SKULL_SIDE = patch(sk.SKULL_SIDE, {(9, 4): "R", (10, 5): "R", (4, 2): "M"})
# Capucha: lo que va detrás de la calavera (el fondo oscuro y la caída sobre
# los hombros) y el borde que la tapa por arriba y a los costados. Origen: la
# esquina de la calavera corrida (-3, -5).
HOOD_BACK = art("""
....................
....................
....................
....................
....................
...vvvvvvvvvvvvvv...
..vvvvvvvvvvvvvvvv..
..vvvvvvvvvvvvvvvv..
..vvvvvvvvvvvvvvvv..
..vvvvvvvvvvvvvvvv..
..vvvvvvvvvvvvvvvv..
..vvvvvvvvvvvvvvvv..
..vvvvvvvvvvvvvvvv..
..vvvvvvvvvvvvvvvv..
.vvvvvvvvvvvvvvvvvv.
.vvvvvvvvvvvvvvvvvv.
VVvvvvvvvvvvvvvvvvVV
VVVVvvvvvvvvvvvvVVVV
VVVVVVVvvvvvvVVVVVVV
.VVVVVVVVVVVVVVVVVV.
..VVVVVVVVVVVVVVVV..
""")
HOOD = art("""
..........HH........
........HHHHV.......
......HHHHHHHVV.....
....HHHHHHHHHHHVV...
...HHHHHHHHHHHHHVV..
..HHHHHHHHHHHHHHHVV.
.HHHHHHHHMHHHHHHHVV.
.HHHHHHHHHHHHHHHHVVV
HHHHVVVVVVVVVVVVHVVV
HHVv............vVVV
HHv..............vVV
HHv..............vVV
HVv..............vVv
HV................Vv
HV................Vv
HV................Vv
""")
HOOD_SIDE = art("""
.....HHH........
...HHHHHHV......
..HHHHHHHHVV....
.HHHHHHHHHHVV...
HHHHHHMHHHHHVV..
HHHHHHHHHHHHVV..
HHHHHHHHHHHVVV..
HHHHHHHHVVVv....
HHHHHHHVv.......
HHHHHHVv........
HHHHHHv.........
HHHHHVv.........
HHHHHV..........
VHHHVV..........
VVVVV...........
.VVV............
""")
HOOD_BACK_VIEW = art("""
.........HH.........
.......HHHHV........
.....HHHHHHHVV......
...HHHHHHHHHHHVV....
..HHHHHHHHHHHHHVV...
.HHHHHHHHHHHHHHHVV..
.HHHHHHHMHHHHHHHVV..
HHHHHHHHHHHHHHHHHVV.
HHHHHHHHHHHHHHHHHVV.
HHHHHHHHHHHHHHHHHVVV
HHHHHHHHHHHHHHHHVVVV
HHHHHHHHHHHHHHHHVVVv
VHHHHHHHHHHHHHHVVVVv
VVHHHHHHHHHHHHVVVVvv
VVVVHHHHHHHHVVVVVvv.
.VVVVVVVVVVVVVVVvv..
..vVVVVVVVVVVVVvv...
""")
# Con la capucha caída (golpe): un rollo de tela sobre los hombros.
HOOD_DOWN = art("""
.HHHHHHHHHHHHHHHH.
HHVVVVVVVVVVVVVVHH
.VVVVVVVVVVVVVVVV.
""")
# La capa rota que cuelga atrás (se ve entre las piernas y a los costados).
CAPE = [art("""
.VVVVVVVVVVVVVVVV.
VVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVV
VvVVVVVVVVVVVVVVvV
VvVVVVVVVVVVVVVVvV
VvVVVVVVVVVVVVVVvV
vvVVVVVVVVVVVVVVvv
vvvVVVVVVVVVVVVvvv
vvvvVVVVVVVVVVvvvv
.vvvVVvVVVVvVVvvv.
.vv.vVvvVVvvVv.vv.
..v..v..vv..v..v..
"""), art("""
.VVVVVVVVVVVVVVVV.
VVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVV
VvVVVVVVVVVVVVVVvV
VvVVVVVVVVVVVVVVvV
VvVVVVVVVVVVVVVVvV
vvVVVVVVVVVVVVVVvv
vvvVVVVVVVVVVVVvvv
vvvvVVVVVVVVVVvvvv
.vvvVVvVVVVvVVvvv.
..vv.vVvvVvvVvv.v.
.v..v..vv..v...v..
""")]
CAPE_SIDE = art("""
VVVVV..
VVVVVV.
VVVVVV.
VVVVVVV
VvVVVVV
VvVVVVv
vvVVVVv
vvVVVvv
vvvVVvv
.vvVvv.
.v.vv.v
..v..v.
""")
# Aljaba de cuero con flechas (plumas moradas y verdes); de frente asoma por
# detrás del hombro derecho (izquierda de la pantalla).
QUIVER = art("""
T.H.T.
TTHHTT
.T.HT.
.NNNN.
.NnnN.
.NNNn.
.NnNn.
.NNnN.
.nNNn.
.NnNn.
..nn..
""")
QUIVER_BACK = art("""
...........T.H.T
..........TTHHTT
...........THT..
.........NNNNN..
........NNnnN...
.......NNNnN....
......NnNNn.....
.....NNnNn......
....NnNNn.......
...NNnNn........
..NnNNn.........
.NNnNn..........
.nNNn...........
..nn............
""")
PAULDRON = art("""
...S..
..NNN.
.NNNNn
NNnNNn
.nnnn.
""")
STRAP = art("""
N.........
nN........
.nN.......
..nN......
...nN.....
....nN....
.....nN...
......nN..
.......SN.
........nN
""")
BELT = art("""
NNNNSSNNNN
nnnnSsnnnn
""")
BELT_SIDE = art("""
NNSNNN
nnsnnn
""")
LOINCLOTH = art("""
QPPQ
QPPQ
QPYQ
.QY.
.Q..
""")
# Arco de rama, de canto (la cuerda del lado del cuerpo). Lo agarra por el
# vendaje del medio.
BOW = art("""
.O......
..O.....
..oO....
...oO...
....O...
....oO..
.....O..
.....oO.
......O.
......O.
......U.
......U.
......U.
......O.
......O.
.....oO.
.....O..
....oO..
....O...
...oO...
..oO....
..O.....
.O......
T.......
T.......
""")
BOW_GRIP = (6, 11)
BOW_TIPS = ((1, 0), (1, 22))
# Arco levantado delante de la cara para tirarle a la cámara: casi recto,
# con la cuerda en «V» hasta la mano.
BOW_AIM = art("""
O..
.O.
.oO
..O
..O
..O
..O
..O
..O
..U
..U
..U
..O
..O
..O
..O
..O
..O
..O
.oO
.O.
O..
T..
""")
BOW_AIM_GRIP = (2, 10)
BOW_AIM_TIPS = ((0, 0), (0, 21))
ARROWHEAD = art("""
.S.
SSs
.s.
""")
# La flecha que sale hacia la cámara (se ve la punta, grande).
ARROW_COMING = art("""
..x..
.xSx.
xSXSx
.xSx.
..x..
""")
QUIVER_PILE = art("""
.T.........
TTH........
.HNNNNNNNn.
..nNnNnNnn.
...nnnnnn..
""")
BOW_PILE = art("""
.O..................
..OO..............T.
....OOooUUUOooOO.TT.
................OO..
""")


def bow(s, out, grip, mode="side", string_to=None):
    """El arco con su cuerda. mode: "side" (de canto, en la mano), "ready"
    (horizontal a la cintura, en guardia) o "aim" (levantado delante de la
    cara). string_to = adónde tira la cuerda (la mano derecha)."""
    if mode == "ready":
        a, (gx, gy), tips = BOW_READY, BOW_READY_GRIP, BOW_READY_TIPS
    elif mode == "aim":
        a, (gx, gy), tips = BOW_AIM, BOW_AIM_GRIP, BOW_AIM_TIPS
    else:
        a, (gx, gy), tips = BOW, BOW_GRIP, BOW_TIPS
    hx, hy = s.at(grip)
    x0, y0 = hx - gx, hy - gy
    (t0x, t0y), (t1x, t1y) = [(x0 + tx, y0 + ty) for tx, ty in tips]
    string = Piece(None, "flat")
    if string_to:
        px, py = s.at(string_to)
        string.line((t0x, t0y), (px, py), "U").line((px, py), (t1x, t1y), "U")
    else:
        string.line((t0x, t0y), (t1x, t1y), "U")
    out.append(Piece().stamp(a, x0, y0))
    out.append(string)


def _rot_cw(p, h):
    """Dónde cae (x, y) de un sello de alto h al girarlo 90° (horario)."""
    x, y = p
    return (h - 1 - y, x)


BOW_READY = rot90(BOW)
BOW_READY_GRIP = _rot_cw(BOW_GRIP, len(BOW))
BOW_READY_TIPS = tuple(_rot_cw(t, len(BOW)) for t in BOW_TIPS)


class Arquero(sk.Gear):
    skull = SKULL
    skull_side = SKULL_SIDE
    wraps = ("U", "u")

    def behind(self, s, P, out):
        out.append(Piece().stamp(CAPE[P["tail"] % 2], *s.at(P["cape"])))
        out.append(Piece().stamp(QUIVER, *s.at(P["quiver"])))

    def waist(self, s, P, out):
        x, y = s.at(P["pelvis"])
        out.append(Piece(shape="cyl").stamp(BELT, x, y - 1))
        out.append(Piece().stamp(LOINCLOTH, x + 3, y + 1))

    def chest(self, s, P, out):
        x, y = s.at(P["ribs"])
        out.append(Piece().stamp(STRAP, x, y))
        out.append(Piece(shape="dome").stamp(PAULDRON, *s.at(P["pauldron"])))

    def left(self, s, P, out):
        hand = P["arm_l"][2]
        mode = P.get("bow", "side")
        if mode != "none":
            bow(s, out, hand, mode, P.get("draw"))
        out.append(Piece().stamp(sk.HAND, *move(s.at(hand), -1, -1)))
        if P.get("arrow") and mode == "aim":
            # la punta de la flecha, en la empuñadura, apuntando a la cámara
            gx, gy = s.at(hand)
            out.append(Piece().stamp(ARROWHEAD, gx - 2, gy - 1))

    def right(self, s, P, out):
        out.append(Piece().stamp(sk.HAND, *move(s.at(P["arm_r"][2]), -1, -1)))
        if P.get("arrow") and P.get("bow") == "ready":
            # flecha cargada sobre el arco, la punta hacia la derecha
            hx, hy = s.at(P["arm_r"][2])
            shaft = Piece()
            shaft.line((hx, hy - 2), (hx + 16, hy - 2), "O")
            shaft.dot(hx - 1, hy - 3, "T").dot(hx - 1, hy - 1, "T")
            out.append(shaft)
            out.append(Piece().stamp(ARROWHEAD, hx + 16, hy - 3))

    def head_under(self, s, P, out):
        if P.get("hood", "up") == "up":
            x, y = s.at(P["skull"])
            out.append(Piece().stamp(HOOD_BACK, x - 3, y - 5))

    def head(self, s, P, out):
        x, y = s.at(P["skull"])
        if P.get("hood", "up") == "up":
            out.append(Piece().stamp(HOOD, x - 3, y - 5))
        else:
            out.append(Piece(shape="cyl").stamp(HOOD_DOWN, x - 2, y + 16))

    def fx(self, s, P, out):
        if P.get("fx") in ("shot", "shot_small"):
            gx, gy = s.at(P["arm_l"][2])
            p = Piece("x", "flat")
            big = P["fx"] == "shot"
            r = 6 if big else 4
            for d in range(-r, r + 1):
                if abs(d) > 2:
                    p.dot(gx + d, gy, "X").dot(gx, gy + d, "X")
            for d in ((-4, -3, 3, 4) if big else (-3, 3)):
                p.dot(gx + d, gy + d, "X").dot(gx + d, gy - d, "X")
            out.append(p)
            out.append(Piece("x", "flat").stamp(ARROW_COMING, gx - 2, gy - 2))

    # de perfil
    def side_behind(self, s, P, out):
        out.append(Piece().stamp(CAPE_SIDE, *s.at(P["cape"])))
        out.append(Piece().stamp(QUIVER, *s.at(P["quiver"])))

    def side_chest(self, s, P, out):
        x, y = s.at(P["pelvis"])
        out.append(Piece(shape="cyl").stamp(BELT_SIDE, x, y - 1))
        out.append(Piece().stamp(PAULDRON, *s.at(P["pauldron"])))

    def side_head(self, s, P, out):
        x, y = s.at(P["skull"])
        out.append(Piece().stamp(HOOD_SIDE, x - 2, y - 4))

    def side_near(self, s, P, out):
        hand = P["arm_n"][2]
        out.append(Piece().stamp(sk.HAND, *move(s.at(hand), -1, -1)))
        bow(s, out, move(hand, 1, 0))

    # de espaldas
    def back_first(self, s, P, out):
        x, y = P["arm_l"][2]
        bow(s, out, (-x, y))

    def back_head(self, s, P, out):
        bx, by = s.mirror_x("skull", P, 14)
        out.append(Piece().stamp(HOOD_BACK_VIEW, bx - 3, by - 5))

    def back_last(self, s, P, out):
        x, y = s.mirror_x("ribs", P, 10)
        out.append(Piece().stamp(QUIVER_BACK, x - 4, y - 6))

    # en el piso
    def pile_under(self, s, P, out):
        out.append(Piece().stamp(BOW_PILE, *s.at(P["bow_at"])))

    def pile_items(self, s, P, out):
        out.append(Piece().stamp(QUIVER_PILE, *s.at(P["quiver"])))
        out.append(Piece(shape="cyl").stamp(HOOD_DOWN, *s.at(P["hood_at"])))


SK = sk.Skeleton(Arquero())

# --- Poses -----------------------------------------------------------------------------

FRONT = pose(sk.FRONT, cape=(-9, -24), quiver=(-14, -34), pauldron=(-11, -23), bow="side",
             arm_l=[(6, -19), (9, -16), (11, -14)], arm_r=[(-7, -19), (-9, -15), (-10, -11)])
SIDE = pose(sk.SIDE, cape=(-9, -23), quiver=(-9, -33), pauldron=(-4, -23),
            arm_n=[(-1, -19), (-1, -16), (3, -14)])
BACK = pose(FRONT, view="n")
# En guardia: el arco horizontal a la cintura, la flecha cargada.
READY = bob(pose(FRONT, bow="ready", arrow=True, foot_r=(-10, -2), foot_l=(6, -2),
                 leg_r=[(-3, -9), (-7, -6), (-7, -3)], leg_l=[(2, -9), (6, -6), (6, -3)],
                 arm_l=[(6, -19), (7, -15), (5, -13)], arm_r=[(-7, -19), (-8, -15), (-6, -12)]), 1)
# Apunta: el arco levantado delante de la cara, la cuerda tensa hasta el mentón.
AIM = pose(READY, bow="aim", left_front=True, weapon_front=True,
           arm_l=[(6, -18), (5, -21), (3, -23)], arm_r=[(-7, -18), (-9, -22), (-4, -24)])
AIM = pose(AIM, draw=AIM["arm_r"][2])
HURT = jaw_open(pose(arm(arm(shift(lunge(READY, 1, 0), 1, -2, ("skull",)), "arm_r", (-4, 1), (-7, -3)),
                         "arm_l", (3, 1), (6, -2)), arrow=False, draw=None, bow="side", form=1, tail=1), 2)
PILE = {
    "pile": 1, "view": "s", "eyes": 0,
    "skull": (-5, -17), "jaw": (6, -5),
    "ribs": (-11, -10), "pelvis": (-4, -5), "quiver": (4, -8), "bow_at": (-20, -4), "hood_at": (-7, -7),
    "bones": [((-13, -2), (-4, -3)), ((-6, -2), (3, -1)), ((2, -3), (11, -2)), ((-9, -5), (-1, -2)),
              ((5, -6), (13, -4))],
    "smear": None, "fx": None,
}


def drawn(P, hand):
    """Tensa la cuerda hasta la mano derecha (rel. al hombro)."""
    Q = arm(P, "arm_r", (-2, -4), hand)
    return pose(Q, draw=Q["arm_r"][2])


def combat(i):
    """En guardia con la flecha cargada; respira y la capa se mueve."""
    seq = [READY, READY, bob(READY, 1), bob(READY, 1, head=1), jaw_open(bob(READY, 0, head=1), 1), READY]
    return pose(seq[i], tail=i % 2)


def release(P, big=True):
    """Suelta: la cuerda vuelve, la flecha sale hacia la cámara, la mano
    derecha se va atrás y el cuerpo retrocede."""
    Q = arm(lunge(P, -1, 0), "arm_r", (-3, -3), (-6, -6))
    return jaw_open(pose(Q, arrow=False, draw=None, fx="shot" if big else "shot_small"), 2 if big else 1)


def attack():
    """Levanta el arco, tensa (se estira), suelta y la flecha sale hacia la
    cámara; vuelve a la guardia."""
    full = pose(drawn(shift(bob(AIM, -1), -1, 0, HEAD), (2, -6)), form=1)
    return [
        pose(bob(READY, 1), form=-1),
        AIM,
        full,
        pose(full, tail=1),
        release(AIM),
        pose(release(AIM, big=False), form=-1),
        pose(arm(READY, "arm_r", (-2, 3), (0, 6)), arrow=False),
        READY,
    ]


def double_shot():
    """Dos flechas seguidas, la segunda más apurada."""
    reload_ = pose(drawn(AIM, (5, -4)), arrow=True)
    return [AIM, drawn(AIM, (2, -6)), release(AIM), reload_, drawn(shift(AIM, -1, 0, HEAD), (2, -6)),
            release(AIM), pose(arm(READY, "arm_r", (-2, 3), (0, 6)), arrow=False), READY]


def hood_off():
    """El golpe le tira la capucha atrás; sacude la cabeza, se enoja y se la
    vuelve a poner."""
    down = pose(READY, hood="down", arrow=False)
    return [pose(HURT, hood="down"),
            jaw_open(shift(down, 1, 0, HEAD), 1),
            jaw_open(shift(down, -1, 0, HEAD), 2),
            pose(arm(down, "arm_r", (-1, -8), (4, -15)), form=1, weapon_front=True),
            pose(arm(READY, "arm_r", (-1, -8), (3, -14)), arrow=False, form=-1, weapon_front=True),
            READY]


CRUMBLE = sk.crumble_poses(READY, {"bow": "none", "arrow": False}, {"bow": "none", "arrow": False},
                           {"bow": "none", "arrow": False})
RISE = jaw_open(pose(arm(arm(bob(READY, -1), "arm_r", (-4, -5), (-5, -10)), "arm_l", (4, -3), (7, -5)),
                     bow="side", arrow=False, form=1), 2)

ANIMS = {
    "idle": (True, 1.6, {"s": [pose(sk.idle(FRONT, i), tail=i // 2) for i in range(8)],
                         "e": [sk.idle(SIDE, i) for i in range(8)],
                         "n": [sk.idle(BACK, i) for i in range(8)]}),
    "walk": (True, 0.8, {"s": [sk.walk_front(FRONT, i) for i in range(6)],
                         "e": [sk.walk_side(SIDE, i) for i in range(6)],
                         "n": [sk.walk_front(BACK, i) for i in range(6)]}),
    "combat": (True, 1.2, {"s": [combat(i) for i in range(6)]}),
    "attack": (False, 0.9, {"s": attack()}),
    "attack_2": (False, 1.0, {"s": double_shot()}),
    "hit": (False, 0.45, {"s": sk.hit(READY, HURT)}),
    "hit_2": (False, 0.8, {"s": hood_off()}),
    "death": (False, 1.5, {"s": sk.death(HURT, CRUMBLE, PILE)}),
    "spawn": (False, 1.6, {"s": sk.spawn(CRUMBLE, PILE, RISE, READY)}),
    "dormant": (True, 1.0, {"s": [PILE]}),
}
SPECIES = "esqueleto_picaro"
PPM = 24
SELF_LIGHT = 0.3


def main(args):
    opt = {a.split("=", 1)[0]: a.split("=", 1)[1] for a in args if "=" in a}
    write_sheet(SPECIES, ANIMS, SK.frame, SK.cv, PPM, SELF_LIGHT, opt.get("--preview"))
    if "--gif" in opt:
        plan = reel(ANIMS, [("idle", 2), ("combat", 2), "attack", "combat", "attack_2", "combat", "hit", "hit_2",
                            "combat", "death", ("dormant", 3), "spawn", "combat"])
        lit_gif(opt["--gif"], plan, SK.frame)


if __name__ == "__main__":
    main(sys.argv[1:])
