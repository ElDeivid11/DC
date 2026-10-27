# Kit pixel de la UI («Grimorio de la Cripta»)

Toda la UI sale de un solo atlas de pixel art generado por código. Nada se dibuja a mano en un editor: los colores vienen de `data/ui_palette.json` y las piezas de `make_ui_kit.py`, así que cambiar un color es editar el JSON y regenerar.

```
data/ui_palette.json ──► tools/ui/make_ui_kit.py ──► ui/kit/ui_atlas.png + ui/kit/manifest.json
tools/ui/src/icons_1x/*.png ┘   (Pillow, determinista)
scripts/ui/ui_style.gd (espejo de la paleta) ─┐
scripts/ui/ui_kit.gd (manifiesto → StyleBoxTexture / AtlasTexture) ─┤
                                              ▼
scripts/ui/theme_builder.gd ──(tools/build_theme.tscn)──► ui/theme_main.tres (único Theme)
```

## Regenerar

Después de tocar la paleta, el generador, la lista de íconos o el título del juego (`app.title`, que dibuja el logo):

```
python3 -I tools/ui/make_ui_kit.py [--preview=docs/capturas/ui_kit.png]
godot --headless --path . res://tools/build_theme.tscn
```

Y commitear `ui/kit/` y `ui/theme_main.tres`. Si se cambió un color de `data/ui_palette.json`, copiarlo también a la constante del mismo nombre en `scripts/ui/ui_style.gd`: `tests/unit/test_ui_kit.gd` falla si no coinciden, si el manifiesto no corresponde a la paleta o al generador actuales, o si el Theme guardado quedó viejo.

## Íconos

Los 41 íconos (30 de menús y 11 de almas: afinidades, pacto, estados y escudo) son de [game-icons.net](https://game-icons.net) (repo `github.com/game-icons/icons`), **CC BY 3.0**: hay que dar crédito (ya va en Opciones → Créditos y en el README). Licencia original: `src/LICENSE_game-icons.txt`.

- `src/icons.json`: id del juego → `autor/nombre` del SVG.
- `src/icons_svg/<autor>/*.svg`: los SVG originales.
- `src/icons_1x/<id>.png`: máscaras de 14×14 (1 bit), commiteadas. Las genera `rasterize_icons.py`, que necesita `cairosvg` y se corre solo al cambiar la lista:

```
python3 -m venv /tmp/venv_ui && /tmp/venv_ui/bin/pip install cairosvg pillow
/tmp/venv_ui/bin/python -I tools/ui/rasterize_icons.py
```

El generador pinta cada máscara en rampas de la paleta (`bronce`, `vela`, `apagado` y, según el ícono, `alma`, `moneda`, `sangre`, `amatista`), con contorno de tinta. En el juego: `UIIcon.make("mejoras", "vela")`.

| Autor | Íconos |
|---|---|
| Lorc | anvil, barbute, book-cover, broadsword, candlebright, checked-shield, clover, cog, crossed-swords, feather, flying-flag, ghost, heart-organ, hourglass, locked-chest, magic-palm, run, scroll-unfurled, standing-potion, swap-bag, treasure-map, trophy |
| Delapouite | dungeon-gate, exit-door, stairs, torch, two-coins, upgrade |
| Sbed | death-skull |
| Skoll | hearts |

Modificaciones: rasterizados a 14–16 px y recoloreados.
