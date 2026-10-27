"""Cofre en pixel art grueso (mismo kit y escala que los enemigos: 24 px/m),
para que resalte contra el pasillo 3D y llame la atención: madera con
flejes de hierro, cantoneras y cerradura de oro, y destellos que brillan con
la luz dorada del cofre (máscara de brillo, como los ojos de los enemigos).

Papeles (los toca EnemySprite, como a un enemigo):
  idle    cerrado; un destello recorre las cantoneras y la cerradura
  open    se sacude, la tapa se levanta y sale un golpe de luz dorada
  opened  abierto, con monedas que titilan adentro

    python3 -I tools/sprites/draw_cofre.py [--preview=/tmp/cofre.png] [--gif=/tmp/cofre.gif]

Escribe assets/sprites/props/cofre.* (formato en tools/sprites/README.md).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pixel_kit as pk  # noqa: E402
from pixel_kit import Canvas, Piece, art, lit_gif, write_sheet  # noqa: E402

W = 24            # ancho del cofre (px)
BODY_H = 10       # caja
LID_H = 7         # tapa cerrada (curva)
STRAPS = (3, 19)  # columnas de los flejes de hierro (2 px cada uno)
CANVAS = Canvas(44, 52, 22, 46)

# Destello de 4 puntas (y uno chico) con el color de brillo.
STAR = art("""
.E.
EEE
.E.
""")
STAR_BIG = art("""
..E..
..E..
EEEEE
..E..
..E..
""")


def _x0():
    return CANVAS.cx - W // 2


def body(dx=0, open_=False):
    """La caja: tablas (O con juntas o), flejes de hierro, cantoneras y la
    cerradura de oro. Abierta, la cerradura queda colgando (sin la tapa)."""
    p = Piece(shape="bevel")
    x0, top = _x0() + dx, CANVAS.ground - BODY_H
    for y in range(BODY_H):
        for x in range(W):
            ch = "o" if y % 3 == 2 else "O"
            if x in (STRAPS[0], STRAPS[1]):
                ch = "I"
            elif x in (STRAPS[0] + 1, STRAPS[1] + 1):
                ch = "i"
            if x == W - 1 or y == BODY_H - 1:
                ch = "o" if ch == "O" else ch
            p.dot(x0 + x, top + y, ch)
    # Cantoneras de oro en las cuatro esquinas.
    for (cx, cy) in ((0, 0), (W - 2, 0), (0, BODY_H - 2), (W - 2, BODY_H - 2)):
        p.stamp(["GG", "Gg"], x0 + cx, top + cy)
    # Cerradura: placa de oro con el ojo de la llave.
    lock = ["GGGG", "GKKg", "GgKg", "gggg"] if not open_ else ["GGGG", "GKKg", "gggg"]
    p.stamp(lock, x0 + W // 2 - 2, top + (0 if not open_ else 1))
    return p


def lid_closed(dx=0, lift=0):
    """Tapa curva (cerrada), con los flejes y el borde de oro. lift = cuánto
    se levantó (la rendija de luz la dibuja glow_gap)."""
    p = Piece(shape="cyl")
    x0 = _x0() + dx
    bottom = CANVAS.ground - BODY_H - 1 - lift
    insets = [5, 2, 1, 0, 0, 0, 0]
    for r in range(LID_H):
        y = bottom - (LID_H - 1 - r)
        ins = insets[r]
        for x in range(ins, W - ins):
            ch = "O"
            if r == 1 or r == 4:
                ch = "o"
            if x in (STRAPS[0], STRAPS[1]):
                ch = "I"
            elif x in (STRAPS[0] + 1, STRAPS[1] + 1):
                ch = "i"
            if r == LID_H - 1:
                ch = "G" if x < W - 2 else "g"
            p.dot(x0 + x, y, ch)
    # Broche de la tapa sobre la cerradura.
    p.stamp(["GG", "gg"], x0 + W // 2 - 1, bottom)
    return p


def lid_open(dx=0, half=False):
    """Tapa abierta: se ve el lado de adentro, parada detrás de la caja (o a
    medio abrir, más baja e inclinada)."""
    p = Piece(shape="bevel")
    x0 = _x0() + dx
    h = 5 if half else 9
    base = CANVAS.ground - BODY_H - 1
    for r in range(h):
        y = base - h + r
        ins = 1 if r < 2 else 0
        if half:
            ins = 2 - min(r, 2)
        for x in range(ins, W - ins):
            ch = "n" if r % 3 == 1 else "L"
            if x in (STRAPS[0], STRAPS[1]):
                ch = "i"
            if r == 0:
                ch = "G" if x < W - 3 else "g"
            p.dot(x0 + x, y, ch)
    return p


def interior(dx=0, phase=0):
    """Adentro de la caja abierta: hueco oscuro con un montón de monedas."""
    p = Piece(outline=None, shape="flat")
    x0, top = _x0() + dx, CANVAS.ground - BODY_H
    for x in range(1, W - 1):
        p.dot(x0 + x, top - 1, "k")
    heap = art("""
