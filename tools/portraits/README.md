# Retratos (héroes y objetos)

## Héroes: pixel art por capas

Los retratos de los héroes son **pixel art grueso** (como los enemigos),
48x48, de frente, armados en el juego por capas según la apariencia que se
elige en el Hub → Héroes (`HeroPortrait`, `scripts/ui/hero_portrait.gd`).

```
python3 -I tools/portraits/draw_hero_parts.py [--preview=/tmp/heroes.png]
```

`draw_hero_parts.py` (numpy + Pillow, determinista) dibuja cada opción de
cada parte (cara, ojos, boca, marca, pelo, barba, tocado, ropa) con
**materiales** en vez de colores (piel, pelo, ojos, ropa, capa y fijos como
cuero, metal o la piel de oso, en tres tonos, más la tinta del contorno):
formas por máscaras sombreadas con luz de arriba a la izquierda y detalles a
mano en ASCII, cada capa con su contorno de 1 px. Escribe
`assets/portraits/heroes/partes.png` (cada píxel guarda material en R / 16 y
tono en G / 80) y `partes.json` (por parte, sus opciones y de cada una sus
capas: rectángulo del atlas y posición en el retrato; el orden de las capas;
y qué tocados esconden el pelo). `--preview` arma retratos de muestra con la
misma cuenta que el juego.

En el juego, `HeroPortrait` pinta cada capa con las paletas de
`data/apariencia.json` (nombres de las opciones, colores de piel, pelo,
ojos, ropa y capa, y los fijos) y lo entrega a escala entera (96 = ×2, 192 =
×4) o, en huecos de menos de 48 px (HUD, tarjetas de combate, listas),
recortado alrededor de la cara: el píxel nunca se achica. La apariencia de
arranque de cada héroe está en `balance.json → party[].apariencia`; la
elegida, en `MetaState.heroes`. `DataRegistry` revisa que las opciones de
`apariencia.json` sean las mismas (ids y orden) que las piezas dibujadas.

Para sumar una opción: dibujarla en `draw_hero_parts.py` (en su lista de la
parte), correr el script y agregar su nombre en `apariencia.json`.

## Objetos: render 3D con filtro PS1

Retratos de objetos de 64x64 en estilo "render 3D con filtro PS1", con fondo
transparente y contorno oscuro de 1 px:

- `assets/portraits/items/<id>.png`: RGBA, 64x64, alfa binaria (ids de `data/items.json`).

El juego solo usa los PNG. Los modelos de `tools/portraits/models/` los
carga únicamente la herramienta de horneado. (Los héroes también salían de
acá, como render de los personajes de KayKit Adventurers; eso quedó en la
historia del repositorio.)

## Regenerar

```
# 1. (Solo si cambian los modelos) bajar los packs y recortar los modelos.
#    Las dependencias de Node son las de tools/assets (cd tools/assets && npm ci).
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --filter=blob:none --no-checkout \
    https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 ADV
(cd ADV && git checkout HEAD -- LICENSE.txt addons/kaykit_character_pack_adventures/Characters/gltf)
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --filter=blob:none --no-checkout \
    https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0 HAL
(cd HAL && git checkout HEAD -- LICENSE.txt addons/kaykit_halloween_bits/Assets/gltf)
node tools/portraits/prepare_models.mjs \
    --adventures=ADV/addons/kaykit_character_pack_adventures \
    --halloween=HAL/addons/kaykit_halloween_bits
godot --headless --path . --import

# 2. Hornear (necesita display: Xvfb; con --headless no renderiza).
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
    res://tools/portraits/bake_portraits.tscn [-- --only=bjorn,venda --preview=/tmp/hoja.png --debug]
```

`prepare_models.mjs --candidatos` exporta además Rogue, Mage y Knight para
comparar opciones. `bake_portraits.tscn` escribe una hoja de contacto (todo
x3 con nearest y, abajo, los objetos a tamaño real sobre una ranura oscura) en
la ruta de `--preview` (por defecto `user://portraits_preview.png`; la ruta
completa sale en la consola). `--debug` imprime las franjas del atlas que usa
cada malla.

## Cómo se hornea (`bake_portraits.gd`)

1. Un `SubViewport` por retrato (mundo propio, fondo transparente, sin MSAA)
   a 4x el tamaño final.
