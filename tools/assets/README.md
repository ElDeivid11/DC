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
