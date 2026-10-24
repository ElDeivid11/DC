"""Paso 2 de 2 de los sprites de enemigos de prueba: cuadros crudos -> pixel art.

Lee lo que dejó tools/sprites/bake_enemy_sprites.tscn (render 4x de los
esqueletos 3D) y arma, por especie, la hoja que usa el juego:

    assets/sprites/enemies/<especie>.png       cuadros RGBA en grilla
    assets/sprites/enemies/<especie>_glow.png  máscara de brillo (ojos)
    assets/sprites/enemies/<especie>.json      formato: tools/sprites/README.md

    python3 -I tools/sprites/pixelize_sprites.py --raw=/tmp/sprites_raw \
        [--only=esqueleto_esbirro] [--preview=/tmp/hoja.png]

Pasos por cuadro (todo con numpy, determinista):
1. Reducción 4x por caja con alfa premultiplicada; cobertura >= ALPHA_CUT
   queda opaca (así los huesos finos no se cortan).
2. Paleta propia de la especie (k-medias en Lab sobre todos sus cuadros,
   PALETTE_SIZE colores) y cada píxel a su color más cercano: bandas planas.
3. Píxeles sueltos fuera.
4. Luz de borde: el borde de arriba y de la izquierda (de donde viene la luz)
   sube un tono dentro de su rampa.
5. Contorno de 1 px por fuera: el color vecino llevado casi a tinta.
6. Ojos: la máscara de brillo marca los píxeles que el juego enciende con el
   color de ojos de cada enemigo.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "sprites" / "enemies"
SS = 4
COLUMNS = 16
ALPHA_CUT = 0.35
GLOW_CUT = 0.2
PALETTE_SIZE = 16
KMEANS_ITERS = 16
OUTLINE_INK = np.array([18.0, 11.0, 16.0])
# Gradación antes de cuantizar (estilo HD-2D): más contraste, sombras hacia
# violeta frío y luces hacia crema cálida.
CONTRAST = 1.25
SHADOW_TINT = np.array([0.30, 0.22, 0.42])
LIGHT_TINT = np.array([1.0, 0.92, 0.74])
GRADE = 0.35
DARK_KEEP = 0.8
# Engrosado de la figura (píxeles): el esqueleto realista tiene huesos de
# 1 px a esta escala; el pixel art los dibuja más gruesos.
DILATE = 1
OUTLINE_MIX = 0.8
EYE_BASE = np.array([255, 240, 205], dtype=np.uint8)
# Orden de las animaciones en la hoja (las variantes van detrás de su papel).
ROLE_ORDER = ["idle", "walk", "combat", "attack", "hit", "death", "spawn", "dormant", "taunt", "ability"]
DIR_ORDER = ["s", "e", "n", "w"]


# --- Color ------------------------------------------------------------------------

def srgb_to_lab(rgb):
    """rgb en 0..1 (..., 3) -> Lab (D65)."""
    c = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16.0 / 116.0)
    return np.stack([116.0 * f[..., 1] - 16.0, 500.0 * (f[..., 0] - f[..., 1]), 200.0 * (f[..., 1] - f[..., 2])], axis=-1)


def kmeans_palette(lab, k):
    """k-medias determinista: arranca en cuantiles de luminancia."""
    order = np.argsort(lab[:, 0], kind="stable")
    centers = lab[order[np.linspace(0, len(order) - 1, k).astype(int)]].copy()
    for _ in range(KMEANS_ITERS):
        d = ((lab[:, None, :] - centers[None, :, :]) ** 2).sum(-1)
        idx = d.argmin(1)
        for j in range(k):
            sel = lab[idx == j]
            if len(sel):
                centers[j] = sel.mean(0)
    return centers


def ramps(lab_pal):
    """Para cada color, el más parecido de su rampa un tono más claro."""
    n = len(lab_pal)
    lighter = np.arange(n)
    for i in range(n):
        best, best_d = i, 1e9
        for j in range(n):
            dl = lab_pal[j, 0] - lab_pal[i, 0]
            if dl < 6.0:
                continue
            d = np.hypot(*(lab_pal[j, 1:] - lab_pal[i, 1:])) + 0.35 * dl
            if d < best_d:
                best, best_d = j, d
        lighter[i] = best
    return lighter


# --- Cuadros ----------------------------------------------------------------------

def reduce(path):
    """RGBA 4x -> (rgb 0..1, cobertura 0..1) al tamaño final."""
    a = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float64) / 255.0
    h, w = a.shape[0] // SS, a.shape[1] // SS
    blocks = a.reshape(h, SS, w, SS, 4)
    alpha = blocks[..., 3].mean((1, 3))
    premul = (blocks[..., :3] * blocks[..., 3:4]).mean((1, 3))
    rgb = premul / np.maximum(alpha, 1e-6)[..., None]
    return rgb, alpha


def reduce_glow(path):
    a = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float64) / 255.0
    h, w = a.shape[0] // SS, a.shape[1] // SS
    lum = a[..., :3].mean(-1) * a[..., 3]
    return lum.reshape(h, SS, w, SS).mean((1, 3))


def grade(rgb):
    """Contraste en S alrededor del gris medio y tinte por luminancia."""
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    # Sin aplastar los oscuros: nada baja de DARK_KEEP de su valor (si no, la
    # túnica violeta del nigromante queda negra pura).
    c = np.clip(np.maximum((rgb - 0.45) * CONTRAST + 0.45, rgb * DARK_KEEP), 0, 1)
    t = np.clip(lum, 0, 1)[..., None]
    tint = SHADOW_TINT * (1 - t) + LIGHT_TINT * t
    return np.clip(c * (1 - GRADE) + c * tint * GRADE / np.maximum(tint.mean(-1, keepdims=True), 1e-3) , 0, 1)


def dilate(rgb, opaque, steps):
    """Engrosa la figura: cada transparente pegado a un opaco toma su color.
    Los huecos de 1 px entre dos partes (entre costillas, entre las piernas)
    no se rellenan: si no, el esqueleto queda macizo."""
    h, w = opaque.shape
    for _ in range(steps):
        rgb_pad = np.pad(rgb, ((1, 1), (1, 1), (0, 0)))
        op_pad = np.pad(opaque, 1)
        sandwiched = (op_pad[:-2, 1:-1] & op_pad[2:, 1:-1]) | (op_pad[1:-1, :-2] & op_pad[1:-1, 2:])
        grown = opaque | sandwiched
        out = rgb.copy()
        for dy, dx in ((1, 0), (0, 1), (0, -1), (-1, 0)):
            nb_op = op_pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
            take = ~grown & nb_op
            out[take] = rgb_pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w][take]
            grown |= take
        rgb, opaque = out, grown & ~(sandwiched & ~opaque)
    return rgb, opaque


def neighbors4(mask):
    """Cantidad de vecinos (4 direcciones) en True."""
    p = np.pad(mask, 1).astype(np.int32)
    return p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]


def finish_frame(idx, opaque, glow, pal_rgb, lighter):
    """Índices de paleta -> RGBA final con luz de borde, contorno y ojos."""
    h, w = idx.shape
    opaque = opaque | glow
    # Píxeles sueltos (sin ningún vecino opaco) fuera, salvo los ojos.
    opaque &= (neighbors4(opaque) > 0) | glow
    padded = np.pad(opaque, 1)
    up_free = ~padded[:-2, 1:-1]
    left_free = ~padded[1:-1, :-2]
    down_solid = padded[2:, 1:-1]
    right_solid = padded[1:-1, 2:]
    # Luz de borde solo donde la figura tiene algo de grosor (si no, un hueso
    # de 1 px quedaría todo iluminado).
    rim = opaque & (up_free | left_free) & (down_solid | right_solid)
    idx = np.where(rim, lighter[idx], idx)
    out = np.zeros((h, w, 4), dtype=np.uint8)
    out[..., :3] = pal_rgb[idx]
    out[..., 3] = np.where(opaque, 255, 0)
    out[glow] = np.append(EYE_BASE, 255)
    # Contorno: cada transparente pegado a la figura toma el color del vecino
    # (el primero que encuentre: arriba, abajo, izquierda, derecha) hacia tinta.
    outline = ~opaque & (neighbors4(opaque) > 0)
    src = np.zeros((h, w, 3))
    found = np.zeros((h, w), dtype=bool)
    rgb_pad = np.pad(out[..., :3].astype(np.float64), ((1, 1), (1, 1), (0, 0)))
    op_pad = np.pad(opaque, 1)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        nb_op = op_pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
        nb_rgb = rgb_pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
        take = outline & nb_op & ~found
        src[take] = nb_rgb[take]
        found |= take
    ink = src * (1.0 - OUTLINE_MIX) + OUTLINE_INK * OUTLINE_MIX
    out[outline, :3] = np.round(ink[outline]).astype(np.uint8)
    out[outline, 3] = 255
    return out


# --- Especie ----------------------------------------------------------------------

def anim_order(names):
    def key(n):
        base, _, var = n.partition("_")
        role = n if n in ROLE_ORDER else base
        return (ROLE_ORDER.index(role) if role in ROLE_ORDER else 99, int(var) if var.isdigit() else 1)
    return sorted(names, key=key)


def process_species(raw_dir, species, preview_rows):
    meta = json.loads((raw_dir / "meta.json").read_text(encoding="utf-8"))
    fw, fh = meta["frame"]
    frames = []  # (anim, dir, i)
    for anim in anim_order(meta["anims"].keys()):
        info = meta["anims"][anim]
        for d in [d for d in DIR_ORDER if d in info["dirs"]]:
            for i in range(info["frames"]):
                frames.append((anim, d, i))
    reduced = []
    for anim, d, i in frames:
        base = raw_dir / f"{anim}_{d}_{i}"
        rgb, alpha = reduce(base.with_suffix(".png"))
        glow = reduce_glow(raw_dir / f"{anim}_{d}_{i}_glow.png") >= GLOW_CUT
        opaque = alpha >= ALPHA_CUT
        rgb, opaque = dilate(grade(rgb), opaque, DILATE)
        reduced.append((rgb, opaque, glow))
    # Paleta de la especie con todos sus píxeles opacos (sin los ojos).
    samples = np.concatenate([rgb[op & ~gl] for rgb, op, gl in reduced])
    lab_pal = kmeans_palette(srgb_to_lab(np.clip(samples, 0, 1)), PALETTE_SIZE)
    # Paleta en sRGB: el promedio real de cada grupo (en Lab solo se agrupa).
    lab_all = srgb_to_lab(np.clip(samples, 0, 1))
    assign = ((lab_all[:, None, :] - lab_pal[None]) ** 2).sum(-1).argmin(1)
    pal_rgb = np.array([np.clip(samples[assign == j].mean(0), 0, 1) if (assign == j).any() else np.zeros(3) for j in range(PALETTE_SIZE)])
    pal_rgb = np.round(pal_rgb * 255).astype(np.uint8)
    lab_pal = srgb_to_lab(pal_rgb / 255.0)
    lighter = ramps(lab_pal)

    rows = (len(frames) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * fw, rows * fh), (0, 0, 0, 0))
    glow_sheet = Image.new("L", (COLUMNS * fw, rows * fh), 0)
    anims = {}
    for n, ((anim, d, i), (rgb, opaque, glow)) in enumerate(zip(frames, reduced)):
        lab = srgb_to_lab(np.clip(rgb, 0, 1))
        idx = ((lab[:, :, None, :] - lab_pal[None, None]) ** 2).sum(-1).argmin(-1)
        img = finish_frame(idx, opaque, glow, pal_rgb, lighter)
        x, y = (n % COLUMNS) * fw, (n // COLUMNS) * fh
        sheet.paste(Image.fromarray(img, "RGBA"), (x, y))
        glow_sheet.paste(Image.fromarray(np.where(glow, 255, 0).astype(np.uint8), "L"), (x, y))
        info = meta["anims"][anim]
        entry = anims.setdefault(anim, {
            "loop": bool(info["loop"]),
            "fps": round(info["frames"] / max(info["length"], 0.05), 2),
            "dirs": {},
        })
        entry["dirs"].setdefault(d, []).append(n)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT_DIR / f"{species}.png", optimize=True)
    glow_sheet.save(OUT_DIR / f"{species}_glow.png", optimize=True)
    out_meta = {
        "version": 1,
        "sheet": f"{species}.png",
        "glow": f"{species}_glow.png",
        "frame": [fw, fh],
        "columns": COLUMNS,
        "pivot": meta["pivot"],
        "pixels_per_meter": meta["pixels_per_meter"],
        "anims": anims,
    }
    (OUT_DIR / f"{species}.json").write_text(json.dumps(out_meta, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{species}: {len(frames)} cuadros, {len(anims)} animaciones -> {OUT_DIR / species}.png")
    if preview_rows is not None:
        for anim in anims:
            cells = [sheet.crop(((k % COLUMNS) * fw, (k // COLUMNS) * fh, (k % COLUMNS + 1) * fw, (k // COLUMNS + 1) * fh)) for k in anims[anim]["dirs"].get("s", [])]
            preview_rows.append((f"{species} {anim}", cells, (fw, fh)))


def save_preview(rows, path, zoom=2):
    if not rows:
        return
    fw, fh = rows[0][2]
    width = max(len(r[1]) for r in rows) * fw * zoom
    sheet = Image.new("RGBA", (width, len(rows) * fh * zoom), (38, 30, 26, 255))
    for r, (_, cells, _) in enumerate(rows):
        for c, cell in enumerate(cells):
            sheet.alpha_composite(cell.resize((fw * zoom, fh * zoom), Image.NEAREST), (c * fw * zoom, r * fh * zoom))
    sheet.save(path)
    print(f"vista previa: {path}")


def main(argv):
    raw, only, preview = None, [], None
    for a in argv:
        if a.startswith("--raw="):
            raw = Path(a.split("=", 1)[1])
        elif a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
        elif a.startswith("--preview="):
            preview = a.split("=", 1)[1]
    if raw is None or not raw.is_dir():
        print(__doc__)
        return 1
    rows = [] if preview else None
    for d in sorted(p for p in raw.iterdir() if p.is_dir() and (p / "meta.json").exists()):
        if only and d.name not in only:
            continue
        process_species(d, d.name, rows)
    if preview:
        save_preview(rows, preview)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
