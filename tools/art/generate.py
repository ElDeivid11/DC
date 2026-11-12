"""Arte de ambiente generado con un modelo abierto que corre en la máquina
(sin cuenta ni costo) y pasado al aspecto del juego.

Genera cada imagen de tools/art/prompts.json con Stable Diffusion
(LCM Dreamshaper v7: pocos pasos, anda en CPU en ~30 s por imagen), la
reduce a la resolución de píxel del juego y le da el color de PS1 (15 bits
con trama de Bayer, como RetroView). Escribe en assets/art/.

    python3 -m venv venv && venv/bin/pip install --index-url https://download.pytorch.org/whl/cpu torch
    venv/bin/pip install diffusers transformers accelerate safetensors pillow numpy
    venv/bin/python tools/art/generate.py [--only=id,id] [--seed=N] [--raw=carpeta] [--post-only]

--only       solo esas imágenes (por id)
--seed       otra semilla (para elegir entre variantes)
--raw        guarda (o lee, con --post-only) las imágenes crudas ahí
--post-only  no genera: vuelve a pasar las crudas de --raw por el filtro

Licencias y procedencia: assets/art/README.md.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).resolve().parent / "prompts.json"
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], float) / 16.0 - 0.5


def retro(img, size, colors=0, bits=5, contrast=1.08, saturation=0.92):
    """A píxel del juego: reducir, limitar la paleta (colors > 0) y bajar a
    `bits` por canal con trama de Bayer."""
    img = img.convert("RGB").resize(tuple(size), Image.LANCZOS)
    img = ImageEnhance.Contrast(img).enhance(contrast)
    img = ImageEnhance.Color(img).enhance(saturation)
    if colors > 0:
        img = img.quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    a = np.asarray(img, float) / 255.0
    levels = 2 ** bits - 1
    h, w = a.shape[:2]
    tile = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w, None]
    a = np.clip(np.floor(a * levels + tile + 0.5), 0, levels) / levels
    return Image.fromarray((a * 255.0 + 0.5).astype(np.uint8), "RGB")


def main():
    only, seed, raw_dir, post_only = None, None, None, False
    for arg in sys.argv[1:]:
        if arg.startswith("--only="):
            only = arg.split("=", 1)[1].split(",")
        elif arg.startswith("--seed="):
            seed = int(arg.split("=", 1)[1])
        elif arg.startswith("--raw="):
            raw_dir = Path(arg.split("=", 1)[1])
        elif arg == "--post-only":
            post_only = True
    spec = json.loads(MANIFEST.read_text(encoding="utf-8"))
    jobs = [j for j in spec["images"] if only is None or j["id"] in only]
    pipe = None
    if not post_only:
        import torch
        from diffusers import DiffusionPipeline
        pipe = DiffusionPipeline.from_pretrained(spec["model"], torch_dtype=torch.float32, safety_checker=None)
        pipe.to("cpu")
        pipe.set_progress_bar_config(disable=True)
    if raw_dir:
        raw_dir.mkdir(parents=True, exist_ok=True)
    for j in jobs:
        s = seed if seed is not None else int(j.get("seed", 1))
        if post_only:
            img = Image.open(raw_dir / f"{j['id']}.png")
        else:
            import torch
            w, h = j.get("size", [768, 432])
            img = pipe(prompt=f"{j['prompt']}, {spec['style']}", num_inference_steps=int(spec.get("steps", 6)),
                       guidance_scale=float(spec.get("guidance", 8.0)), width=w, height=h,
                       generator=torch.Generator("cpu").manual_seed(s)).images[0]
            if raw_dir:
                img.save(raw_dir / f"{j['id']}.png")
        out = ROOT / j["out"]
        out.parent.mkdir(parents=True, exist_ok=True)
        retro(img, j["pixel"], int(j.get("colors", 0)), int(j.get("bits", 5))).save(out, optimize=True)
        print(f"{j['id']}: semilla {s} -> {j['out']}", flush=True)


if __name__ == "__main__":
    main()
