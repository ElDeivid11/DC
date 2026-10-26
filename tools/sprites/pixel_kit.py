"""Kit para dibujar enemigos en pixel art grueso (lo usan draw_*.py).

Un sprite se arma con «sellos» dibujados a mano en ASCII (un carácter por
píxel, colores de PAL) y líneas de píxeles. Cada sello va en una Piece, que
lleva su contorno de 1 px y una forma (para el mapa de normales); las piezas
se apilan en orden. Las poses son diccionarios con dónde va cada parte, en
píxeles enteros respecto del piso; las animaciones son listas de poses.

write_sheet() escribe la hoja (PNG), la máscara de brillo (_glow.png), el
mapa de normales (_normal.png) y el JSON (formato en tools/sprites/README.md).
lit_gif() arma un GIF con las animaciones iluminadas como en el juego.
"""
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "sprites" / "enemies"

# Paleta de todos los enemigos. 2-3 tonos por material, contorno casi negro.
PAL = {
    "K": "#1a1020",  # contorno y huecos
    "W": "#f2ead2", "B": "#c4b294", "D": "#86727a",  # hueso
    "E": "#ffffff",  # lo que brilla con el color de ojos (pupilas, llamas, espectro)
    "R": "#e04a3a", "r": "#92243a",  # rojo (bufanda, pintura)
    "S": "#d4dce6", "s": "#7a8296",  # acero
    "G": "#f0b840", "g": "#a06428",  # oro
    "O": "#9a5a30", "o": "#5e3420",  # madera
    "L": "#5a382c", "N": "#8a5a3a", "n": "#6a4028",  # cuero
    "H": "#6a9a48", "V": "#4a7034", "v": "#2c4426",  # tela verde (capucha)
    "M": "#86a83c",  # musgo
    "U": "#d8cfa4", "u": "#a39a74",  # vendas
    "P": "#8a52aa", "Q": "#6a3a8a", "q": "#42245a",  # tela morada
    "k": "#2a2030",  # tela oscura, rota
    "Y": "#d8a838",  # tela amarilla (taparrabo)
    "I": "#9a9aa8", "i": "#5c5c6a",  # hierro
    "C": "#9a8e78", "c": "#5e5446",  # cuerno y corona de hueso viejo
    "Z": "#c88a40", "z": "#7a5228",  # bronce
    "A": "#3d62a8", "a": "#24396b",  # tela azul
    "T": "#7a5a8a",  # plumas
    "X": "#ffffff", "x": "#a8d8ff",  # estela
    "F": "#b4c0b8", "f": "#64766c",  # espíritu (espectro, aura): brilla tenue con el color de ojos
}
GLOW = "E"
SPIRIT = "Ff"
# Valores de la máscara de brillo: 255 = ojos (color de ojos a pleno),
# 128 = espíritu (su gris por el color de ojos, sin luz ni niebla).
GLOW_EYE, GLOW_SPIRIT = 255, 128
METAL = "SsGgIiZz"


def art(s):
    return [r for r in s.strip("\n").split("\n")]


def flip_x(a):
    w = max(len(r) for r in a)
    return [r.ljust(w, ".")[::-1] for r in a]


def flip_y(a):
    return a[::-1]


def recolor(a, table):
    return ["".join(table.get(c, c) for c in r) for r in a]


def rot90(a):
    """Gira un sello 90° (en sentido horario)."""
    w = max(len(r) for r in a)
    rows = [r.ljust(w, ".") for r in a]
    return ["".join(rows[len(rows) - 1 - j][i] for j in range(len(rows))) for i in range(w)]


def width(a):
    return max(len(r) for r in a)


def rot_point(p, a):
    """Dónde cae el píxel p = (col, fila) de un sello al girarlo con rot90."""
    x, y = p
    return (len(a) - 1 - y, x)


def squash(a, row=4):
    """Aplastado: una fila menos (la del medio del cráneo, por defecto)."""
    return a[:row] + a[row + 1:]


def stretch(a, row=4):
    """Estirado: una fila repetida."""
    return a[:row + 1] + [a[row]] + a[row + 1:]


def dither(a, phase=0):
    """Trama de damero: deja un píxel sí y uno no (transparencia retro)."""
    return ["".join(c if (x + y + phase) % 2 == 0 else "." for x, c in enumerate(r)) for y, r in enumerate(a)]


