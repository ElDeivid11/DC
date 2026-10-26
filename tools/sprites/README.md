# Sprites de enemigos (pixel art de píxel gordo)

Los enemigos se dibujan como **sprites de pixel art dentro del mundo 3D**: un cuadro plano que siempre mira a la cámara, con la misma niebla PSX del entorno. El cuadro cambia según la animación y hacia dónde mira el enemigo (hasta 8 direcciones). En el juego lo hace `EnemySprite` (`scripts/world/enemy_sprite.gd`, shader `shaders/enemy_sprite.gdshader`).

![El esbirro: frente, perfil, espalda, tajo, escudazo, calavera que salta y dormido](../../docs/capturas/esbirro_vistas.png)

**Las hojas de hoy son de prueba**, hechas por código (abajo): el **esbirro** ya está en el estilo elegido (pixel art grueso, `draw_esbirro.py`); los demás siguen con el generador anterior (`draw_monsters.py`) hasta que David confirme el estilo. El arte definitivo las reemplaza con el **mismo formato** sin tocar código. Opciones → **Enemigos** cambia entre *Pixel art* y *Modelo 3D* (desde el próximo piso; por defecto `data/balance.json → render.enemy_style_default`).

## Guía de estilo

Referencia: las capturas que pasó David de shooters retro con monstruos de sprite (bichos simpáticos de pocos píxeles sobre un mundo 3D) y el boceto del esqueleto con bufanda (8 vistas). La idea es un **contraste duro entre el entorno y el enemigo**: el mundo es 3D, con texturas, trama y luz; el enemigo es **pixel art grueso y plano**.

- **Píxeles gordos**: el sprite es chico (el esqueleto, ~38 px de alto) y se ve grande: a 24 px por metro, cada píxel del sprite mide unos 4 cm en el mundo, el triple que un texel del entorno (64 px/m). Ese salto de tamaño de píxel es el contraste.
- **Pocos colores y contorno negro**: 2–3 tonos por material (hueso claro, sombra y sombra profunda; rojo y rojo oscuro...), contorno de 1 px casi negro alrededor de cada parte. Sin degradés, sin antialias, sin tramas.
- **Simpático y con carácter**: calavera enorme (~1/3 del alto) con ceño, pupilas que brillan (máscara `glow`), nariz y una sonrisa de dientes; cuerpo chiquito de huesos de 1–2 px. Una prenda de color fuerte por especie (bufanda roja del esbirro, capucha verde del ballestero, casco con cuernos del guardián, túnica morada del nigromante).
- **Luz pareja** (`flat_light`): todo el cuadro recibe la misma luz (ambiente del bioma + antorchas y lámpara cercanas, con su parpadeo) y toma solo parte de su color (`enemies.sprite_flat_tint`): cada color queda plano y el monstruo conserva su paleta en cualquier bioma. Un poco de luz propia (`self_light`) para que se recorte en la oscuridad.
- **Animación de 8/16 bits**: pocos cuadros, todo se mueve de a píxeles enteros (nada se rota ni se escala). Anticipación y golpe claros, **estela blanca** del arma en el tajo, un destello en el escudazo; al recibir un golpe retrocede (o se le salta la calavera) y el juego lo pone blanco un instante; al morir se desarma en un montón de huesos.

## Formato de una hoja (para el arte definitivo)

Por especie, tres archivos en `assets/sprites/enemies/` y la ruta del JSON en `data/species.json → <especie>.visual.sprite`:

| Archivo | Qué es |
|---|---|
| `<especie>.png` | Hoja RGBA: todos los cuadros en una grilla de celdas iguales, de izquierda a derecha y de arriba abajo. Fondo transparente. El alfa se corta a 0,5 (sin semitransparencias). |
| `<especie>_glow.png` | Opcional, mismo tamaño: blanco donde el sprite **brilla** (los ojos). Esos píxeles se pintan con el color de ojos del enemigo (cambia por rango, élite o jefe), sin luz ni niebla. |
| `<especie>.json` | Cómo leer la hoja (ver abajo). |

