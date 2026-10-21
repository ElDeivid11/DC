"""Rasteriza los íconos de game-icons.net (SVG 512x512) a máscaras 1-bit de 14x14.

Se corre UNA vez (o al cambiar la lista de tools/ui/src/icons.json): las
máscaras se commitean en tools/ui/src/icons_1x/ y el generador del kit
(make_ui_kit.py) solo necesita Pillow.

    python3 -m venv /tmp/venv_ui && /tmp/venv_ui/bin/pip install cairosvg pillow
    /tmp/venv_ui/bin/python -I tools/ui/rasterize_icons.py

Método: se quita el rectángulo de fondo del SVG, se rasteriza a 112x112 (x8),
se reduce con promedio por área (BOX) a 14x14 y se corta en cobertura >= 0,5.
Íconos: game-icons.net (CC BY 3.0, ver tools/ui/src/LICENSE_game-icons.txt).
"""
import io
import json
import re
import sys
from pathlib import Path

import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
OUT = SRC / "icons_1x"
SIZE = 14
OVERSAMPLE = 8
THRESHOLD = 0.5
BG_RECT = re.compile(r'<path d="M0 0h512v512H0z"\s*/>')


def mask(svg_path: Path) -> Image.Image:
    svg = BG_RECT.sub("", svg_path.read_text(encoding="utf-8"))
    big = SIZE * OVERSAMPLE
    png = cairosvg.svg2png(bytestring=svg.encode("utf-8"), output_width=big, output_height=big)
    alpha = Image.open(io.BytesIO(png)).convert("RGBA").getchannel("A")
    small = alpha.resize((SIZE, SIZE), Image.Resampling.BOX)
    cut = int(255 * THRESHOLD)
    return small.point(lambda v: 255 if v >= cut else 0)


def main() -> int:
    icons = json.loads((SRC / "icons.json").read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    for icon_id, rel in sorted(icons.items()):
        svg = SRC / "icons_svg" / (rel + ".svg")
        if not svg.exists():
            print("falta", svg, file=sys.stderr)
            return 1
        mask(svg).save(OUT / (icon_id + ".png"))
    print("máscaras:", len(icons), "→", OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
