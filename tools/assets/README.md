# Pipeline de assets (fuera de Godot)

Adapta assets libres (CC0) al estilo PSX/Lunacid del juego. Los resultados se
commitean en `assets/`; los packs originales NO van al repo (se bajan aparte).

Requisitos: Node 22 y Python 3 con Pillow + numpy.

```
cd tools/assets && npm ci          # una vez (node_modules está en .gitignore)
```

## Enemigos (`process_enemies.mjs`)

Fuente: **KayKit Character Pack: Skeletons 1.0** (Kay Lousberg, CC0),
<https://github.com/KayKit-Game-Assets/kaykit-character-pack-skeletons-1.0>.

```
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 https://github.com/KayKit-Game-Assets/kaykit-character-pack-skeletons-1.0 ~/kaykit-game-assets/kaykit-character-pack-skeletons-1.0
cd tools/assets && node process_enemies.mjs [ruta/al/addons/kaykit_character_pack_skeletons]
```

Por cada enemigo (tabla `ENEMIES` del script): se queda solo con las
animaciones que usa el juego, las remuestrea a 12 fps, suelda y simplifica la
malla (~40% de los triángulos), y recolorea la textura con
`recolor_texture.py` (64 px, paleta de 15 bits con trama Bayer 4x4, huesos
color marfil sucio y un acento de color por tipo). Salida:
`assets/enemies/<id>.glb` y `assets/enemies/weapons/<arma>.glb`.

El resto (escala, ojos que brillan, cabeza más chica, animación a pasos) lo
hace `scripts/world/enemy_visual.gd` en el juego, con los datos de
`data/species.json` → `visual`.

Revisión visual: `tools/enemy_preview.tscn` (ver su encabezado).

## Texturas (`make_textures.py`)

Fuente: **WRAD Textures** (wriks, CC0 1.0),
<https://github.com/wwwriks/wrad-textures>. Solo se usan fotos de `seamless/`
(1024 px, tileables). La licencia se copia sola a
`assets/textures/LICENSE_WRAD.txt`. El repo pesa cientos de MB: bajar solo lo
que se usa.

```
git clone --filter=blob:none --no-checkout https://github.com/wwwriks/wrad-textures ~/wrad-textures
cd ~/wrad-textures && git checkout HEAD -- LICENSE README.md \
    seamless/ash.png seamless/bricks1.png seamless/bricks2.png seamless/bricks3.png \
    seamless/bricks4.png seamless/bricks5.png seamless/concrete3.png seamless/planks2.png \
    seamless/planks4.png seamless/planks5.png seamless/stone2.png seamless/stone4.png \
    seamless/tiles1.png
cd -   # volver a la raíz del proyecto
python3 -I tools/assets/make_textures.py --src ~/wrad-textures --out assets/textures \
    [--preview /tmp/hoja.png] [--temas luna,abismo] [--zoom 2]
```

Salida por tema: `assets/textures/<tema>/{wall_a,wall_b,floor_a,floor_b,ceiling}.png`,
PNG RGB de 128x128 que cubre 4 m x 4 m (2x2 celdas) y repite sin costuras.
`wall_b` / `floor_b` son variantes del mismo material (ahumado, agrietado,
musgo, vetas) para ~15 % de las caras. Por textura: reducción BOX de la foto
entera (no se recorta: así sigue siendo tileable), desaturar + contraste +
aplanar la luz de la foto, mapa de degradado con la rampa del tema (75-80 %
rampa + color original), gamma buscada para que la luminancia media quede en
el objetivo del slot (paredes/piso ~0.21-0.32, techo ~0.11-0.16), capas de
ruido tileable y cuantización a 16 colores con trama Bayer 4x4. Los
parámetros de cada tema (fuentes, rampa, capas, luminancia) están en la tabla
`THEMES` del script; el encabezado explica cada paso. Es determinista: misma
entrada, mismos PNG.

| Tema | wall_a | wall_b | floor_a | floor_b | ceiling |
|---|---|---|---|---|---|
| `catacumbas` (Catacumbas del Pozo, ocre) | bricks5 + mugre | bricks5 + hollín + grietas | bricks4 | bricks4 + tierra + grietas | stone2 |
| `cisterna` (Cisterna Anegada, verde) | bricks3 | bricks3 + musgo + chorretes | concrete3 + charcos | concrete3 + musgo + grietas | bricks2 |
| `luna` (Salones de la Luna, azul plata) | bricks2 | bricks2 + hollín + escarcha + grietas | tiles1 | tiles1 + hollín + grietas | stone2 |
| `castillo` (Castillo Carmesí, granate y oro) | bricks1 + mugre | bricks1 + hollín + grietas + chorretes | planks4 | planks5 | planks2 |
| `abismo` (El Abismo, violeta y negro) | stone4 | stone4 + vetas cian | ash | ash + vetas cian | stone2 |

Después de regenerar, abrir Godot (o `godot --headless --path . --import`)
para que importe los PNG.
