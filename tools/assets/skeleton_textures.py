#!/usr/bin/env python3
"""Texturas PS1 de los esqueletos (las llama process_enemies.mjs).

    python3 -I skeleton_textures.py bone  --ao AO.png --height H.png --out X.png \
        --bone "#cdbf98" --shadow "#2c3027" --stain "#5a5a33" [--size 128] [--seed 1]
    python3 -I skeleton_textures.py cloth --src T_Ranger_BaseColor.png --out X.png \
        --dark "#120a18" --mid "#3a2448" --light "#7a6488" --trim "#5a4a30" [--size 128]

bone: el modelo no trae textura. Se arma con los mapas que hornea
build_skeletons.py sobre las UV nuevas: oclusión ambiental (uniones, costillas,
órbitas y entre vértebras más oscuras) y altura (las piernas más sucias que el
cráneo). Color = sombra -> hueso según la oclusión, manchas de ruido de baja
frecuencia (moho, óxido, hollín: el color "stain" de cada especie), grano fino
y cuantización a 15 bits (5-5-5, como la PlayStation) con trama Bayer 4x4.

cloth: el atlas del traje Ranger de Quaternius (4096 px, verdes y marrones) se
reduce con BOX y se re-pinta con una rampa propia (tela oscura de nigromante):
la tela (verdes) va a dark/mid/light según su luminancia, el cuero y los
metales (naranjas, amarillos, grises) a la rampa de "trim". Misma trama 15 bits.

Determinista: misma entrada y semilla, mismo PNG.
"""
import argparse
import colorsys

import numpy as np
from PIL import Image

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0


def hex_rgb(s: str) -> np.ndarray:
    s = s.lstrip("#")
    return np.array([int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def load_gray(path: str, size: int) -> np.ndarray:
    im = Image.open(path).convert("L").resize((size, size), Image.BOX)
    return np.asarray(im, dtype=np.float32) / 255.0


def value_noise(size: int, cells: int, rng: np.random.Generator) -> np.ndarray:
    """Ruido de valor suave (bilineal sobre una grilla de cells x cells)."""
    grid = rng.random((cells + 1, cells + 1)).astype(np.float32)
    u = np.linspace(0, cells, size, endpoint=False, dtype=np.float32)
    i = np.floor(u).astype(int)
    f = u - i
    f = f * f * (3 - 2 * f)
    a = grid[i][:, i]
    b = grid[i][:, i + 1]
    c = grid[i + 1][:, i]
    d = grid[i + 1][:, i + 1]
    fx = f[None, :]
    fy = f[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def quantize15(rgb: np.ndarray) -> Image.Image:
    size_y, size_x = rgb.shape[:2]
    th = np.tile(BAYER4, (size_y // 4 + 1, size_x // 4 + 1))[:size_y, :size_x][..., None]
    q = np.floor(np.clip(rgb, 0.0, 1.0) * 31.0 + th) / 31.0
    return Image.fromarray((np.clip(q, 0.0, 1.0) * 255.0).astype(np.uint8), "RGB")


def bone(args: argparse.Namespace) -> None:
    size = args.size
    rng = np.random.default_rng(args.seed)
    ao = load_gray(args.ao, size)
    h = load_gray(args.height, size)
    bone_c, shadow_c, stain_c = hex_rgb(args.bone), hex_rgb(args.shadow), hex_rgb(args.stain)
    # Oclusión con más contraste: las uniones casi negras, la superficie clara.
    occ = np.clip((ao - 0.35) / 0.6, 0.0, 1.0) ** 1.3
    rgb = shadow_c + (bone_c - shadow_c) * occ[..., None]
    # Manchas: dos octavas de ruido, más fuertes abajo (pies y tibias sucios).
    n = 0.65 * value_noise(size, 6, rng) + 0.35 * value_noise(size, 17, rng)
    amount = np.clip((n - 0.45) * 2.2, 0.0, 1.0) * (args.stain_amount * (0.45 + 0.55 * (1.0 - h) ** 1.5))
    rgb = rgb + (stain_c * (0.55 + 0.45 * occ[..., None]) - rgb) * amount[..., None]
    # Grano fino (se ve "pintado a mano" a 128 px).
    grain = rng.normal(0.0, args.grain, size=(size, size)).astype(np.float32)
    rgb = rgb * (1.0 + grain[..., None])
    quantize15(rgb).save(args.out)


def cloth(args: argparse.Namespace) -> None:
    size = args.size
    src = Image.open(args.src).convert("RGB").resize((size, size), Image.BOX)
    img = np.asarray(src, dtype=np.float32) / 255.0
    flat = img.reshape(-1, 3)
    hsv = np.array([colorsys.rgb_to_hsv(*p) for p in flat], dtype=np.float32).reshape(img.shape)
    hue, sat, val = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    lum = img @ np.array([0.3, 0.59, 0.11], dtype=np.float32)
    # Luminancia normalizada por zona (el atlas tiene sombreado pintado).
    t = np.clip((lum - np.percentile(lum, 3)) / max(np.percentile(lum, 97) - np.percentile(lum, 3), 1e-3), 0.0, 1.0)
    dark, mid, light = hex_rgb(args.dark), hex_rgb(args.mid), hex_rgb(args.light)
    ramp = np.where(t[..., None] < 0.5, dark + (mid - dark) * (t[..., None] * 2), mid + (light - mid) * ((t[..., None] - 0.5) * 2))
    trim = hex_rgb(args.trim)
    trim_ramp = trim * (0.35 + 0.9 * t[..., None])
    is_cloth = (hue > 0.17) & (hue < 0.5) & (sat > 0.15)
    rgb = np.where(is_cloth[..., None], ramp, trim_ramp)
    rng = np.random.default_rng(args.seed)
    rgb = rgb * (1.0 + rng.normal(0.0, args.grain, size=(size, size)).astype(np.float32)[..., None])
    _ = val
    quantize15(rgb).save(args.out)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("bone")
    b.add_argument("--ao", required=True)
    b.add_argument("--height", required=True)
    b.add_argument("--out", required=True)
    b.add_argument("--size", type=int, default=128)
    b.add_argument("--seed", type=int, default=1)
    b.add_argument("--bone", default="#cdbf98")
    b.add_argument("--shadow", default="#2c3027")
    b.add_argument("--stain", default="#5a5a33")
    b.add_argument("--stain-amount", type=float, default=0.7)
    b.add_argument("--grain", type=float, default=0.035)
    c = sub.add_parser("cloth")
    c.add_argument("--src", required=True)
    c.add_argument("--out", required=True)
    c.add_argument("--size", type=int, default=128)
    c.add_argument("--seed", type=int, default=1)
    c.add_argument("--dark", default="#120a18")
    c.add_argument("--mid", default="#3a2448")
    c.add_argument("--light", default="#7a6488")
    c.add_argument("--trim", default="#5a4a30")
    c.add_argument("--grain", type=float, default=0.03)
    args = ap.parse_args()
    {"bone": bone, "cloth": cloth}[args.cmd](args)


if __name__ == "__main__":
    main()
