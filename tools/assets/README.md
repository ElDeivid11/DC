# Pipeline de assets (fuera de Godot)

Adapta assets libres (CC0) al estilo PSX/Lunacid del juego. Los resultados se
commitean en `assets/`; los packs originales NO van al repo (se bajan aparte).

Requisitos: Node 22 y Python 3 con Pillow + numpy. Los enemigos además
necesitan Blender como módulo de Python (`bpy`, ver abajo).

```
cd tools/assets && npm ci          # una vez (node_modules está en .gitignore)
```

## Enemigos (`build_skeletons.py` + `process_enemies.mjs`)

Un esqueleto humano **realista** (no "chibi") con skinning rígido estilo PS1,
animado con el rig y las bibliotecas de animación de Quaternius. Todas las
fuentes son CC0; las licencias y de qué copia/commit sale cada archivo están
en `assets/enemies/LICENSE_*.txt`.

| Fuente | Qué se usa | De dónde (copia usada) |
|---|---|---|
| **Skeleton - Realistic**, Paul Kotelevets (Blender Studio, *Human Base Meshes* v1.4.1), CC0 | la malla (135 piezas, 66k triángulos, sin rig ni textura) | bundle oficial en <https://www.blender.org/download/demo-files/#asset-bundles>; copia usada: `beldenge/diamondback` @ `3e582c7eecdef16867fb52ccc3c7a2947e5a1eaa`, `src/reimagined/models/sources/blender-skeleton/skeleton-realistic.blend` (sha256 `f54a3ee1…46eeb7`) |
| **Universal Animation Library 2** [Standard], Quaternius, CC0 | el rig de 65 huesos (estilo Unreal: `root`, `pelvis`, `spine_01`…, `Head`, `hand_r`…) y animaciones | `agentkaerf/FreeModels` @ `db3df04d1e4714298a09510b26fb6de6645138a2`, `Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb` |
| **Universal Animation Library** [Standard] (la 1), Quaternius, CC0 | más animaciones (mismo rig) | `IAFahim/quaternius.universalAnimationLibrary.standard` @ `8456155dbae7eb861f553a2341871ccae633c857`, `UAL1_Standard.fbx` |
| **Modular Character Outfits - Fantasy** [Standard], Quaternius, CC0 | capucha, chaqueta y mangas del nigromante (`Male_Ranger`) | `agentkaerf/FreeModels` @ `db3df04…`, `Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/` |
| **KayKit Character Pack: Skeletons 1.0**, Kay Lousberg, CC0 | solo las **armas** (`assets/enemies/weapons/`) | <https://github.com/KayKit-Game-Assets/kaykit-character-pack-skeletons-1.0> |

Quaternius anunció una licencia propia (QAL) para lanzamientos futuros: las
copias de arriba (y sus archivos de licencia) dicen CC0 1.0. Si se vuelven a
bajar, usar esos commits y releer la licencia.

### Bajar las fuentes (una vez; no van al repo)

Clones parciales (solo lo que se usa):

```
mkdir -p ~/fuentes && cd ~/fuentes
git clone --depth 1 --filter=blob:none --no-checkout https://github.com/agentkaerf/FreeModels
(cd FreeModels && git fetch --depth 1 origin db3df04d1e4714298a09510b26fb6de6645138a2 && \
 git checkout db3df04d1e4714298a09510b26fb6de6645138a2 -- \
   "Universal Animation Library 2[Standard]" \
   "Modular Character Outfits - Fantasy[Standard]/License_Standard.txt" \
   "Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits")
git clone --depth 1 https://github.com/IAFahim/quaternius.universalAnimationLibrary.standard ual1
git clone --depth 1 --filter=blob:none --no-checkout https://github.com/beldenge/diamondback
(cd diamondback && git fetch --depth 1 origin 3e582c7eecdef16867fb52ccc3c7a2947e5a1eaa && \
 git checkout 3e582c7eecdef16867fb52ccc3c7a2947e5a1eaa -- src/reimagined/models/sources/blender-skeleton)
```

En vez de la copia de `diamondback` sirve el `.blend` del bundle oficial de
Blender (la colección se busca por nombre, `--collection "Skeleton - Realistic"`).

### Blender como módulo (`bpy`)

`bpy` 5.2 (el de PyPI necesita Python 3.13):

```
python3.13 -m venv ~/venv_bpy && ~/venv_bpy/bin/pip install bpy==5.2.2
```

### Comandos

```
# 1) Cuerpos, rig y animaciones (Blender, ~1 min). Intermedios en tools/assets/.work/
~/venv_bpy/bin/python -I tools/assets/build_skeletons.py \
    --skeleton ~/fuentes/diamondback/src/reimagined/models/sources/blender-skeleton/skeleton-realistic.blend \
    --ual2 "$HOME/fuentes/FreeModels/Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb" \
    --ual1 ~/fuentes/ual1/UAL1_Standard.fbx \
    --outfits "$HOME/fuentes/FreeModels/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits" \
    --out tools/assets/.work
# 2) Un .glb por enemigo en assets/enemies/ (Node + Python)
cd tools/assets && node process_enemies.mjs [--work .work] [--kaykit <pack>/addons/kaykit_character_pack_skeletons]
cd ../.. && godot --headless --path . --import
```