def oriented(table, name):
    """Un arma en una dirección: table tiene los dibujos «ul» (diagonal hacia
    arriba a la izquierda), «u» (vertical) y «l» (horizontal), cada uno con
    dónde la agarra la mano; las otras direcciones («ur», «r», «dl», «dr»,
    «d») salen espejando. -> (sello, (columna, fila) del agarre)."""
    base = {"ul": "ul", "ur": "ul", "dl": "ul", "dr": "ul", "u": "u", "d": "u", "l": "l", "r": "l"}[name]
    a, (gx, gy) = table[base]
    w, h = width(a), len(a)
    if name in ("ur", "dr", "r"):
        a, gx = flip_x(a), w - 1 - gx
    if name in ("dl", "dr", "d"):
        a, gy = flip_y(a), h - 1 - gy
    return a, (gx, gy)


MIRROR = {"ul": "ur", "ur": "ul", "dl": "dr", "dr": "dl", "l": "r", "r": "l", "u": "u", "d": "d"}


# --- Piezas ------------------------------------------------------------------------------

class Piece:
    """Una capa: píxeles con su color y, alrededor, su contorno (1 px).
    shape dice qué volumen tiene, para el mapa de normales: "dome" (cúpula,
    una calavera), "disc" (cúpula baja, un escudo), "cyl" (cilindro acostado:
    tórax, pelvis, telas que rodean), "bevel" (borde inclinado: huesos,
    armas, telas sueltas) o "flat"."""

    def __init__(self, outline="K", shape="bevel"):
        self.px = {}
        self.outline = outline
        self.shape = shape

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


def _normals(shape, solid):
    """Normales (x derecha, y arriba, z hacia la cámara) de los píxeles de una
    pieza según su forma."""
    ys, xs = np.nonzero(solid)
    if shape in ("dome", "disc", "cyl"):
        cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
        rx, ry = (xs.max() - xs.min()) / 2 + 1.0, (ys.max() - ys.min()) / 2 + 1.0
        dx, dy = (xs - cx) / rx, (ys - cy) / ry
        if shape == "cyl":
            dy = dy * 0.3
        k = 0.6 if shape == "disc" else 0.95
        nx, ny = dx * k, -dy * k
        nz = np.sqrt(np.clip(1 - nx ** 2 - ny ** 2, 0.05, 1))
    else:
        pad = np.pad(solid, 1)
        free_l, free_r = ~pad[1:-1, :-2], ~pad[1:-1, 2:]
        free_u, free_d = ~pad[:-2, 1:-1], ~pad[2:, 1:-1]
        nx = (free_r.astype(float) - free_l)[ys, xs] * 0.75
        ny = (free_u.astype(float) - free_d)[ys, xs] * 0.75
        if shape == "flat":
            nx, ny = nx * 0, ny * 0
        nz = np.ones_like(nx)
    v = np.stack([nx, ny, nz], -1)
    return ys, xs, v / np.linalg.norm(v, axis=-1, keepdims=True)