```json
{
	"version": 1,
	"sheet": "esqueleto_esbirro.png",
	"glow": "esqueleto_esbirro_glow.png",
	"frame": [101, 120],
	"columns": 16,
	"pivot": [59, 114],
	"pixels_per_meter": 64,
	"anims": {
		"idle":   {"loop": true,  "fps": 4.29, "dirs": {"s": [0, 1, 2, 3, 4, 5], "e": [6, 7, 8, 9, 10, 11], "n": [12, 13, 14, 15, 16, 17]}},
		"attack": {"loop": false, "fps": 8.89, "dirs": {"s": [48, 49, 50, 51, 52, 53, 54, 55]}},
		"attack_2": {"loop": false, "fps": 8.89, "dirs": {"s": [56, 57, 58, 59, 60, 61, 62, 63]}}
	}
}
```

- `frame`: tamaño de cada celda en píxeles. `columns`: celdas por fila.
- `pivot`: el punto de la celda (desde arriba a la izquierda) que va **en el piso, entre los pies**.
- `pixels_per_meter`: escala en el mundo. 64 es la densidad de las texturas del entorno (128 px por celda de 2 m); el esbirro usa 24 para que sus píxeles se vean el triple de gordos (~38 px para 1,6 m).
- `flat_light` (opcional, `false`): luz pareja, todo el cuadro con la misma luz (ver la guía de estilo). Sin esto, cada píxel lo ilumina la escena como a un HD-2D.
- `self_light` (opcional): luz propia del sprite (0–1); si falta, `data/balance.json → enemies.sprite_self_light`. En combate, con el preset Clásica, 1 píxel del sprite ≈ 1 píxel de la imagen de 240 líneas.
- `anims`: una entrada por **papel** de `species.json → visual.anims` (los mismos nombres). Si un papel tiene variantes (por ejemplo dos ataques), van como `attack`, `attack_2`, `attack_3`... y el juego elige una al azar.
  - `loop`: `true` en `idle`, `combat`, `walk` y `dormant`; `false` en el resto (al terminar vuelven solos a la anterior; `death` queda en su último cuadro).
  - `fps`: cuadros por segundo. La duración (cuadros / fps) importa: el combate espera a que termine el ataque o el golpe.
  - `dirs`: índices de cuadros por dirección (hacia dónde mira el enemigo respecto de la cámara): `s` de frente (obligatoria), `se` tres cuartos a la derecha de la pantalla, `e` de perfil a la derecha, `ne` de espaldas a la derecha, `n` de espaldas, y `nw`, `w`, `sw` del otro lado. El juego usa la más cercana que haya, contando las espejadas (`w` sale de `e` espejado, `sw` de `se`...): alcanza con `s`, `se`, `e`, `ne` y `n`, o incluso solo `s`, `e` y `n`. En combate el enemigo siempre está de frente: alcanza con `s` en todo salvo `idle` y `walk`, que se ven mientras deambula.

| Papel | Cuándo se ve | Direcciones |
|---|---|---|
| `idle` | Quieto, explorando | las 8 (o 5 con espejo) |
| `walk` | Caminando (un paso = 0,2 s) | las 8 (o 5 con espejo) |
| `combat` | En guardia durante el combate | s |
| `attack` (+ variantes) | Ataca | s |
| `hit` (+ variantes) | Recibe un golpe (además, el juego lo pone blanco un instante) | s |
| `death` | Muere (después se hunde en el piso) | s |
| `dormant` | Dormido: un montón de huesos en el piso | s |
| `spawn` | Se levanta al despertarse o al empezar el combate | s |
| `taunt`, `ability` | Solo el jefe: se burla al empezar; habilidad especial | s |

El estilo, en la guía de arriba. `tests/unit/test_sprites.gd` revisa que cada papel tenga su animación, que los índices estén dentro de la hoja y que haya dirección `s`. Para mirar una hoja nueva sin jugar:

```
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
    res://tools/sprites/sprite_preview.tscn -- --out=/tmp/sprites.png [--role=walk]
```

(una fila por especie, mirando a la cámara, a la derecha, de espaldas y a la izquierda). Las celdas pueden tener cualquier tamaño; conviene recortarlas al rectángulo que usa la animación más ancha, como hace el generador.

Después de copiar PNG nuevos: `godot --headless --path . --import` y, en los `.png.import` nuevos, `detect_3d/compress_to=0` (si no, Godot los comprime al usarlos en 3D y se ensucia el píxel).

