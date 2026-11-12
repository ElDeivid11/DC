#!/usr/bin/env python3
"""Adapta el atlas de degradados de KayKit (1024 px, colores pastel "chibi")
a una textura PS1 estilo Lunacid: 64 px, paleta sucia y apagada, acentos
recoloreados por variante, mugre y cuantización a 15 bits (5-5-5, como la
PlayStation) con dithering ordenado Bayer 4x4.

Uso (lo llama tools/assets/process_enemies.mjs):
    python3 recolor_texture.py ENTRADA.png SALIDA.png --hue 95 --size 64 --seed 1

--hue        tono (0-360) al que se llevan los acentos saturados (trapos,
             capas, gemas). Así cada tipo de esqueleto tiene su color.
--accent-sat saturación de esos acentos (0-1).
--darken     multiplicador de brillo global (Lunacid es oscuro).
"""
import argparse
import colorsys

import numpy as np
from PIL import Image

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0
# Tinte de las sombras: verde-azulado frío de cripta.
SHADOW_TINT = np.array([0.16, 0.2, 0.19], dtype=np.float32)
# Hueso "sucio": marfil grisáceo en vez del beige limpio de KayKit.
BONE = np.array([0.74, 0.71, 0.6], dtype=np.float32)


def rgb_to_hsv(img: np.ndarray) -> np.ndarray:
    flat = img.reshape(-1, 3)
    return np.array([colorsys.rgb_to_hsv(*p) for p in flat], dtype=np.float32).reshape(img.shape)


def hsv_to_rgb(img: np.ndarray) -> np.ndarray:
    flat = img.reshape(-1, 3)
    return np.array([colorsys.hsv_to_rgb(*p) for p in flat], dtype=np.float32).reshape(img.shape)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--size", type=int, default=64)
    ap.add_argument("--hue", type=float, default=95.0)
    ap.add_argument("--accent-sat", type=float, default=0.45)
    ap.add_argument("--darken", type=float, default=0.78)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()

    src = Image.open(args.src).convert("RGB")
    # BOX promedia cada bloque: conserva los degradados del atlas en 64 px.
    img = np.asarray(src.resize((args.size, args.size), Image.BOX), dtype=np.float32) / 255.0
    hsv = rgb_to_hsv(img)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]

    # 1) Acentos vivos (capas rojas/magenta, gemas azules/cian/violeta) → color
    #    de la variante. El cuero/madera (naranjas) y el oro (amarillos) NO:
    #    esos solo se apagan.
    red = (h < 0.02) | (h > 0.88)
    cold = (h > 0.45) & (h < 0.88)
    accent = (s > 0.45) & (v > 0.25) & (red | cold)
    h = np.where(accent, args.hue / 360.0, h)
    s = np.where(accent, np.minimum(s, args.accent_sat), s * 0.45)

    # 2) Todo más apagado y oscuro.
    v = v * args.darken
    rgb = hsv_to_rgb(np.stack([h, s, v], axis=-1))

    # 3) Hueso: tonos cálidos claros y poco saturados → marfil sucio.
    bone = (~accent) & (hsv[..., 0] > 0.04) & (hsv[..., 0] < 0.16) & (hsv[..., 2] > 0.55)
    rgb = np.where(bone[..., None], rgb * 0.35 + BONE * 0.65 * hsv[..., 2:3], rgb)

    # 4) Sombras hacia el verde-azulado de la cripta.
    lum = rgb.mean(axis=-1, keepdims=True)
    rgb = rgb + (SHADOW_TINT - rgb) * (1.0 - lum) * 0.35

    # 5) Mugre: ruido de valor determinista (se ve "pintado a mano" a 64 px).
    rng = np.random.default_rng(args.seed)
    grime = rng.normal(0.0, 0.05, size=rgb.shape[:2])[..., None]
    rgb = np.clip(rgb * (1.0 + grime), 0.0, 1.0)

    # 6) 15 bits por píxel (5-5-5) con dithering ordenado, como la PS1.
    th = np.tile(BAYER4, (args.size // 4 + 1, args.size // 4 + 1))[: args.size, : args.size][..., None]
    q = np.floor(rgb * 31.0 + th) / 31.0
    out = Image.fromarray((np.clip(q, 0.0, 1.0) * 255.0).astype(np.uint8), "RGB")
    out.save(args.dst)


if __name__ == "__main__":
    main()