class Canvas:
    """El cuadro donde se dibuja un enemigo: w x h píxeles, con el punto del
    piso entre los pies en (cx, ground). Las poses van relativas a ese punto
    (x a la derecha, y hacia abajo: negativo = arriba del piso)."""

    def __init__(self, w, h, cx, ground):
        self.w, self.h, self.cx, self.ground = w, h, cx, ground

    def at(self, p):
        return (self.cx + p[0], self.ground + p[1])

    def render(self, pieces):
        """-> (grilla de caracteres, normales HxWx3)."""
        H, W = self.h, self.w
        grid = np.full((H, W), ".", dtype="<U1")
        normals = np.zeros((H, W, 3))
        normals[..., 2] = 1.0
        for p in pieces:
            solid = np.zeros((H, W), bool)
            for (x, y) in p.px:
                if 0 <= x < W and 0 <= y < H:
                    solid[y, x] = True
            if not solid.any():
                continue
            if p.outline:
                pad = np.pad(solid, 1)
                left, right, up, down = pad[1:-1, :-2], pad[1:-1, 2:], pad[:-2, 1:-1], pad[2:, 1:-1]
                ring = ~solid & (left | right | up | down)
                grid[ring] = p.outline
                # el contorno mira hacia afuera de la pieza
                v = np.stack([(left.astype(float) - right) * 0.8, (down.astype(float) - up) * 0.8,
                              np.full((H, W), 0.6)], -1)
                v /= np.linalg.norm(v, axis=-1, keepdims=True)
                normals[ring] = v[ring]
            for (x, y), ch in p.px.items():
                if 0 <= x < W and 0 <= y < H:
                    grid[y, x] = ch
            ys, xs, v = _normals(p.shape, solid)
            normals[ys, xs] = v
        return grid, normals

    def to_rgba(self, grid, normals):
        """-> (color RGBA, máscara de brillo (GLOW_EYE / GLOW_SPIRIT / 0),
        normales RGBA). Las normales van en RGB (x derecha, y arriba, z hacia
        la cámara; 0..255 = -1..1) y el alfa marca el material: 128 = metal
        (brilla), 255 = mate."""
        rgba = np.zeros((self.h, self.w, 4), np.uint8)
        for ch, hexc in PAL.items():
            m = grid == ch
            rgba[m, :3] = [int(hexc[i:i + 2], 16) for i in (1, 3, 5)]
            rgba[m, 3] = 255
        nrm = np.zeros((self.h, self.w, 4), np.uint8)
        nrm[..., :3] = np.clip(np.round((normals + 1.0) * 127.5), 0, 255).astype(np.uint8)
        nrm[..., 3] = np.where(np.isin(grid, list(METAL)), 128, 255)
        glow = np.where(grid == GLOW, GLOW_EYE, np.where(np.isin(grid, list(SPIRIT)), GLOW_SPIRIT, 0)).astype(np.uint8)
        return rgba, glow, nrm


# --- Poses -------------------------------------------------------------------------------
# Una pose es un dict: puntos (x, y), polilíneas [hombro, codo, mano] o
# [cadera, rodilla, tobillo], y datos sueltos (qué espada, cuadro de la
# bufanda, ojos encendidos...).

HEAD = ("skull", "jaw")
LEGS = ("leg_r", "leg_l", "leg_n", "leg_f")
FEET = ("foot_r", "foot_l", "foot_n", "foot_f")
NOT_BODY = ("smear", "bones")


def move(v, dx, dy):
    if isinstance(v, list):
        return [(x + dx, y + dy) for x, y in v]
    return (v[0] + dx, v[1] + dy)


def is_point(v):
    return isinstance(v, tuple) and len(v) == 2 and all(isinstance(c, int) for c in v)


def is_path(v):
    return isinstance(v, list) and v and all(is_point(p) for p in v)


def shift(P, dx, dy, keys):
    """Corre esas partes (de las piernas, solo la cadera)."""
    Q = dict(P)
    for k in keys:
        if k not in Q or not (is_point(Q[k]) or is_path(Q[k])):
            continue
        if k in LEGS:
            Q[k] = [move(Q[k][0], dx, dy)] + Q[k][1:]
        else:
            Q[k] = move(Q[k], dx, dy)
    return Q


def upper(P):
    """Las partes que se mueven con el cuerpo (no los pies ni las piernas)."""
    return [k for k in P if (is_point(P[k]) or is_path(P[k])) and k not in FEET and k not in LEGS
            and k not in NOT_BODY and not k.startswith("fixed_")]


