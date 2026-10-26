"""Esqueleto guardián en pixel art grueso (élite): casco de hierro con
cuernos, hombreras, túnica azul con ribete dorado, hacha y un escudo redondo
de bronce.

    python3 -I tools/sprites/draw_guardian.py [--preview=/tmp/hoja.png] [--gif=/tmp/anim.gif]

Escribe assets/sprites/enemies/esqueleto_guardian.*. El cuerpo sale de
skeleton.py.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import skeleton as sk  # noqa: E402
from pixel_kit import (HEAD, MIRROR, Piece, arm, art, bob, crescent, flip_x, jaw_open, lit_gif, lunge,  # noqa: E402
                       move, oriented, pose, reel, rot90, rot_point, shift, smear_piece, write_sheet)

# --- Sellos ----------------------------------------------------------------------------

# Casco: va sobre la calavera corrido (-2, -5). Cuernos hacia arriba y afuera,
# banda de bronce, protector de nariz y carrilleras.
HELMET = art("""
C................C
CC..............CC
cCC....IIII....CCc
.cCC.IIIIIIII.CCc.
..cCIIIIIIIIIIiCc.
...IIIIIIIIIIIIii.
..IIIIIIIIIIIIIiii
..IIiIIIIIIIIIiiii
..ZZZZZZZZZZZZZZzz
..Ii.....II....ii.
..I......II.....i.
..I......I......i.
""")
HELMET_SIDE = art("""
.............C..
............CC..
......IIIIICc...
....IIIIIIIIi...
...IIIIIIIIIIi..
..IIIIIIIIIIIi..
..IIIIIIIIIIIii.
..ZZZZZZZZZZZZz.
..Ii.........I..
...i.........i..
""")
HELMET_BACK = art("""
C................C
CC..............CC
cCC....IIII....CCc
.cCC.IIIIIIII.CCc.
..cCIIIIIIIIIIiCc.
...IIIIIIIIIIIIii.
..IIIIIIIIIIIIIiii
..IIIIIIIIIIIIiiii
..ZZZZZZZZZZZZZZzz
..IIIIIIIIIIIIIIii
..iIIIIIIIIIIIIii.
...iiiiiiiiiiiii..
""")
# El casco tirado en el piso.
HELMET_PILE = art("""
C..............C
cC...IIIIII...Cc
.cCIIIIIIIIIICc.
..ZZZZZZZZZZZZz.
""")
PAULDRON = art("""
.IIII.
IIIIIi
IiIiii
.iiii.
""")
TABARD = art("""
GAAAAG
GAAaAG
GAAaAG
GAaAAG
.GAAG.
..GG..
""")
BELT = art("""
LLLLGGLLLL
LLLLGgLLLL
""")
SHIELD = art("""
....iiii....
..iiZZZZii..
.iZZZZZZZZi.
.iZZZZZZZZzi
iZZZZIIZZZzi
iZZZIISiZZzi
iZZZIIiiZZzi
iZZZZiiZZzzi
.iZZZZZZZzi.
.izZZZZZzzi.
..iizzzzii..
....iiii....
""")
SHIELD_BACK = art("""
....iiii....
..iizzzzii..
.izzzzzzzzi.
.izLLLLLLzzi
izzzzzzzzzzi
izzLLLLLLzzi
izzzzzzzzzzi
izzzzzzzzzzi
.izzzzzzzzi.
.izzzzzzzzi.
..iizzzzii..
....iiii....
""")
SHIELD_FLAT = art("""
...iiiiiii...
.iZZZZIIZZZi.
iZZZZZZZZZZzi
.iiiizzziiii.
""")
# Hacha: cabeza de hierro con el filo claro, mango de madera. GRIP = dónde
# la agarra la mano.
AXE_U = art("""
.SSS..
SSIIi.
SSIIOi
SSIIi.
.SSS..
...O..
...O..
...O..
...O..
...O..
...o..
...o..
...O..
...G..
""")
AXES = {
    "u": (AXE_U, (3, 10)),
    "ul": (art("""
