# Sprites de enemigos (pixel art estilo Dragon Quest HD-2D)

Los enemigos se dibujan como **sprites de pixel art dentro del mundo 3D**: un cuadro plano que siempre mira a la cámara, iluminado por las antorchas y con la misma niebla PSX del entorno. El cuadro cambia según la animación y hacia dónde mira el enemigo (8 direcciones). En el juego lo hace `EnemySprite` (`scripts/world/enemy_sprite.gd`, shader `shaders/enemy_sprite.gdshader`).

![El esbirro en las 8 direcciones](../../docs/capturas/esbirro_vistas.png)

**Las hojas de hoy son de prueba**, dibujadas por código con `draw_monsters.py` (abajo). El arte definitivo las reemplaza con el **mismo formato** sin tocar código. Opciones → **Enemigos** cambia entre *Pixel art* y *Modelo 3D* (desde el próximo piso; por defecto `data/balance.json → render.enemy_style_default`).

## Guía de estilo

Referencia: los remakes HD-2D de Dragon Quest I, II y III (Square Enix, 2024–2025) y el boceto del esqueleto con bufanda que pasó David (8 vistas). De los remakes: monstruos de pixel art basados en los diseños de Akira Toriyama, más nítidos y luminosos que en *Octopath Traveler*, animados, con paletas cercanas a las originales, sobre escenarios 3D con luz real. De la referencia:

- **Diseño caricaturesco y amenazante**: calavera enorme (~1/3 del alto) con grietas, cuencas hondas con ceño y una pupila que brilla, pómulos, nariz de dos agujeros y una sonrisa de dientes grandes; cuerpo flaco de huesos con nudos (codos, rodillas, rótulas), dos huesos en antebrazo y pierna, dedos en los pies.
- **Postura**: agachado, piernas abiertas y arqueadas, encorvado; arma en una mano y escudo en la otra.
- **Silueta que se lee**: una prenda de color fuerte por especie (bufanda roja del esbirro, capucha verde del ballestero, casco con cuernos del guardián, túnica morada del nigromante). Las variantes por rango o piso se tiñen en el juego (como las «paletas cambiadas» de Dragon Quest).
- **Sombreado en bandas** con luz de arriba a la izquierda: 3–5 tonos por material, sombras hacia violeta, luces hacia crema, brillo puntual en hueso y metal. Sin antialias ni tramas.
- **Contorno** de 1 px del color oscuro de cada material (no negro), y líneas interiores donde una parte pasa por delante de otra.
- **Animación** de frente al jugador en combate, con anticipación y estiramiento: el monstruo se acerca un poco al golpear (escala ~1,15) y deja una **estela blanca** del arma; al recibir un golpe retrocede y el juego lo pone blanco un instante.
- **Escala**: 64 px por metro, igual que las texturas del entorno; el esqueleto mide ~100 px.

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
	"frame": [115, 100],
	"columns": 16,
	"pivot": [60, 98],
	"pixels_per_meter": 64,
	"anims": {
		"idle":   {"loop": true,  "fps": 4.29, "dirs": {"s": [0, 1, 2, 3, 4, 5], "se": [6, 7, 8, 9, 10, 11], "e": [12, 13, 14, 15, 16, 17], "ne": [18, 19, 20, 21, 22, 23], "n": [24, 25, 26, 27, 28, 29], "nw": [30, 31, 32, 33, 34, 35], "w": [36, 37, 38, 39, 40, 41], "sw": [42, 43, 44, 45, 46, 47]}},
		"attack": {"loop": false, "fps": 8.89, "dirs": {"s": [118, 119, 120, 121, 122, 123, 124, 125]}},
		"attack_2": {"loop": false, "fps": 8.89, "dirs": {"s": [126, 127, 128, 129, 130, 131, 132, 133]}}
	}
}
```

- `frame`: tamaño de cada celda en píxeles. `columns`: celdas por fila.
- `pivot`: el punto de la celda (desde arriba a la izquierda) que va **en el piso, entre los pies**.
- `pixels_per_meter`: escala en el mundo. Con 64 (la densidad de las texturas del entorno: 128 px por celda de 2 m), el esqueleto de prueba mide unos 100 px. En combate, con el preset Clásica, 1 píxel del sprite ≈ 1 píxel de la imagen de 240 líneas.
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

```
python3 -I tools/sprites/draw_monsters.py [--only=esqueleto_esbirro] [--preview=/tmp/hoja.png]
```

`draw_monsters.py` (numpy + Pillow, determinista, ~2 min las cuatro) **dibuja cada monstruo por código**, sin modelos ni imágenes de afuera:

1. **Formas simples en 2,5D**: esferas, elipsoides, huesos (cápsulas con punta redonda, finitas o gruesas) y placas planas (hojas, escudos, la bufanda), en el espacio del personaje. Cada una tiene material y grupo.
2. **Esqueleto articulado**: `rig()` ubica pelvis, columna, hombros, codos, manos, cadera, rodillas y tobillos a partir de una pose (inclinación, giro, cabeza, mandíbula, ángulos de cada brazo y pierna, giro del arma...). `skeleton_prims()` arma encima el cuerpo de hueso (costillas sueltas sobre un interior oscuro, pelvis con alas, vértebras, radio y cúbito, tibia y peroné, dedos) y `skull_prims()` la calavera; cada monstruo suma su ropa y sus armas (`esbirro()`, `picaro()`, `guardian()`, `nigromante()`).
3. **Animaciones** = poses clave interpoladas (`keyed`) o ciclos (`breathe`, `walk_cycle`), con la estela del golpe (`smear`) en el cuadro del impacto. El monstruo se apoya solo en el piso (su punto más bajo).
4. **Render**: cada forma se rasteriza a 4x con profundidad y normal exactas; la luz (arriba a la izquierda) da el tono de la rampa de su material. Cada píxel final es el tono **más frecuente** de sus 4x4 muestras (píxeles limpios, sin mezclas), después van las líneas interiores entre partes y el contorno exterior.
5. **Hoja**: idle y walk en 8 vistas (0°, ±45°, ±90°, ±135°, 180°), el resto de frente; todo se recorta al rectángulo común y se escribe la hoja, la máscara de brillo y el JSON.

Las paletas están en `MATERIALS` (5 tonos + contorno por material) y las poses en `*_anims()`. Para probar una animación sin regenerar todo, `--only=especie --preview=...`.

La versión anterior (render de los modelos 3D pasado a pixel art) quedó en la historia del repositorio (commit `430558c`).
