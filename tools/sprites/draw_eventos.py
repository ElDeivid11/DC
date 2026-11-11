"""Eventos de sala en pixel art grueso (mismo kit y escala que los enemigos y
el cofre: 24 px/m): lo que se encuentra explorando y se usa chocándolo.

  fuente     pila de piedra con una calavera que escupe agua que brilla
             (idle: el agua corre; used: seca)
  santuario  ídolo cornudo sobre un altar con dos velas y sangre
             (idle: velas y ojos encendidos; used: apagado)
  mercader   encapuchado con un morral enorme y un farol en una vara
  forja      yunque sobre un bloque de piedra con una llama de alma encima

Lo que brilla (agua, llamas, ojos, farol) va en la máscara de brillo y toma
el color que le pasa el juego (FloorBuilder.spawn_event).

También escribe assets/textures/props/trampa.png: la losa de la trampa de
pinchos (32x32, con los agujeros por donde salen).

    python3 -I tools/sprites/draw_eventos.py [--preview=/tmp/eventos]
"""
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pixel_kit as pk  # noqa: E402
from pixel_kit import Canvas, Piece, art, write_sheet  # noqa: E402

CANVAS = Canvas(48, 60, 24, 54)
CX, GY = CANVAS.cx, CANVAS.ground


def block(p, x0, y0, w, h, ch, shade=None, top=None):
    """Rectángulo relativo al piso (x0 desde el centro, y0 = fila de arriba,
    negativo = sobre el piso). shade: color de la última columna y fila;
    top: color de la primera fila."""
    for j in range(h):
        for i in range(w):
            c = ch
            if shade and (i == w - 1 or j == h - 1):
                c = shade
            if top and j == 0:
                c = top
            p.dot(CX + x0 + i, GY + y0 + j, c)
    return p


def rel(p, a, x, y):
    p.stamp(a, CX + x, GY + y)
    return p


# --- Fuente --------------------------------------------------------------------------------

SKULL_SPOUT = art("""
.CCCCCC.
CCCCCCCC
CKKCCKKC
CKKCCKKC
CCCKKCCC
.CcKKcC.
.cKKKKc.
""")


