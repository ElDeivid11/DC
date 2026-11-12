"""Esqueleto esbirro en pixel art grueso (bufanda roja, espada corta y escudo).

    python3 -I tools/sprites/draw_esbirro.py [--preview=/tmp/hoja.png] [--gif=/tmp/anim.gif]

Escribe assets/sprites/enemies/esqueleto_esbirro.png, _glow.png, _normal.png y
.json (formato en tools/sprites/README.md). El cuerpo sale de skeleton.py; acá
va lo suyo: la bufanda, la espada, el escudo, el tajo y el escudazo.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import skeleton as sk  # noqa: E402
from pixel_kit import (HEAD, MIRROR, Piece, arm, art, bob, crescent, flip_x, jaw_open, lit_gif, lunge,  # noqa: E402
                       move, oriented, pose, reel, shift, smear_piece, write_sheet)

# --- Sellos ----------------------------------------------------------------------------

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
# Puntas de la bufanda al viento (salen del lado izquierdo del cuello): tres
# dibujos que se pasan en ida y vuelta.
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
SCARF_PILE = art("""
..RRRRR...
.RRrRRRRR.
RRr..rRRRR
.r.....rR.
""")


def tail_art(i):
    """Las puntas de la bufanda: tres dibujos en ida y vuelta (A B C B)."""
    return TAILS[(0, 1, 2, 1)[i % 4]]


def sword(s, out, hand, name):
    a, (gx, gy) = oriented(SWORDS, name)
    hx, hy = s.at(hand)
    out.append(Piece().stamp(a, hx - gx, hy - gy))
    out.append(Piece().stamp(sk.HAND, hx - 1, hy - 1))


class Esbirro(sk.Gear):
    def behind(self, s, P, out):
        out.append(Piece().stamp(tail_art(P["tail"]), *s.at(P["tails"])))

    def chest(self, s, P, out):
        out.append(Piece(shape="cyl").stamp(WRAP, *s.at(P["wrap"])))

    def left(self, s, P, out):
        out.append(Piece().stamp(sk.HAND, *move(s.at(P["arm_l"][2]), -1, -1)))
        out.append(Piece(shape="disc").stamp(SHIELD, *s.at(P["shield"])))

    def right(self, s, P, out):
        sword(s, out, P["arm_r"][2], P["sword"])

    def fx(self, s, P, out):
        if P.get("smear"):
            out.append(smear_piece(s.cv, P["smear"]))
        if P.get("fx") in ("star", "star_small"):
            # golpe de escudo: un destello delante del escudo
            x0, y0 = s.at(P["shield"])
            p = Piece("x", "flat")
            cx, cy = x0 + 4, y0 + 5
            big = P["fx"] == "star"
            for d in range(-6 if big else -4, 7 if big else 5):
                if abs(d) > (1 if big else 2):
                    p.dot(cx + d, cy, "X").dot(cx, cy + d, "X")
            for d in ((-4, -3, 3, 4) if big else (-3, 3)):
                p.dot(cx + d, cy + d, "X").dot(cx + d, cy - d, "X")
            out.append(p)

    def side_behind(self, s, P, out):
        out.append(Piece().stamp(tail_art(P["tail"]), *s.at(P["tails"])))

    def side_chest(self, s, P, out):
        out.append(Piece(shape="cyl").stamp(WRAP_SIDE, *s.at(P["wrap"])))

    def side_near(self, s, P, out):
        sword(s, out, P["arm_n"][2], P["sword"])

    def back_first(self, s, P, out):
        x, y = P["arm_r"][2]
        sword(s, out, (-x, y), MIRROR[P["sword"]])
        out.append(Piece(shape="disc").stamp(SHIELD_BACK, *s.mirror_x("shield", P, 9)))

    def back_last(self, s, P, out):
        out.append(Piece(shape="cyl").stamp(flip_x(WRAP), *s.mirror_x("wrap", P, 12)))
        out.append(Piece().stamp(flip_x(tail_art(P["tail"])), *s.mirror_x("tails", P, 14)))

    def pile_under(self, s, P, out):
        # la espada caída en diagonal: la punta (abajo a la izquierda del sello)
        # en P["sword_at"]
        a, _ = oriented(SWORDS, "dl")
        tx, ty = s.at(P["sword_at"])
        out.append(Piece().stamp(a, tx, ty - len(a) + 1))

    def pile_items(self, s, P, out):
        out.append(Piece(shape="disc").stamp(SHIELD_FLAT, *s.at(P["shield"])))
        out.append(Piece().stamp(SCARF_PILE, *s.at(P["scarf"])))


SK = sk.Skeleton(Esbirro())

# --- Poses -----------------------------------------------------------------------------

FRONT = pose(sk.FRONT, wrap=(-6, -23), tails=(-19, -25), shield=(7, -18), sword="ul")
SIDE = pose(sk.SIDE, wrap=(-4, -23), tails=(-16, -25), sword="ur")
BACK = pose(FRONT, view="n")
PILE = {
    "pile": 1, "view": "s", "eyes": 0,
    "skull": (-5, -17), "jaw": (6, -5),
    "ribs": (-11, -10), "pelvis": (-4, -5), "shield": (4, -5), "sword_at": (-19, 1),
    "scarf": (-10, -7),
    "bones": [((-13, -2), (-4, -3)), ((-6, -2), (3, -1)), ((2, -3), (11, -2)), ((-9, -5), (-1, -2)),
              ((5, -6), (13, -4))],
    "smear": None, "fx": None,
}
GUARD = bob(pose(FRONT, foot_r=(-10, -2), foot_l=(6, -2), leg_r=[(-3, -9), (-7, -6), (-7, -3)],
                 leg_l=[(2, -9), (6, -6), (6, -3)], arm_r=[(-7, -19), (-11, -17), (-12, -20)],
                 arm_l=[(6, -19), (7, -15), (7, -12)], shield=(5, -19)), 1)
HURT = jaw_open(pose(arm(shift(lunge(GUARD, 1, 0), 1, -2, ("skull",)), "arm_r", (-5, 0), (-7, -4)), form=1, tail=2), 2)


def combat(i):
    """En guardia: más agachado, la espada tiembla arriba."""
    G = GUARD
    seq = [G, arm(G, "arm_r", (-4, 2), (-5, -2)), bob(G, 1), bob(arm(G, "arm_r", (-4, 2), (-5, -2)), 1, head=1),
           jaw_open(bob(G, 0, head=1), 1), G]
    return pose(seq[i], tail=i)


def _swing(P, a0, a1, w, r=19):
    """Estela del tajo alrededor del hombro de la espada."""
    return crescent(P["arm_r"][0], r, a0, a1, w)


def attack():
    G = GUARD
    f = []
    # 0 anticipación: se agacha, se aplasta y lleva la espada atrás y abajo
    f.append(pose(arm(bob(G, 2), "arm_r", (-4, 3), (-7, 6)), sword="dl", form=-1))
    # 1-2 levanta la espada por encima de la cabeza, se estira, abre la boca
    up = pose(arm(shift(bob(G, -1), -1, 0, HEAD), "arm_r", (-4, -5), (-3, -11)), sword="u", form=1)
    f.append(jaw_open(up, 1))
    f.append(jaw_open(pose(up, tail=2), 2))
    # 3-6 el tajo: la espada baja cruzando el cuerpo con su estela
    s3 = pose(arm(G, "arm_r", (1, -6), (6, -9)), sword="ur", weapon_front=True)
    f.append(jaw_open(pose(s3, smear=_swing(s3, 125, 70, 2)), 1))
    s4 = pose(arm(shift(bob(G, 1), 1, 0, HEAD), "arm_r", (4, -3), (10, -3)), sword="r", weapon_front=True)
    f.append(jaw_open(pose(s4, smear=_swing(s4, 125, 15, 3)), 2))
    s5 = pose(arm(lunge(G, 1, 2), "arm_r", (5, 2), (11, 6)), sword="dr", weapon_front=True, form=-1)
    f.append(jaw_open(pose(s5, smear=_swing(s5, 60, -50, 4)), 2))
    s6 = pose(arm(lunge(G, 1, 2), "arm_r", (5, 3), (9, 8)), sword="dr", weapon_front=True)
    f.append(jaw_open(pose(s6, smear=_swing(s6, 0, -60, 2)), 1))
    # 7-8 vuelve a la guardia
    f.append(pose(arm(bob(G, 1), "arm_r", (-2, 3), (-4, 5)), sword="ul"))
    f.append(G)
    return f


def bash():
    """Escudazo: se echa atrás, embiste con el escudo y saca un destello."""
    G = GUARD
    back = pose(arm(shift(G, -1, -1, HEAD), "arm_l", (4, 2), (6, 5)), shield=(9, -19))
    return [
        back,
        jaw_open(pose(back, form=1, tail=1), 1),
        pose(arm(lunge(G, -1, 1), "arm_l", (-2, 2), (-4, 5)), shield=(1, -18), tail=2),
        jaw_open(pose(arm(lunge(G, -1, 2), "arm_l", (-3, 2), (-6, 5)), shield=(-4, -18), form=-1, fx="star"), 2),
        jaw_open(pose(arm(lunge(G, -1, 2), "arm_l", (-3, 2), (-6, 5)), shield=(-4, -18), fx="star_small"), 1),
        pose(arm(bob(G, 1), "arm_l", (0, 3), (-1, 6)), shield=(1, -18)),
        pose(G, shield=(4, -19)),
        G,
    ]


CRUMBLE = sk.crumble_poses(GUARD, {"sword": "dl", "shield": (6, -16)}, {"sword": "l", "shield": (6, -13)},
                           {"sword": "l", "shield": (6, -11)})
RISE = jaw_open(pose(arm(arm(bob(GUARD, -1), "arm_r", (-4, -5), (-5, -10)), "arm_l", (4, -3), (6, -6)),
                     sword="u", shield=(8, -22), form=1, tail=2), 2)

# nombre -> (se repite, duración en s, {dirección: lista de poses})
ANIMS = {
    "idle": (True, 1.6, {"s": [sk.idle(FRONT, i) for i in range(8)], "e": [sk.idle(SIDE, i) for i in range(8)],
                         "n": [sk.idle(BACK, i) for i in range(8)]}),
    "walk": (True, 0.8, {"s": [sk.walk_front(FRONT, i) for i in range(6)],
                         "e": [sk.walk_side(SIDE, i) for i in range(6)],
                         "n": [sk.walk_front(BACK, i) for i in range(6)]}),
    "combat": (True, 1.2, {"s": [combat(i) for i in range(6)]}),
    "attack": (False, 0.9, {"s": attack()}),
    "attack_2": (False, 0.9, {"s": bash()}),
    "hit": (False, 0.45, {"s": sk.hit(GUARD, HURT)}),
    "hit_2": (False, 0.6, {"s": sk.hit_skull(GUARD)}),
    "death": (False, 1.5, {"s": sk.death(HURT, CRUMBLE, PILE)}),
    "spawn": (False, 1.6, {"s": sk.spawn(CRUMBLE, PILE, RISE, GUARD)}),
    "dormant": (True, 1.0, {"s": [PILE]}),
}
SPECIES = "esqueleto_esbirro"
# Unos 38 px para 1,6 m: cada píxel del sprite mide ~4 cm en el mundo, el
# triple que un texel del entorno (64 px/m). Ese salto es el contraste.
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