.....gGGg..gGg......
..gGGGgGGGGGgGGg.gg.
.GGgGGGGGgGGGGGGGGg.
""")
    p.stamp(heap, x0 + 2, top - 3)
    # Monedas que titilan (cambian de lugar según la fase).
    for i, (cx, cy) in enumerate(((7, -2), (13, -3), (17, -2), (10, -1))):
        if (i + phase) % 2 == 0:
            p.dot(x0 + cx, top + cy, "E")
    return p


def glow_gap(dx=0, lift=2):
    """Rendija de luz entre la caja y la tapa que se levanta."""
    p = Piece(outline=None, shape="flat")
    x0, y = _x0() + dx, CANVAS.ground - BODY_H - 1
    for k in range(lift):
        for x in range(2, W - 2):
            p.dot(x0 + x, y - k, "E")
    return p


def rays(dx=0, size=2):
    """Golpe de luz dorada que sale del cofre al abrirse: cinco haces en
    abanico (el del medio, el más largo); size 0..2 = cuánto se estiran."""
    p = Piece(outline=None, shape="flat")
    cx = CANVAS.cx + dx
    top = CANVAS.ground - BODY_H - 2
    lengths = [[2, 4, 6, 4, 2], [4, 7, 10, 7, 4], [6, 11, 15, 11, 6]][size]
    for off, length in zip((-8, -4, 0, 4, 8), lengths):
        for k in range(length):
            x = cx + off + (off // 4) * k // 4
            # Los haces de afuera, punteados (se deshacen hacia arriba).
            if abs(off) == 8 and k % 2 == 1:
                continue
            p.dot(x, top - k, "E")
    return p


def star(at, big=False):
    p = Piece(outline=None, shape="flat")
    a = STAR_BIG if big else STAR
    p.stamp(a, at[0] - len(a[0]) // 2, at[1] - len(a) // 2)
    return p


# --- Poses --------------------------------------------------------------------------------
# Una pose es la lista de piezas de ese cuadro (de atrás hacia adelante).

def closed(dx=0, sparkle=None):
    pieces = [body(dx), lid_closed(dx)]
    if sparkle:
        pieces.append(star(sparkle[0], sparkle[1]))
    return pieces


def _corner(i):
    """Puntos donde aparece el destello del reposo: cantoneras y cerradura."""
    x0, top = _x0(), CANVAS.ground - BODY_H
    return [(x0 + 1, top - LID_H + 1), (x0 + W // 2, top + 2), (x0 + W - 2, top + BODY_H - 2), (x0 + W - 3, top - LID_H + 2)][i]


IDLE = []
for i in range(2):
    # Por cada punto: chico, grande, chico, y una pausa sin destello.
    p1, p2 = _corner(i * 2), _corner(i * 2 + 1)
    IDLE += [closed(), closed(sparkle=(p1, False)), closed(sparkle=(p1, True)), closed(sparkle=(p1, False)),
             closed(), closed(sparkle=(p2, False)), closed(sparkle=(p2, True)), closed()]

OPEN = [
    closed(-1),
    closed(1),
    [body(), glow_gap(lift=2), lid_closed(lift=2)],
    [lid_open(half=True), interior(), body(open_=True), rays(size=0)],
    [lid_open(), interior(), body(open_=True), rays(size=2)],
    [lid_open(), interior(phase=1), body(open_=True), rays(size=1)],
    [lid_open(), interior(), body(open_=True), rays(size=0)],
]

OPENED = [
    [lid_open(), interior(phase=0), body(open_=True)],
    [lid_open(), interior(phase=1), body(open_=True)],
]

ANIMS = {
    "idle": (True, 2.4, {"s": IDLE}),
    "open": (False, 0.75, {"s": OPEN}),
    "opened": (True, 1.2, {"s": OPENED}),
}


def frame(P):
    grid, normals = CANVAS.render(P)
    return CANVAS.to_rgba(grid, normals)


def main():
    preview = gif = None
    for a in sys.argv[1:]:
        if a.startswith("--preview="):
            preview = a.split("=", 1)[1]
        elif a.startswith("--gif="):
            gif = a.split("=", 1)[1]
    pk.OUT_DIR = pk.ROOT / "assets" / "sprites" / "props"
    write_sheet("cofre", ANIMS, frame, CANVAS, 24, 0.35, preview)
    if gif:
        plan = [(P, 2.4 / len(IDLE)) for P in IDLE] + [(P, 0.75 / len(OPEN)) for P in OPEN] + [(P, 0.6) for P in OPENED * 2]
        lit_gif(gif, plan, frame, eye=(1.0, 0.82, 0.4))


if __name__ == "__main__":
    main()