**Paso 1, `build_skeletons.py`** (ver su encabezado), por variante (`esqueleto`
para las tres especies comunes y `nigromante`):

- Saca la subdivisión y **decima** las 135 piezas a ~3.300 triángulos.
- Escala el esqueleto al alto del maniquí de UAL2 (×0,97) y **encaja cada
  miembro en las articulaciones del rig**: húmero/fémur giran sobre el hombro o
  la cadera y se estiran hasta el codo/rodilla del rig; radio+cúbito y
  tibia+peroné se llevan al codo/rodilla, se orientan y se estiran hasta la
  muñeca/tobillo; la mano se gira para que palma y dedos coincidan con `hand_*`.
  Así los pivotes del rig caen en las articulaciones de la malla (y el arma
  queda en el puño).
- **Skinning rígido** (PS1): cada pieza entera al hueso que le corresponde por
  nombre (`proximal.index.L` → `index_01_l`, `leg_tibula.R` → `calf_r`...); las
  vértebras, al segmento de hueso más cercano.
- UV nuevas (smart project) y horneado con Cycles de **oclusión ambiental** y
  **altura** (`<variante>_ao.png`, `_height.png`).
- **Ojos**: dos esferitas (malla `Skeleton_Eyes`) en el centro de cada órbita,
  que se busca con un mapa de profundidad del cráneo (hueco entre ceja y pómulo).
- Nigromante: capucha, chaqueta y mangas del `Male_Ranger` (sus proporciones
  se ajustan al reposo de UAL2 antes de pasarle el skinning; se decima al 20%),
  más una **falda cónica** generada hasta los tobillos (doble cara, pesos de
  pelvis a piernas). Se borran las piezas del esqueleto que tapa la ropa.
- Pasa `UAL1_Standard.fbx` a `ual1_anims.glb` (a 30 fps: así queda en el FBX).
  Las rotaciones locales de sus huesos son las mismas que las de UAL2; solo el
  nodo `Armature` viene girado 180°, y el paso 2 no copia sus canales.

**Paso 2, `process_enemies.mjs`**, por enemigo (tabla `ENEMIES`: base, colores):

- Arma **solo los clips que pide `data/species.json` → `visual.anims`** de esa
  especie, según la tabla `CLIPS` (de qué biblioteca sale cada uno; se pueden
  encadenar clips o sacar una pose quieta). Los nombres finales no terminan en
  `_Loop`: el importador de Godot se los saca.
- Remuestrea todo a **12 fps exactos** (el juego avanza de a 1/12 s) y saca los
  canales que nunca se mueven del reposo.
- Texturas con `skeleton_textures.py`: **hueso de 128 px** (oclusión + altura
  + paleta por especie: hueso, sombra de las uniones, manchas) y la **túnica**
  (atlas del Ranger re-pintado a 128 px). 15 bits con trama Bayer 4x4.

| Especie | Cuerpo (tris) | Hueso | Arma | idle / combat / walk | attack | otros |
|---|---|---|---|---|---|---|
| esbirro | 3.283 + 40 ojos | marfil amarillento, moho | `hoja` | `Zombie_Idle` / `Sword_Idle` / `Zombie_Walk` | `Sword_Attack`, `Zombie_Scratch` | |
| ballestero | 3.283 + 40 | gris frío | `ballesta` | `Idle` / `Pistol_Idle` / `Walk` | `Pistol_Shoot` | |
| guardián | 3.283 + 40 | tostado, óxido | `hacha` + `escudo` | `Shield_Idle` / `Shield_Idle` / `Walk_Formal` | `Sword_Attack`, `Shield_OneShot` | hit: `Sword_Block`, `Hit_Chest` |
| nigromante | 1.937 + 1.858 túnica + 40 | ceniza | `baculo` | `Torch_Idle` / `Torch_Idle` / `Walk_Formal` | `Spell_Shoot`, `Spell_Cast_Full` | ability `OverhandThrow`, taunt `Idle_Rail_Call` |

Todos: hit `Hit_Chest`/`Hit_Head`, death `Death01`, spawn `LayToIdle` (se
levanta del piso), dormant `Floor_Pose` (primer cuadro de `LayToIdle`).

Las **armas** siguen siendo las de KayKit (procesadas como antes con
`recolor_texture.py`; solo se rehacen con `--kaykit`). En el juego cuelgan de
`hand_r`/`hand_l` con un montaje por especie (`visual.weapon_r_mount`:
posición, rotación y escala en el espacio del hueso). Para calcular una
rotación que deje el arma de cierta forma en una pose, se puede leer la pose
del hueso con un script de Godot (`get_bone_global_pose`) y despejar
`hueso⁻¹ · orientación_deseada`.

El resto (escala, ojos que brillan, animación a pasos, luz propia) lo hace
`scripts/world/enemy_visual.gd` con los datos de `data/species.json` → `visual`.

Revisión visual: `tools/enemy_preview.tscn` (ver su encabezado: papel,
cuadro congelado, cámara cerca/cara y una sola especie).

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