..SS........
.SSII.......
SSIIIi......
.SIIOOi.....
..iiiO......
......O.....
.......O....
........O...
.........o..
..........o.
...........G
"""), (9, 8)),
    "l": (rot90(rot90(rot90(AXE_U))), rot_point(rot_point(rot_point((3, 10), AXE_U), rot90(AXE_U)),
                                                rot90(rot90(AXE_U)))),
}


def axe(s, out, hand, name):
    a, (gx, gy) = oriented(AXES, name)
    hx, hy = s.at(hand)
    out.append(Piece().stamp(a, hx - gx, hy - gy))
    out.append(Piece().stamp(sk.HAND, hx - 1, hy - 1))


def sparks(s, out, center, big=True):
    """Chispas del golpe contra el escudo (o del hacha contra el piso)."""
    cx, cy = s.at(center)
    p = Piece("x", "flat")
    pts = [(-5, -3), (-4, -2), (-3, -1), (5, -3), (4, -2), (3, -1), (0, -6), (0, -5), (-6, 1), (6, 1)]
    if not big:
        pts = pts[1:3] + pts[4:6] + [pts[7]]
    for dx, dy in pts:
        p.dot(cx + dx, cy + dy, "X")
    out.append(p)


class Guardian(sk.Gear):
    def chest(self, s, P, out):
        x, y = s.at(P["ribs"])
        for dx in (-3, 7):
            out.append(Piece(shape="dome").stamp(PAULDRON, x + dx, y - 2))

    def waist(self, s, P, out):
        x, y = s.at(P["pelvis"])
        out.append(Piece(shape="cyl").stamp(BELT, x, y - 1))
        out.append(Piece().stamp(TABARD, x + 2, y + 1))

    def left(self, s, P, out):
        out.append(Piece().stamp(sk.HAND, *move(s.at(P["arm_l"][2]), -1, -1)))
        out.append(Piece(shape="disc").stamp(SHIELD, *s.at(P["shield"])))

    def right(self, s, P, out):
        axe(s, out, P["arm_r"][2], P["axe"])

    def head(self, s, P, out):
        if P.get("helmet", "on") == "on":
            x, y = s.at(P["skull"])
            dy = -1 if P.get("form", 0) > 0 else (1 if P.get("form", 0) < 0 else 0)
            out.append(Piece(shape="dome").stamp(HELMET, x - 2, y - 5 + dy))
        elif P.get("helmet") == "flying":
            x, y = s.at(P["helmet_at"])
            out.append(Piece(shape="dome").stamp(HELMET, x, y))

    def fx(self, s, P, out):
        if P.get("smear"):
            out.append(smear_piece(s.cv, P["smear"]))
        if P.get("fx") in ("sparks", "sparks_small"):
            x, y = P["shield"]
            sparks(s, out, (x + 5, y + 5), P["fx"] == "sparks")
        if P.get("fx") in ("ground", "ground_small"):
            sparks(s, out, P["fx_at"], P["fx"] == "ground")

    def side_chest(self, s, P, out):
        x, y = s.at(P["ribs"])
        out.append(Piece(shape="dome").stamp(PAULDRON, x, y - 2))
        px, py = s.at(P["pelvis"])
        out.append(Piece().stamp(TABARD[:5], px + 1, py + 1))

    def side_head(self, s, P, out):
        x, y = s.at(P["skull"])
        out.append(Piece(shape="dome").stamp(HELMET_SIDE, x - 1, y - 4))

    def side_near(self, s, P, out):
        axe(s, out, P["arm_n"][2], P["axe"])

    def back_first(self, s, P, out):
        x, y = P["arm_r"][2]
        axe(s, out, (-x, y), MIRROR[P["axe"]])
        out.append(Piece(shape="disc").stamp(SHIELD_BACK, *s.mirror_x("shield", P, 12)))

    def back_head(self, s, P, out):
        bx, by = s.mirror_x("skull", P, 14)
        out.append(Piece(shape="dome").stamp(HELMET_BACK, bx - 2, by - 5))

    def back_last(self, s, P, out):
        x, y = s.mirror_x("ribs", P, 10)
        for dx in (-3, 7):
            out.append(Piece(shape="dome").stamp(PAULDRON, x + dx, y - 2))

    def pile_under(self, s, P, out):
        a, _ = oriented(AXES, "l")
        out.append(Piece().stamp(a, *s.at(P["axe_at"])))

    def pile_items(self, s, P, out):
        out.append(Piece(shape="disc").stamp(SHIELD_FLAT, *s.at(P["shield"])))
        out.append(Piece(shape="dome").stamp(HELMET_PILE, *s.at(P["helmet_pile"])))


SK = sk.Skeleton(Guardian())

# --- Poses -----------------------------------------------------------------------------

FRONT = pose(sk.FRONT, shield=(6, -19), axe="u", arm_r=[(-7, -19), (-9, -15), (-11, -12)])
SIDE = pose(sk.SIDE, axe="u", arm_n=[(-1, -19), (-1, -15), (3, -13)])
BACK = pose(FRONT, view="n")
GUARD = bob(pose(FRONT, foot_r=(-10, -2), foot_l=(6, -2), leg_r=[(-3, -9), (-7, -6), (-7, -3)],
                 leg_l=[(2, -9), (6, -6), (6, -3)], arm_r=[(-7, -19), (-11, -18), (-12, -21)], axe="ul",
                 arm_l=[(6, -19), (6, -15), (5, -12)], shield=(2, -20)), 1)
HURT = jaw_open(pose(arm(shift(lunge(GUARD, 1, 0), 1, -2, ("skull",)), "arm_r", (-5, 0), (-7, -4)), form=1), 2)
PILE = {
    "pile": 1, "view": "s", "eyes": 0,
    "skull": (-5, -17), "jaw": (6, -5), "helmet_pile": (-21, -6),
    "ribs": (-11, -10), "pelvis": (-4, -5), "shield": (3, -5), "axe_at": (7, -4),
    "bones": [((-13, -2), (-4, -3)), ((-6, -2), (3, -1)), ((2, -3), (11, -2)), ((-9, -5), (-1, -2)),
              ((5, -6), (13, -4))],
    "smear": None, "fx": None,
}


def combat(i):
    """En guardia: detrás del escudo, el hacha en alto."""
    G = GUARD
    seq = [G, G, bob(G, 1), bob(arm(G, "arm_r", (-4, 1), (-5, -3)), 1, head=1), jaw_open(bob(G, 0, head=1), 1), G]
    return pose(seq[i], tail=i)


def chop():
    """Hachazo de arriba: se agacha, levanta el hacha con las dos manos por
    encima de la cabeza, la baja con todo y saltan chispas del piso."""
    G = GUARD
    up = pose(arm(shift(bob(G, -1), 0, -1, HEAD), "arm_r", (-2, -6), (1, -12)), axe="u", form=1, shield=(4, -19))
    s4 = pose(arm(lunge(G, 1, 1), "arm_r", (5, -4), (11, -6)), axe="r", weapon_front=True)
    s5 = pose(arm(lunge(G, 1, 3), "arm_r", (5, 2), (9, 8)), axe="d", weapon_front=True, form=-1)
    return [
        pose(arm(bob(G, 2), "arm_r", (-4, 2), (-6, 5)), axe="dl", form=-1),
        jaw_open(up, 1),
        jaw_open(pose(up, tail=2), 2),
        jaw_open(pose(s4, smear=crescent(s4["arm_r"][0], 20, 110, 20, 3)), 2),
        jaw_open(pose(s5, smear=crescent(s5["arm_r"][0], 20, 45, -60, 4), fx="ground",
                      fx_at=move(s5["arm_r"][0], 10, 15)), 2),
        jaw_open(pose(s5, fx="ground_small", fx_at=move(s5["arm_r"][0], 10, 15)), 1),
        pose(arm(bob(G, 2), "arm_r", (4, 2), (6, 6)), axe="dr"),
        pose(arm(bob(G, 1), "arm_r", (-3, 2), (-5, 4)), axe="ul"),
        G,
    ]


def bash():
    """Escudazo: se echa atrás y embiste con el escudo."""
    G = GUARD
    back = pose(arm(shift(G, -1, -1, HEAD), "arm_l", (4, 2), (6, 5)), shield=(7, -20))
    hit_ = pose(arm(lunge(G, -1, 2), "arm_l", (-3, 2), (-6, 5)), shield=(-6, -19), form=-1)
    return [
        back,
        jaw_open(pose(back, form=1), 1),
        pose(arm(lunge(G, -1, 1), "arm_l", (-2, 2), (-4, 5)), shield=(-2, -19)),
        jaw_open(pose(hit_, fx="sparks"), 2),
        jaw_open(pose(hit_, fx="sparks_small", form=0), 1),
        pose(arm(bob(G, 1), "arm_l", (0, 3), (-1, 6)), shield=(0, -19)),
        pose(G, shield=(1, -20)),
        G,
    ]


def block():
    """Recibe el golpe en el escudo: chispas, retrocede un paso."""
    G = GUARD
    return [jaw_open(pose(lunge(G, 1, 0), fx="sparks"), 1), pose(lunge(G, 1, 0), fx="sparks_small"),
            lunge(G, -1, 0), G]


def helmet_pop():
    """El golpe le vuela el casco; se lo vuelve a encajar de un manotazo."""
    G = GUARD
    sx, sy = G["skull"]
    return [jaw_open(pose(HURT, helmet="flying", helmet_at=(sx - 1, sy - 9)), 2),
            jaw_open(pose(G, helmet="flying", helmet_at=(sx, sy - 13)), 1),
            jaw_open(pose(G, helmet="flying", helmet_at=(sx - 2, sy - 9), form=1), 2),
            pose(arm(G, "arm_r", (0, -8), (5, -14)), helmet="flying", helmet_at=(sx - 2, sy - 7), weapon_front=True),
            pose(G, form=-1),
            G]


CRUMBLE = sk.crumble_poses(GUARD, {"axe": "dl", "shield": (4, -16)}, {"axe": "l", "shield": (4, -13)},
                           {"axe": "l", "shield": (4, -11)})
RISE = jaw_open(pose(arm(arm(bob(GUARD, -1), "arm_r", (-3, -6), (-2, -12)), "arm_l", (4, -3), (6, -6)),
                     axe="u", shield=(6, -22), form=1), 2)

ANIMS = {
    "idle": (True, 1.6, {"s": [sk.idle(FRONT, i) for i in range(8)], "e": [sk.idle(SIDE, i) for i in range(8)],
                         "n": [sk.idle(BACK, i) for i in range(8)]}),
    "walk": (True, 0.9, {"s": [sk.walk_front(FRONT, i) for i in range(6)],
                         "e": [sk.walk_side(SIDE, i) for i in range(6)],
                         "n": [sk.walk_front(BACK, i) for i in range(6)]}),
    "combat": (True, 1.3, {"s": [combat(i) for i in range(6)]}),
    "attack": (False, 1.0, {"s": chop()}),
    "attack_2": (False, 0.9, {"s": bash()}),
    "hit": (False, 0.45, {"s": block()}),
    "hit_2": (False, 0.7, {"s": helmet_pop()}),
    "death": (False, 1.5, {"s": sk.death(HURT, CRUMBLE, PILE)}),
    "spawn": (False, 1.6, {"s": sk.spawn(CRUMBLE, PILE, RISE, GUARD)}),
    "dormant": (True, 1.0, {"s": [PILE]}),
}
SPECIES = "esqueleto_guardian"
PPM = 24
SELF_LIGHT = 0.3


def main(args):
    opt = {a.split("=", 1)[0]: a.split("=", 1)[1] for a in args if "=" in a}
    write_sheet(SPECIES, ANIMS, SK.frame, SK.cv, PPM, SELF_LIGHT, opt.get("--preview"))
    if "--gif" in opt:
        plan = reel(ANIMS, [("idle", 2), ("combat", 2), "attack", "combat", "attack_2", "combat", "hit", "hit_2",
                            "combat", "death", ("dormant", 3), "spawn", "combat"])
        lit_gif(opt["--gif"], plan, SK.frame, eye=(1.0, 0.48, 0.16))


if __name__ == "__main__":
    main(sys.argv[1:])