## Cómo se generan las hojas de prueba

### El esbirro: pixel art grueso, píxel por píxel

```
python3 -I tools/sprites/draw_esbirro.py [--preview=/tmp/esbirro.png]
```

`draw_esbirro.py` (numpy + Pillow, determinista, menos de 1 s) arma cada cuadro con **sellos dibujados a mano en ASCII** (un carácter por píxel, la paleta arriba del archivo):

1. **Sellos**: calavera de frente, de perfil y de espaldas; mandíbula; tórax (con esternón, de perfil y con columna y omóplatos); pelvis; bufanda (vuelta al cuello y tres cuadros de las puntas al viento); escudo (frente, dorso con correa y tirado en el piso); espada (en diagonal, vertical y horizontal; las demás direcciones salen espejando); pies y manos. Los huesos de brazos y piernas son **líneas de píxeles** entre hombro-codo-mano y cadera-rodilla-tobillo.
2. **Contorno**: cada parte lleva su borde de 1 px casi negro y se apila en orden (lo de adelante tapa a lo de atrás con su contorno).
3. **Poses**: un diccionario con dónde va cada parte, en píxeles enteros respecto del piso (`FRONT`, `SIDE`, `GUARD`, el montón `PILE`). Las animaciones son listas de poses armadas con ayudas chicas: `bob` (agacharse), `shift` (correr partes), `lift` (levantar un pie), `jaw_open`. La vista de espaldas es la pose de frente espejada con los sellos de atrás; de perfil, lo del lado lejano va un tono más oscuro. La estela del tajo es una medialuna de píxeles (`crescent`).
4. **Hoja**: idle y walk de frente (`s`), de perfil (`e`; el juego espeja `w`) y de espaldas (`n`); el resto de frente. Escribe `flat_light`, `self_light` y `pixels_per_meter` en el JSON.

Para retocar un sello, editar el ASCII y volver a correr el script: no hace falta tocar nada más.

### Las demás especies (generador anterior)

```
python3 -I tools/sprites/draw_monsters.py [--only=esqueleto_picaro] [--preview=/tmp/hoja.png]
```

`draw_monsters.py` (numpy + Pillow, determinista, ~1,5 min las tres) arma el ballestero, el guardián y el nigromante con formas en 2,5D (se ven más «modelo» que pixel art; pasan al estilo del esbirro cuando David lo confirme):

1. **Formas simples en 2,5D**: esferas, elipsoides, huesos (cápsulas con punta redonda, finitas o gruesas) y placas planas (hojas, escudos, la bufanda), en el espacio del personaje. Cada una tiene material y grupo.
2. **Esqueleto articulado**: `rig()` ubica pelvis, columna, hombros, codos, manos, cadera, rodillas y tobillos a partir de una pose (inclinación, giro, cabeza, mandíbula, ángulos de cada brazo y pierna, giro del arma...). `skeleton_prims()` arma encima el cuerpo de hueso (costillas sueltas sobre un interior oscuro, pelvis con alas, vértebras, radio y cúbito, tibia y peroné, dedos) y `skull_prims()` la calavera; cada monstruo suma su ropa y sus armas (`picaro()`, `guardian()`, `nigromante()`).
3. **Animaciones** = poses clave interpoladas (`keyed`) o ciclos (`breathe`, `walk_cycle`), con la estela del golpe (`smear`) en el cuadro del impacto. El monstruo se apoya solo en el piso (su punto más bajo).
4. **Render**: cada forma se rasteriza a 4x con profundidad y normal exactas; la luz (arriba a la izquierda) da el tono de la rampa de su material. Cada píxel final es el tono **más frecuente** de sus 4x4 muestras (píxeles limpios, sin mezclas), después van las líneas interiores entre partes y el contorno exterior.
5. **Hoja**: idle y walk en 8 vistas (0°, ±45°, ±90°, ±135°, 180°), el resto de frente; todo se recorta al rectángulo común y se escribe la hoja, la máscara de brillo y el JSON.

Las paletas están en `MATERIALS` (5 tonos + contorno por material) y las poses en `*_anims()`. Para probar una animación sin regenerar todo, `--only=especie --preview=...`.

La versión anterior (render de los modelos 3D pasado a pixel art) quedó en la historia del repositorio (commit `430558c`).