def bob(P, dy, head=0, dx=0):
    """Agacha el cuerpo dy píxeles (también las caderas; las rodillas, la
    mitad; los pies no). head: la cabeza, además."""
    Q = shift(P, dx, dy, upper(P) + [k for k in LEGS if k in P])
    for k in LEGS:
        if k in Q:
            Q[k] = [Q[k][0], move(Q[k][1], 0, dy // 2)] + Q[k][2:]
    return shift(Q, 0, head, HEAD) if head else Q


def pose(P, **kw):
    Q = dict(P)
    Q.update(kw)
    return Q


def lift(P, foot, dy, dx=0):
    """Levanta un pie (y su tobillo) dy píxeles."""
    leg = {"foot_r": "leg_r", "foot_l": "leg_l", "foot_n": "leg_n", "foot_f": "leg_f"}[foot]
    Q = dict(P)
    Q[foot] = move(P[foot], dx, -dy)
    hip, knee, ankle = P[leg]
    Q[leg] = [hip, move(knee, dx // 2, -(dy // 2)), move(ankle, dx, -dy)]
    return Q


def arm(P, key, elbow, hand):
    """Brazo desde su hombro: codo y mano relativos al hombro."""
    sh = P[key][0]
    return pose(P, **{key: [sh, move(sh, *elbow), move(sh, *hand)]})


def lunge(P, dx, dy):
    """Todo el cuerpo (menos los pies) se va dx, dy: embestir o retroceder."""
    return bob(P, dy, dx=dx)


def jaw_open(P, d):
    return pose(P, jaw=move(P["jaw"], 0, d))


def crescent(c, r, a0, a1, w):
    """Medialuna de píxeles alrededor de c (relativo al piso), de radio r,
    entre los ángulos a0 y a1 (grados, 0 = derecha, 90 = arriba), más gruesa
    (w px) hacia a1."""
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


def smear_piece(canvas, pts):
    p = Piece("x", "flat")
    for (x, y) in pts:
        p.dot(canvas.cx + x, canvas.ground + y, "X")
    return p


# --- Hoja --------------------------------------------------------------------------------

COLUMNS = 16


def write_sheet(species, anims, frame_fn, canvas, ppm, self_light, preview=None, flat_light=True):
    """anims: nombre -> (se repite, duración en s, {dirección: [poses]}).
    frame_fn(pose) -> (rgba, brillo, normales) en el lienzo canvas."""
    frames, meta_anims = [], {}
    for name, (loop, length, dirs) in anims.items():
        count = len(dirs["s"])
        entry = {"loop": loop, "fps": round(count / length, 2), "dirs": {}}
        for d, seq in dirs.items():
            assert len(seq) == count, (name, d)
            for i, P in enumerate(seq):
                rgba, glow, nrm = frame_fn(P)
                if rgba[0, :, 3].any() or rgba[:, 0, 3].any() or rgba[:, -1, 3].any() or rgba[-1, :, 3].any():
                    print(f"  aviso: {species} {name}/{d}/{i} toca el borde del cuadro")
                entry["dirs"].setdefault(d, []).append(len(frames))
                frames.append((rgba, glow, nrm))
        meta_anims[name] = entry
    alpha = np.zeros((canvas.h, canvas.w), dtype=bool)
    for rgba, _, _ in frames:
        alpha |= rgba[..., 3] > 0
    ys, xs = np.nonzero(alpha)
    x0, x1 = max(0, xs.min() - 1), min(canvas.w, xs.max() + 2)
    y0, y1 = max(0, ys.min() - 1), min(canvas.h, ys.max() + 2)
    frames = [(rgba[y0:y1, x0:x1], glow[y0:y1, x0:x1], nrm[y0:y1, x0:x1]) for rgba, glow, nrm in frames]
    fw, fh = x1 - x0, y1 - y0
    pivot = [canvas.cx - x0, canvas.ground - y0]
    rows = (len(frames) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * fw, rows * fh), (0, 0, 0, 0))
    glow_sheet = Image.new("L", (COLUMNS * fw, rows * fh), 0)
    normal_sheet = Image.new("RGBA", (COLUMNS * fw, rows * fh), (128, 128, 255, 255))
    for n, (rgba, glow, nrm) in enumerate(frames):
        x, y = (n % COLUMNS) * fw, (n // COLUMNS) * fh
        sheet.paste(Image.fromarray(rgba, "RGBA"), (x, y))
        glow_sheet.paste(Image.fromarray(glow, "L"), (x, y))
        normal_sheet.paste(Image.fromarray(nrm, "RGBA"), (x, y))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT_DIR / f"{species}.png", optimize=True)
    glow_sheet.save(OUT_DIR / f"{species}_glow.png", optimize=True)
    normal_sheet.save(OUT_DIR / f"{species}_normal.png", optimize=True)
    meta = {"version": 1, "sheet": f"{species}.png", "glow": f"{species}_glow.png", "normal": f"{species}_normal.png",
            "frame": [int(fw), int(fh)],
            "columns": COLUMNS, "pivot": [int(pivot[0]), int(pivot[1])], "pixels_per_meter": ppm,
            "flat_light": flat_light, "self_light": self_light, "anims": meta_anims}
    (OUT_DIR / f"{species}.json").write_text(json.dumps(meta, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{species}: {len(frames)} cuadros de {fw}x{fh}, {len(meta_anims)} animaciones")
    if preview:
        zoom = 3
        rows_ = [ids for e in meta_anims.values() for ids in e["dirs"].values()]
        cells = max(len(r) for r in rows_)
        out = Image.new("RGBA", (cells * fw * zoom, len(rows_) * fh * zoom), (60, 52, 44, 255))
        for r, ids in enumerate(rows_):
            for c, k in enumerate(ids):
                cell = Image.fromarray(frames[k][0], "RGBA").resize((fw * zoom, fh * zoom), Image.NEAREST)
                out.alpha_composite(cell, (c * fw * zoom, r * fh * zoom))
        out.save(preview)
        print(f"vista previa: {preview}")


# --- Vista previa iluminada (la misma cuenta que shaders/enemy_sprite.gdshader) ----------

def _band(x):
    return np.where(x > 0.7, 1.0, np.where(x > 0.35, 0.65, np.where(x > 0.08, 0.35, 0.0)))


def _to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _to_srgb(c):
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.clip(c, 0, None) ** (1 / 2.4) - 0.055)


def lit(rgba, glow, nrm, lights, eye=(0.6, 1.0, 0.35), ambient=0.12, self_light=0.3, tint=0.5):
    """El cuadro iluminado: lights = [((x, y, z) hacia la luz, (r, g, b)), ...]."""
    n = nrm[..., :3].astype(float) / 127.5 - 1.0
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    alb = _to_lin(rgba[..., :3].astype(float) / 255.0)
    metal = nrm[..., 3] < 191
    light = np.full(alb.shape, ambient)
    spec = np.zeros(alb.shape)
    for L, col in lights:
        L = np.array(L, float)
        L /= np.linalg.norm(L)
        col = np.array(col, float)
        light += _band((n * L).sum(-1))[..., None] * col
        h = L + np.array([0, 0, 1.0])
        h /= np.linalg.norm(h)
        spec += np.where(metal & ((n * h).sum(-1) > 0.93), 0.8, 0.0)[..., None] * col
    lum = light.mean(-1, keepdims=True)
    light = lum + (light - lum) * tint
    eye = _to_lin(np.array(eye, float))
    halo = np.zeros(glow.shape)
    ys, xs = np.nonzero(glow == GLOW_EYE)
    for y, x in zip(ys, xs):
        halo[max(0, y - 2):y + 3, max(0, x - 2):x + 3] = 0.12
    c = alb * (light + self_light) + spec + alb * eye[None, None, :] * 1.4 * halo[..., None]
    spirit = glow == GLOW_SPIRIT
    c[spirit] = alb[spirit].mean(-1, keepdims=True) * eye * 1.4 * 0.6
    c[glow == GLOW_EYE] = eye * 1.4
    out = np.zeros_like(rgba)
    out[..., :3] = (np.clip(_to_srgb(np.clip(c, 0, 1)), 0, 1) * 255).astype(np.uint8)
    out[..., 3] = rgba[..., 3]
    return out


def lit_gif(path, plan, frame_fn, zoom=5, eye=(0.6, 1.0, 0.35), crop=None):
    """GIF de una lista de (pose, segundos), con una antorcha que da vueltas
    alrededor y la lámpara del equipo de frente."""
    frames, durs = [], []
    for k, (P, dur) in enumerate(plan):
        ang = 2 * math.pi * k / len(plan)
        lights = [((math.cos(ang), 0.45, math.sin(ang)), (1.1, 0.75, 0.4)), ((0.0, 0.2, 1.0), (0.45, 0.4, 0.33))]
        rgba, glow, nrm = frame_fn(P)
        img = Image.fromarray(lit(rgba, glow, nrm, lights, eye))
        if crop:
            img = img.crop(crop)
        bg = Image.new("RGBA", img.size, (34, 28, 26, 255))
        bg.alpha_composite(img)
        frames.append(bg.convert("RGB").resize((img.width * zoom, img.height * zoom), Image.NEAREST))
        durs.append(int(round(dur * 1000)))
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=durs, loop=0)
    print(f"gif: {path} ({len(frames)} cuadros)")


def reel(anims, names):
    """Plan para lit_gif: las animaciones en orden (nombre o (nombre, vueltas))."""
    plan = []
    for spec in names:
        name, loops = spec if isinstance(spec, tuple) else (spec, 1)
        loop, length, dirs = anims[name]
        seq = dirs["s"]
        for _ in range(loops):
            plan += [(P, length / len(seq)) for P in seq]
    return plan