def fuente(phase=0, dry=False):
    back = block(Piece(shape="bevel"), -5, -34, 10, 22, "I", "i")
    rel(back, SKULL_SPOUT, -4, -31)
    # musgo en la piedra
    for (x, y) in ((-5, -18), (-4, -17), (4, -22), (3, -15)):
        back.dot(CX + x, GY + y, "M")
    bowl = Piece(shape="cyl")
    widths = [28, 28, 26, 24, 20, 14]
    for j, w in enumerate(widths):
        for i in range(w):
            ch = "I" if j < 2 else ("i" if (i > w - 4 or j == len(widths) - 1) else "I")
            bowl.dot(CX - w // 2 + i, GY - 14 + j, ch)
    stem = block(Piece(shape="cyl"), -4, -8, 8, 5, "I", "i")
    base = Piece(shape="bevel")
    block(base, -8, -3, 16, 1, "I", "i")
    block(base, -10, -2, 20, 2, "I", "i")
    water = Piece(outline=None, shape="flat")
    for i in range(24):
        x = CX - 12 + i
        if dry:
            water.dot(x, GY - 14, "i")
        else:
            water.dot(x, GY - 14, "E" if (i + phase) % 4 < 2 else "F")
    pieces = [back, stem, base, bowl, water]
    if not dry:
        jet = Piece(outline=None, shape="flat")
        for k in range(10):
            if (k + phase) % 3 != 2:
                jet.dot(CX - 1, GY - 24 + k, "E")
                jet.dot(CX, GY - 24 + k, "E" if (k + phase) % 2 == 0 else "F")
        # salpicadura
        for (dx, dy) in (((-3, -15), (2, -16)), ((-4, -16), (3, -15)), ((-2, -16), (4, -16)), ((-3, -16), (2, -15)))[phase % 4]:
            jet.dot(CX + dx, GY + dy, "E")
        pieces.append(jet)
    return pieces


# --- Santuario -----------------------------------------------------------------------------

IDOL = art("""
c..........c
Cc........cC
CC.CCCCCC.CC
.CCCCCCCCCC.
..CCCCCCCC..
..CEECCEEC..
..CEECCEEC..
..CCCKKCCC..
...CcKKcC...
...cKcKcc...
....cccc....
""")


def santuario(phase=0, lit=True):
    idol_art = IDOL if lit else pk.recolor(IDOL, {"E": "K"})
    altar = Piece(shape="bevel")
    block(altar, -13, -6, 26, 6, "I", "i", "S")
    block(altar, -10, -12, 20, 6, "I", "i", "S")
    # runas y sangre que chorrea por el frente
    for (x, y) in ((-7, -9), (-6, -8), (-7, -7), (5, -9), (6, -8), (5, -7)):
        altar.dot(CX + x, GY + y, "s")
    for (x, y, ch) in ((-1, -12, "R"), (0, -12, "R"), (1, -12, "r"), (0, -11, "R"), (0, -10, "r"), (0, -9, "r"), (-1, -5, "r"), (0, -4, "r")):
        altar.dot(CX + x, GY + y, ch)
    idol = rel(Piece(shape="dome"), idol_art, -6, -24)
    candles = Piece(shape="bevel")
    block(candles, -12, -16, 2, 4, "U", "u")
    block(candles, 10, -15, 2, 3, "U", "u")
    pieces = [altar, idol, candles]
    if lit:
        fl = Piece(outline=None, shape="flat")
        for (x, y) in ((-12, -18), (10, -17)):
            fl.dot(CX + x + (phase % 2), GY + y, "E")
            fl.dot(CX + x, GY + y + 1, "E")
            fl.dot(CX + x + 1, GY + y + 1, "E")
            if phase % 3 == 0:
                fl.dot(CX + x + 1 - (phase % 2), GY + y - 1, "E")
        pieces.append(fl)
    return pieces


# --- Mercader ------------------------------------------------------------------------------

HOOD = art("""
...QQQQQQ...
..QQQQQQQQ..
.QQQKKKKQQq.
.QQKKKKKKQq.
.QQKEKKEKQq.
.QQKKKKKKQq.
.QQQKKKKQQq.
..QQQQQQQq..
""")

PACK = art("""
..UUUUUUUU..
.UuuuuuuuuU.
..NNNNNNNN..
.NNnNNNNnNN.
.NNnNNNNnNN.
.NNNNNNNNNN.
.NNGGNNNNNN.
.NNGgNNNNNn.
.NNNNNNNNNn.
.NNnNNNNnNn.
.NnnnnnnnnN.
""")


def mercader(phase=0):
    bob = 1 if phase in (2, 3) else 0
    pack = rel(Piece(shape="bevel"), PACK, -11, -38 + bob)
    robe = Piece(shape="cyl")
    widths = [12, 12, 14, 14, 16, 16, 16, 18, 18, 18, 20, 20, 20, 20, 20, 22, 22, 22, 22, 22, 22]
    for j, w in enumerate(widths):
        y = GY - len(widths) + j
        if j == 0:
            y += bob
        for i in range(w):
            ch = "Q"
            if i >= w - 3:
                ch = "q"
            elif (i * 3 + j) % 7 == 0 and j > 3:
                ch = "q"
            if j == len(widths) - 1 and i % 3 == 0:
                ch = "k"
            robe.dot(CX - 3 - w // 2 + i + 3, y, ch)
    # faja y bolsitas
    for i in range(14):
        robe.dot(CX - 7 + i, GY - 13, "Y" if i % 5 else "G")
    robe.stamp(["nn", "Nn"], CX + 3, GY - 12)
    hood = rel(Piece(shape="dome"), HOOD, -6, -30 + bob)
    # vara con el farol
    pole = Piece(shape="bevel")
    for k in range(34):
        pole.dot(CX + 15, GY - 1 - k, "O" if k % 6 else "o")
    for i in range(5):
        pole.dot(CX + 11 + i, GY - 35, "O")
    lantern = Piece(shape="bevel")
    sway = (0, 1, 0, -1)[phase % 4]
    lx, ly = CX + 9 + sway, GY - 33
    lantern.stamp(["GGGGG", "G...G", "G...G", "G...G", "ggggg"], lx, ly)
    flame = Piece(outline=None, shape="flat")
    for (dx, dy) in ((1, 1), (2, 1), (3, 1), (1, 2), (2, 2), (3, 2), (2, 3)):
        flame.dot(lx + dx, ly + dy, "E")
    if phase % 2:
        flame.dot(lx + 2, ly + 1, "F")
    # mano que asoma de la manga, sobre la vara
    hand = Piece(shape="bevel")
    hand.stamp(["WB", "BD"], CX + 13, GY - 17)
    return [pack, pole, robe, hood, lantern, flame, hand]


# --- Forja ---------------------------------------------------------------------------------

ANVIL = art("""
SSSSSSSSSSSSSS..
ISSSSSSSSSSSSSSS
.IIIIIIIIIIIIis.
...IIIIIIIii....
....IIIIIi......
....IIIIIi......
...IIIIIIIi.....
..IIIIIIIIIi....
""")

FLAME = [
    art("""
...E...
..EE...
..EEE..
.EEEEE.
.EEFEE.
EEFFFEE
.EFFFE.
..EEE..
"""),
    art("""
....E..
...EE..
..EEE..
.EEEEE.
.EFEEE.
EEFFFEE
.EFFFE.
..EEE..
"""),
    art("""
..E....
..EE...
.EEEE..
.EEEEE.
.EEFEE.
EEFFFEE
.EFFFE.
..EEE..
"""),
]


def forja(phase=0):
    stone = Piece(shape="bevel")
    block(stone, -13, -10, 26, 10, "C", "c", "U")
    for (x, y) in ((-9, -6), (-8, -6), (-8, -5), (4, -4), (5, -4), (5, -3), (-2, -7), (-1, -7)):
        stone.dot(CX + x, GY + y, "c")
    # cadenas que cuelgan del bloque
    for k in range(6):
        stone.dot(CX - 12, GY - 9 + k, "i" if k % 2 else "I")
        stone.dot(CX + 11, GY - 8 + k, "I" if k % 2 else "i")
    anvil = rel(Piece(shape="bevel"), ANVIL, -8, -18)
    # brasero de hierro con la llama del alma
    bowl = Piece(shape="cyl")
    bowl.stamp([".iIIIIIi.", "..iIIIi..", "...iIi..."], CX - 5, GY - 23)
    fl = rel(Piece(outline=None, shape="flat"), FLAME[phase % 3], -4, -31)
    sparks = Piece(outline=None, shape="flat")
    for (dx, dy) in (((-6, -34), (5, -36)), ((-7, -37), (6, -33)), ((4, -39), (-5, -32)))[phase % 3]:
        sparks.dot(CX + dx, GY + dy, "E")
    return [stone, anvil, bowl, fl, sparks]


# --- Hojas ---------------------------------------------------------------------------------

def frame(P):
    grid, normals = CANVAS.render(P)
    return CANVAS.to_rgba(grid, normals)


SHEETS = {
    "fuente": {
        "idle": (True, 0.8, {"s": [fuente(k) for k in range(4)]}),
        "used": (True, 1.0, {"s": [fuente(0, dry=True)]}),
    },
    "santuario": {
        "idle": (True, 1.2, {"s": [santuario(k) for k in range(6)]}),
        "used": (True, 1.0, {"s": [santuario(0, lit=False)]}),
    },
    "mercader": {
        "idle": (True, 1.6, {"s": [mercader(k) for k in range(4)]}),
    },
    "forja": {
        "idle": (True, 0.6, {"s": [forja(k) for k in range(3)]}),
    },
}


def trap_plate(path):
    """Losa de la trampa: piedra más oscura que el piso, con un filete y nueve
    agujeros por donde salen los pinchos."""
    stone, dark, light, hole = (86, 78, 72, 255), (58, 52, 48, 255), (112, 102, 94, 255), (14, 10, 12, 255)
    img = Image.new("RGBA", (32, 32), stone)
    px = img.load()
    for i in range(32):
        for (x, y) in ((i, 0), (i, 31), (0, i), (31, i)):
            px[x, y] = dark
        for (x, y) in ((i, 1), (1, i)):
            if 0 < i < 31:
                px[x, y] = light
    for gy in range(3):
        for gx in range(3):
            cx, cy = 7 + gx * 9, 7 + gy * 9
            for dy in range(-2, 2):
                for dx in range(-2, 2):
                    px[cx + dx, cy + dy] = hole
            px[cx - 2, cy - 2] = dark
            px[cx + 1, cy + 1] = light
    # grietas
    for (x, y) in ((12, 11), (13, 12), (13, 13), (14, 14), (21, 20), (22, 21), (22, 22)):
        px[x, y] = dark
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print(f"trampa: {path}")


def main():
    preview = None
    for a in sys.argv[1:]:
        if a.startswith("--preview="):
            preview = a.split("=", 1)[1]
    pk.OUT_DIR = pk.ROOT / "assets" / "sprites" / "props"
    for name, anims in SHEETS.items():
        write_sheet(name, anims, frame, CANVAS, 24, 0.35, f"{preview}_{name}.png" if preview else None)
    trap_plate(pk.ROOT / "assets" / "textures" / "props" / "trampa.png")


if __name__ == "__main__":
    main()