2. Materiales PSX del juego (`FloorBuilder.make_psx_material`: sombreado por
   vértice, snapping, afín) con la textura original; snapping proporcional al
   tamaño final, como el preset "clasico". Solo permutaciones de shader ya
   horneadas en `addons/psx/shaders/cache` (otra combinación escribiría un
   archivo nuevo en el addon: el script lo avisa con un error).
3. Luz: clave cálida de antorcha `#ffc98a` del lado derecho, relleno frío
   `#3a4d7a` tenue del izquierdo y ambiente bajo `#2a221c`. Niebla lejos
   (`FloorBuilder.set_fog(50, 100)`).
4. Post-proceso sobre la `Image`: reducción por caja (promedio
   premultiplicado), alfa binaria, fondo de catacumba (degradé radial
   `#3b2f25` → `#120e0b` con viñeta) en los héroes, trama Bayer 4x4 a 15 bits
   (31 niveles, umbral Bayer/16, igual que `shaders/psx_viewport_dither.gdshader`)
   y, en los objetos, contorno `#0a0806` en los píxeles transparentes vecinos
   (4 direcciones) a opacos.
5. Objetos: encuadre exacto con los vértices proyectados (`fill` = fracción
   del cuadro que ocupa la silueta; la poción menor ocupa menos que la mayor).

Recoloreo: los modelos KayKit usan un atlas de 8x4 franjas de degradé. En la
tabla del script, `swaps` copia otra franja del mismo atlas y `tints` pinta una
franja de un color conservando su degradé; siempre sobre una copia de la
textura, nunca sobre los archivos.

## Qué modelo va en cada retrato

Todos los packs son de Kay Lousberg (www.kaylousberg.com), **CC0 1.0**
(licencias copiadas en `assets/portraits/LICENSE_KayKit_*.txt`).

| Retrato | Modelo | Pack | Ajustes |
|---|---|---|---|
| `items/pocion_menor` | `bottle_C_green.gltf.glb` | Dungeon Remastered 1.0 (`addons/kaykit_dungeon_remastered`) | Vidrio: franja verde → roja. Ocupa el 66 % del cuadro (más chica). |
| `items/pocion_mayor` | `bottle_A_labeled_brown.gltf.glb` | Dungeon Remastered 1.0 | Botella alta con etiqueta; líquido → carmesí/magenta. Ocupa el 90 %. |
| `items/antorcha_vieja` | `torch.gltf.glb` + llama de dos prismas | Dungeon Remastered 1.0 + primitivas | Mango más grueso, madera envejecida; llama sin sombrear como las antorchas del juego. En diagonal. |
| `items/venda` | primitivas | — (propio) | Rollo de lino (cilindros de 10 lados con textura de trama por código), tira suelta con sangre seca. |
| `items/sello_retiro` | primitivas | — (propio) | Pergamino enrollado con cinta y sello de lacre rojo. |
| `items/bomba_humo` | primitivas | — (propio) | Bomba redonda de hierro, mecha con chispa y tres bocanadas de humo. (Se probó `smokebomb` de Adventurers: a 64 px no se leía como bomba.) |
| `items/amuleto_hueso` | `bone_A.gltf` → `models/bone_a.glb` + cordón (toro) + chispa | Halloween Bits 1.0 + primitivas | Hueso colgado de un cordón de cuero, con una chispa del color de las almas (`UIStyle.SOUL`). |
| `items/talisman_hueso` | `skull.gltf` → `models/skull.glb` + dos brasas | Halloween Bits 1.0 + primitivas | Cráneo con brasas en las cuencas (+1 ataque). |

Fuentes exactas:

- KayKit Character Pack: Adventurers 1.0 —
  <https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0>
  (commit `672074b73ba276876a19e8816ecdc5241817ab47`), `Characters/gltf/`.
- KayKit Halloween Bits 1.0 —
  <https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0>
  (commit `6dc69bf6b2fa766a985754f35ec6a0324090e6c6`), `Assets/gltf/`.
- KayKit Dungeon Remastered 1.0 — ya en el repo, `addons/kaykit_dungeon_remastered/`.

## Elena: por qué Rogue con capucha

Se compararon Rogue con capucha, Rogue sin capucha y Mage con el mismo
encuadre. La capucha índigo contrasta con el fondo ocre y con el gorro de oso
de Bjorn (siluetas y colores bien distintos incluso a 1x), deja la cara entera
a la vista y sugiere lo ágil (pícara) y lo arcano (color). Sin capucha, el
pelo cobrizo se pierde contra el fondo cálido; a la Mage el sombrero no entra
en un retrato de cabeza y hombros.
