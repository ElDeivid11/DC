# Estado técnico — roguelike jugable de punta a punta

Complemento técnico de `CLAUDE.md` (reglas) y `docs/GUIA_CLAUDE_CODE.md` (plan por fases). Actualizado al terminar las fases 0–9 de la guía y la etapa "enemigos + estilo Lunacid" (19-oct-2026).

> `docs/PLAN_DE_DISENO_ROGUELIKE.md` y `docs/archive/` todavía no están en el repo.

## Verificación

```
tools/verify.sh
```

Corre import, lint, arranque (`--quit-after 120`), 52 tests unitarios y el smoke test. Todo pasa con **cero errores y cero warnings**: los warnings de GDScript se suben a error con un `override.cfg` temporal, porque fuera del editor Godot no los imprime. Godot 4.7.2 headless; en este entorno el comando es `godot`.

Capturas de pantalla reales (OpenGL por software sobre Xvfb):

```
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
  res://tools/screenshot.tscn -- --scene=res://scenes/Hub.tscn --out=/tmp/hub.png --frames=60 --demo
```

## Flujo de escenas

```
Boot.tscn ─(errores de datos → pantalla de error)─▶ Hub.tscn ──[Iniciar]──▶ Run.tscn (piso N)
                                                       ▲                      │  bajar = advance_floor() + recargar Run.tscn
                                                       │                      ▼
                                                RunSummary.tscn ◀── muerte / retiro / victoria / abandono
```

Todo cambio de escena pasa por `SceneRouter.goto()`, con un fundido a negro de unos 180 ms.

## Autoloads (orden de `project.godot`)

| Autoload | Qué hace |
|---|---|
| `EventBus` | Señales globales: `run_started`, `run_ended`, `floor_reached`, `combat_started`, `enemy_killed`, `boss_defeated`, `fled_combat`, `soul_acquired`, `item_picked`, `item_used`, `coins_changed`, `unlock_earned`, `settings_changed`, `hud_message`. |
| `DataRegistry` | Carga y **valida** `data/*.json`: tipos, referencias cruzadas y JSON roto con archivo y línea. Normaliza los números (los de JSON llegan como float). Expone `get_species/soul/item/upgrade/unlock/floor`, `bal("a.b")`, `stats_for_rank()`, `make_soul()` y `t("clave", [args])` para los textos. |
| `MetaState` | Estado **persistente**: monedas, mejoras, desbloqueos, bestiario, contadores de progreso, estadísticas y ajustes. Durante la run nadie lo escribe. |
| `SaveSystem` | `user://save.json` con escritura atómica (`.tmp` + rename), copia `.bak`, `version` y migraciones paso a paso (hoy hay una, v0→v1). Si el guardado es de una versión más nueva, queda en solo lectura. |
| `GameState` | Estado de la **run**: equipo (HP actual, almas, capacidad), inventario, piso, semilla y rng, monedas desglosadas, kills, especies vistas, objetos usados, huidas y jefes. `snapshot()` alimenta las recompensas. |
| `Controls` | Registra por código las acciones de juego (teclado y mando) y arma los textos de Opciones → Controles. |
| `SceneRouter` | Fundidos entre escenas y blips de UI generados por código (`play_ui("hover"/"click"/"error"/"coin")`). |
| `DebugTools` | Panel F1, flags de debug (`force_soul_drop`, `force_surprise`, `god_mode`, `one_hit`, `fixed_seed`) y log de eventos en `user://debug.log`. Solo en builds de debug. |

**Regla de oro**: `GameState` nunca escribe en `MetaState`. Al terminar, `RunSummary` llama a `RunRewards.compute(snapshot, MetaState)` (función pura) y aplica el resultado **una sola vez** con `MetaState.apply_run_result()`, y después autoguarda. El flag `GameState.result_applied` evita aplicarlo dos veces.

## Datos (`data/`)

| Archivo | Contenido |
|---|---|
| `species.json` | Especies: rango base, `rank_range` (rangos en los que aparece), `tier` (basico/elite/jefe), `peso` (sorteo), `dormant_chance`, `soul_id`, familia, descripción y el bloque `visual` (modelo, escala, cabeza/manos, armas, color de ojos, luz propia y qué animación usar para cada papel). `"activo": false` la saca del juego (los goblins, sin licencia). |
| `souls.json` | Plantillas de alma: `active{name}`, `passive{name, description, effect{type, value}}` o `null`, y `stat_modifiers`. Incluye las 5 almas de jefe con las pasivas nuevas. |
| `items.json` | 8 objetos: `nombre`, `descripcion`, `tipo` (consumible/pasivo), `efecto{tipo, valor, en_combate, fuera_combate}`, `peso_aparicion`, `unlock_id`. |
| `unlocks.json` | Condiciones: `condicion{tipo, parametros}`, `recompensa` (id de objeto) y `oculto`. |
| `upgrades.json` | Mejoras: `efecto{tipo, valor}` (el valor puede ser fraccionario; el total se redondea), `coste_base` y `max_nivel`. |
| `floors.json` | Generación (tamaño de salas, densidad...), los **biomas** (`themes`: texturas, niebla, ambiente, color de antorchas, luna) y, por piso: bioma, tamaño, rango min/max, enemigos, cofres, objetos y jefe (especie, nombre, alma, escala, tinte y color de ojos). |
| `balance.json` | Todos los números de balance (ver el README). |
| `texts.json` | **Todos** los textos de UI, con `%s/%d`. El lint revisa que cada `t("clave")` usada exista. |

## Sistemas

### Pisos — `FloorGenerator` → `FloorData` → `FloorBuilder`

- **Generador propio con semilla**: `hash([semilla, piso])`. Primero estampa la **sala del jefe, hecha a mano** (`floors.json → sala_jefe`, ver «Sala del jefe») contra un borde del mapa al azar, girada para que la puerta mire hacia adentro; después pone salas rectangulares sin solaparse (lejos de ella) y las une con pasillos en L, siempre a la sala más cercana ya conectada, más algunos lazos extra (si las dos L pisarían la sala del jefe, el pasillo la rodea por BFS), y cava un pasillo desde la puerta hasta lo más cercano. El inicio va en la sala más lejana de esa puerta (por BFS). La sala del jefe no está en `rooms`: ahí no van cofres, objetos, cajas ni otros enemigos. Los cofres van en esquinas de sala y **solo se aceptan si no cortan ningún camino** (BFS). Los enemigos salen de `FloorGenerator.roll_enemy()` (lo usa también `balance_sim`): especie ponderada por `peso` entre las activas no jefe cuyo `rank_range` se cruza con el del piso, rango al azar en el cruce, y tipo (las especies élite siempre lo son; las básicas con `enemies.elite_chance`). Algunos quedan **dormidos**. Los objetos sueltos salen de una tabla ponderada **solo con los objetos disponibles**. También pone props, columnas y **antorchas** (separadas `antorcha_cada` pasos; una siempre en la sala de inicio; la sala del jefe trae las suyas).
- `FloorGenerator.test_room()`: la sala 15×9 del prototipo (techo alto), con un ejemplar de cada enemigo (uno dormido) y el jefe del piso 1, columnas, props y 4 antorchas.
- **`addons/dungeon_crawler_3d` se evaluó y se descartó**: trabaja con escenas de salas 3D prearmadas, conectores y su propio grafo. Adoptarlo obligaba a rehacer la construcción del mapa (grilla lógica y geometría), y el generador propio produce el mismo formato `cells[y][x]` que ya usaba el prototipo.
- `FloorBuilder(world, tema)`: la geometría va en **una malla por bloque de 8×8 celdas** (cada bloque con su lista de luces; con un nodo por celda eran cientos de draw calls). Las caras de 2×2 m están **subdivididas 4×4** para que la luz por vértice dibuje el charco de las antorchas y la deformación afín no se exagere. **UV de mundo**: cada textura de 128 px cubre 4×4 m y se repite sin costura; un % de caras usa la variante `_b`. Los **colores de vértice** llevan una oclusión falsa horneada (unión piso-pared, rincones, techo más oscuro) y ±8% de ruido. Las celdas de techo alto agregan el "dintel" contra las vecinas más bajas.
- Luz: **sin sol** (solo luz de luna en los Salones de la Luna), ambiente tintado del bioma, fondo = color de la niebla, antorchas de pared (`FlickerLight`, parpadeo escalonado a 12 Hz) y la lámpara cálida del equipo.
- Columnas: prisma de 8 lados con basa y capitel, con la textura de pared del bioma. Antorchas: modelo de KayKit Dungeon Remastered (CC0) + llama sin sombrear.
- Los props del pack PSX también reciben material PSX, con la misma niebla y snapping que el resto. LevelBlock sigue habilitado para armar salas a mano en el editor (con su parche de `material: Material`).

### Enemigos — `EnemyBody`: `EnemySprite` (pixel art) o `EnemyVisual` (3D)

- **Sprites (por defecto)**: `EnemySprite` (`scripts/world/enemy_sprite.gd`) dibuja al enemigo como pixel art en el mundo 3D, estilo Dragon Quest HD-2D: un quad que gira en Y para mirar siempre a la cámara, con el cuadro de la hoja según el papel de animación y la dirección (8: s, se, e, ne, n, nw, w, sw; se calcula el ángulo del +Z del nodo respecto de la cámara y se usa la dirección más cercana que traiga la hoja, contando las espejadas). Shader `shaders/enemy_sprite.gdshader`: si la hoja trae **mapa de normales** (`normal`), **luz con volumen por píxel del sprite**: `EnemySprite` junta el ambiente del bioma y las 4 luces más fuertes del grupo `luces` (antorchas, lámpara, aura, luna; con la atenuación de Godot y su parpadeo), pasa la dirección de cada una al espacio del sprite y el shader sombrea cada píxel en bandas (N·L), con destello en el metal (alfa del mapa) y un reflejo de los ojos en el hueso de alrededor; si no, luz del mundo (antorchas) o **luz pareja** (`flat_light` en la hoja: `EnemySprite` suma en el centro del sprite el ambiente del bioma y las luces del grupo `luces` —antorchas, lámpara, aura, luna— con la atenuación de Godot, y el shader la aplica igual a todo el cuadro, tomando solo parte de su color: `enemies.sprite_flat_tint`), la **misma niebla PSX** que el resto (globals `psx_fog_*`), ojos de la máscara `glow` sin luz ni niebla, destello blanco al recibir un golpe y una luz propia mínima (`self_light` de la hoja o `enemies.sprite_self_light`); tinte por especie/élite/jefe multiplicado (`enemies.sprite_albedo`). Hoja = PNG + glow + JSON (`species.json → visual.sprite`); el formato, pensado para que el arte definitivo reemplace las hojas de prueba sin tocar código, está en `tools/sprites/README.md`. Las hojas se hacen por código, las cuatro en **pixel art grueso** (`tools/sprites/draw_*.py` sobre `pixel_kit.py` y, los tres esqueletos comunes, `skeleton.py`): ~38–40 px de alto a 24 px/m (píxeles el triple de gordos que los texels del entorno), pocos colores y contorno negro, armadas con sellos dibujados a mano en ASCII y huesos como líneas de píxeles; cada parte declara su forma y de ahí sale el mapa de normales. Las animaciones mueven las partes de a píxeles enteros, con anticipación, compresión y estiramiento de la calavera y movimiento secundario. Esbirro, arquero y guardián: vistas de frente, perfil y espalda (la de espaldas es la pose de frente espejada con los sellos de atrás); la muerte los desarma en un montón de huesos. El **nigromante** (diseño de David) es más grande (~52 px hasta la corona), solo de frente, con un espectro detrás y dos esqueletitos a los pies que son parte del sprite. La máscara `glow` tiene dos niveles: 255 = ojos (color de ojos a pleno) y 128 = **espíritu** (espectro, llama, aura: su gris por el color de ojos, más suave, `spirit_energy`). Guía de estilo en el README de esa carpeta. `tests/unit/test_sprites.gd` valida las hojas.
- Opciones → Enemigos (`settings.enemy_style`: `sprite` | `model`, por defecto `render.enemy_style_default`) elige al crear cada enemigo (`FloorBuilder.use_sprites`); los dos comparten la interfaz `EnemyBody` (papeles, luz propia, `finished_role`, sombra blob), que es lo único que usan `RunController` y el combate.

**Modelo 3D** — `EnemyVisual` (`scripts/world/enemy_visual.gd`):

- Modelos: esqueleto anatómico "Skeleton - Realistic" (Paul Kotelevets, CC0) con skinning rígido estilo PS1 sobre el rig de 65 huesos de la Universal Animation Library de Quaternius (UAL1 + UAL2, CC0). `tools/assets/build_skeletons.py` (Blender como módulo `bpy`) decima las 135 piezas, las encaja en las articulaciones, ata cada pieza a su hueso, hornea oclusión, pone los ojos y arma la túnica del nigromante (Modular Character Outfits - Fantasy, CC0, + una falda cónica). `process_enemies.mjs` deja solo los clips que pide `species.json`, a 12 fps, y `skeleton_textures.py` pinta el hueso a 128 px por especie. ~3,3k triángulos por cuerpo. Armas (KayKit, CC0) en `BoneAttachment3D` sobre los huesos de `visual.bones` (por defecto `hand_r`/`hand_l`/`Head`), con montaje por arma en datos (`weapon_r_mount`/`weapon_l_mount`: pos, rot, scale).
- Animación **a pasos**: el `AnimationPlayer` va en modo manual y se avanza de a 1/12 s. Cada papel (`idle`, `combat`, `walk`, `attack`, `hit`, `death`, `spawn`, `dormant`, `ability`, `taunt`) se mapea en `species.json → visual.anims` (texto o lista para variar).
- Si a un modelo le falta una animación que pide `species.json`, `EnemyVisual` lo avisa con un warning (verify lo cuenta como error). Los clips no pueden terminar en `_Loop`: el importador de Godot les saca el sufijo.
- Ojos: material sin sombrear **y sin niebla** (se ven antes que el cuerpo). Sombra "blob" con trama Bayer en recorte (sin mezcla alfa). Material un poco más claro que el entorno (`enemies.albedo_boost`).
- RunController: caminar (`walk` → `idle`), despertar (`spawn`), golpe recibido (`hit` + parpadeo), ataque y habilidad del jefe (señal `enemy_acting`, el daño llega `combat.enemy_attack_windup` s después), burla del jefe al empezar, muerte (`enemy_defeated`) y el cadáver se hunde en el piso (un montón de huesos quieto ya significa "esqueleto dormido").

### Exploración — `RunController` (Run.tscn)

- **`RetroView`** (la usan la run y el Hub): SubViewport a ~240 líneas (con `stretch = true` el tamaño lo decide el contenedor: se usa `stretch_shrink`), **trama de 15 bits dentro del SubViewport** (`shaders/psx_viewport_dither.gdshader`: cada celda Bayer es un píxel del juego y la UI queda limpia; el dither del addon se apaga con `psx_bit_depth = 0`) y los globals afín/temblor. Presets en `balance.json → render.presets`: Clásica (240 líneas, afín 0,6, temblor 160), Crujiente (180, afín 1,0, temblor 110) y Limpia (sin filtros). Opciones → Imagen.
- **Arreglo**: el jugador y los enemigos van al **centro** de la celda (`cell*2 + 1`). Antes iban a la esquina (`cell*2`), con la cámara pegada al plano de la pared oeste.
- Cámara: FOV 64 al explorar y 58 en combate; pasos de 0,22 s con suavizado y un leve balanceo vertical (Opciones → Balanceo al caminar). La lámpara del equipo es una `FlickerLight` cálida.
- Enemigos: tras cada paso del jugador, los que están a ≤ 5 pasos **de camino** se acercan por BFS y el resto deambula. Los dormidos no se mueven hasta que el equipo está a ≤ 2 pasos (ese turno solo se levantan); chocarlos los despierta en un ataque sorpresa. Si uno llega a tu celda: de frente es combate normal; por la espalda o un costado, **emboscada**. Después de huir, el enemigo queda aturdido 2 turnos. El jefe no deambula: duerme en su sala hasta su presentación.
- Cofres: se abren chocándolos y dan monedas más un objeto de la tabla. Si el inventario está lleno, el objeto queda en el suelo. Los objetos sueltos se recogen al pisarlos.
- **Sala del jefe, hecha a mano** (`floors.json → sala_jefe`): un dibujo en ASCII mirando al norte (`#` pared, `T` pared con antorcha, `.` piso, `=` alfombra, `b` brasero, `p` columna, `S` jefe, `X` salida, `D` puerta), la misma en todos los pisos con las texturas del bioma. `DataRegistry` valida filas parejas, caracteres y que haya un solo `S`, `X` y `D` (la puerta abajo, con piso arriba). `FloorGenerator._place_boss_room()` la gira (`boss_room_rows(turns)`, de a cuartos de vuelta horarios), la apoya en un borde y llena `FloorData`: piso y techo alto (`techo`, y `techo_salida` en el nicho), `boss_door` + `boss_door_dir` (hacia adentro), `braziers` y `pillars` en el centro de su celda (esas celdas van a `FloorData.solid`: se ven como piso pero no se atraviesan; `distances_from` y `RunController.is_wall` las respetan), `carpet`, `boss_circle` (el jefe) y `exit_cell` (justo detrás). Puerta, jefe y salida quedan en el mismo eje: todo centrado. `FloorBuilder.build_boss_room()` arma la **puerta** de dos hojas con marco (texturas de `tools/sprites/draw_sala_jefe.py`: tablas, herrajes, argollas y una calavera partida por la junta; cada hoja cuelga de su bisagra y muestra de cada lado su mitad del dibujo), los braseros (`BrazierFire`: llamas sin sombrear que cambian de alto a saltos, brasas y una `FlickerLight` apagada), el círculo (plano con `nigromante_circulo.png`, recorte, sin sombrear) y la **alfombra** (un tramo por celda, subdividido y a 5 cm del piso: con el temblor PS1 de los vértices, a 1 cm el piso la tapaba), con el fuego y el círculo del **color de ojos del jefe**. Los valores, en `balance.json → boss_room`.
- **La puerta**: empieza cerrada y bloquea su celda (`RunController._door_closed`; también para los enemigos). Chocarla la abre (`try_interact` → `_open_boss_door`: las hojas giran hacia adentro, sonido de puerta, mensaje; el HUD muestra «Abrir la puerta» con el marcador `door`). Al vencer al jefe se vuelve a abrir.
- **Presentación del jefe** (`RunController._boss_intro()`): pisar una celda de la sala que no sea la puerta, la primera vez (`GameState.floor_flags.boss_intro`), bloquea el control, oculta el HUD y abre `UICinematic` (franjas de tinta y la pista «Enter acelerar»); la puerta se cierra de un **portazo** detrás del equipo (sonido y sacudón de cámara con los offsets de la cámara), el equipo ya mira al jefe por el eje (`GridPlayer.face_cell` por si acaso), los braseros se encienden **de a pares** del más cercano al más lejano, se enciende el círculo, el jefe hace `spawn` (se levanta del montón; su aura se enciende), aparece el cartel (piso en romanos, nombre en gótica ×2 y `epiteto` de `floors.json`), hace `taunt` y se desliza **por la alfombra** (BFS) hasta la celda de enfrente; recién ahí `start_combat(..., "boss")`. Enter o Esc ponen `Engine.time_scale` en `boss_room.skip_speed` hasta el final (se vuelve a 1 al terminar y en `_exit_tree`). Al vencerlo se abre la puerta y se apaga el círculo; los braseros quedan. `debug_fight_boss` deja la sala así sin la presentación; `debug_boss_entrance(true)` abre la puerta y la dispara (capturas). Sonidos sintetizados por `tools/audio/make_boss_sfx.py` (portazo, brasero, golpe de entrada).
- La salida está sellada hasta matar al jefe. Pisarla abre el **punto de retiro**: bajar / retirarse / quedarse. En el último piso, salir es la victoria.
- Menús: Pausa (el árbol queda en pausa y el reloj de la run también), Estado, Inventario (`use_item_field()`; Enter sobre una casilla usa el objeto, y las curas solo se ofrecen a los heridos) y Mapa. Tab/I/M/Esc abren y cierran.

### Combate — `CombatManager`

- Autocontenido y sobre **copias**. Termina con `combat_ended(outcome, result)`, donde `outcome` es `victory`, `defeat` o `fled`, y `result` trae `{hp, items_used, soul_pick}`. RunController aplica eso a la run. *(Cambió respecto del prototipo, que emitía `(victory, soul_result)`.)*
- Acciones: Atacar · Habilidad (las activas de las almas de **ese** personaje) · Defender · Objeto · Huir.
- **Sorpresa**: el enemigo pierde su primer turno y hay ×1,5 de daño en esa ronda. **Emboscada**: el enemigo pega primero con ×1,5.
- Pasivas por tipo de efecto (`SoulEffects`): `damage_reduction_flat`, `defend_bonus_multiplier`, `damage_bonus_flat`, más tres nuevas, `lifesteal_pct`, `crit_chance`, `thorns_flat`, y `coin_bonus_pct`, que se aplica al calcular las monedas de cada kill.
- Jefes: stats ×1,5, cada 3 turnos usan una habilidad de área y no se puede huir de ellos. Después de la presentación el combate empieza en modo `boss`: el equipo tiene el turno gratis ×1,5 de la sorpresa (con su propio texto; el balance cuenta con eso) y una **entrada propia** (`_boss_entrance`): primero solo el cartel del jefe con la barra de vida que se llena a tramos, después entran las tarjetas, la cola y las acciones. La cámara de combate se abre más para un jefe (`render.combat_fov_boss`, `combat_boss_lift`, `combat_boss_pitch`): entran la corona bajo su barra y los esqueletitos sobre las tarjetas.
- UI: enemigo con rango y HP, cola de turnos, tarjetas del equipo, registro compacto y menú de acciones. Hay números flotantes, parpadeo del panel y del modelo 3D al recibir golpes, y la cámara retrocede un poco para encuadrar al enemigo.
- Al ganar: resumen post-combate (monedas y bonus de primera kill) → Continuar → **revelación del alma**, si soltó una → recogerla o dejarla → a quién → si ese personaje está lleno, reemplazar una de sus almas o descartar la nueva.

### Niveles y atributos (por expedición)

- Todo vive en el personaje de `GameState.party`: `level`, `xp`, `points` y `stats {vit, atq, def, esp, agi, sue}`. Se pierde al terminar la run (como las almas); **no toca `MetaState`**.
- EXP: `RunRules.kill_xp(rango, tipo)` = `xp_kill_base + (10 − rango) × xp_per_rank`, élite y jefe multiplican. `GameState.add_xp()` se la da entera a **cada personaje en pie** (los caídos no suben), sube los niveles que alcance (`leveling.xp_to_next`, tope `max_level`), da `points_per_level` puntos, cura `heal_on_level_pct` y emite `EventBus.level_up`. RunController (`_grant_xp`) avisa con un toast.
- Almas: `member_soul_capacity()` = capacidad base (+ Amuleto) + `RunRules.level_soul_slots(nivel)` (= nivel / `soul_slot_every`). La capacidad nunca baja dentro de una run.
- Puntos: `GameState.apply_points(m, {stat: n})` valida todo antes de tocar nada; lo que sube VIT también sube el HP actual.
- La EXP de una kill se da al cerrar el combate, pero la elección del alma pasa antes: por eso el roster lleva `level_win` y `soul_capacity_win` (`RunRules.level_after_xp`, el mismo bucle que `add_xp`) y `CombatManager._capacity_after_win()` no marca "lleno" a quien la victoria le abre un espacio. Como red, `_on_combat_ended` convierte un reemplazo en suma si al final hay lugar. El resumen de victoria anuncia las subidas de nivel.
- El bonus de monedas (pasivas + SUE) se fija al empezar el combate (`e.coin_bonus`) y es el mismo en el resumen y en lo que se cobra, aunque alguien caiga.
- Efectos (`RunRules.stat_*`, valores en `balance.json → stats`): VIT → HP máx. (redondeado); ATQ, DEF y ESP van por escalones (`floori`: con 0,25, +1 cada 4 puntos, como dice Atributos). ATQ → ataque; DEF → daño que se resta a cada golpe recibido, **después** de las pasivas y sin dejarlo en menos de 1; ESP → daño de las habilidades de alma; AGI → crítico (del personaje) y huida (promedio del equipo vivo); SUE → probabilidad de alma y monedas (suma del equipo vivo). CombatManager recibe `def`, `ability_bonus` y `crit_bonus` en el roster.
- UI: **Estado → Atributos** (`AttributesPage`): lista de personajes, retrato, nivel, EXP, `UIStatRadar` (hexágono; el reparto pendiente se dibuja en verde) y −/+ por estadística. El reparto queda pendiente hasta Confirmar; al cerrar Estado con algo pendiente, `StatusScreen.close()` pregunta si aplicarlo. Estado abre directo en Atributos si alguien tiene puntos. El HUD muestra retrato, `Nv N` y `▲N` (puntos sin repartir).

### Almas, objetos, desbloqueos y monedas

- Curva de drop (`RunRules.soul_drop_chance`): normal `8% × (1 + 0,1 × (10 − rango))`, élite 25%, jefe 100%. Sabiduría suma puntos porcentuales. El flag de debug la fuerza.
- Monedas: por kill, `11 − rango` (élite ×2); jefe, `25 × piso`; cofres según el piso; primera kill de cada especie, `10 × (11 − rango)`, que se cobra en el resumen. Botín suma un % al total. Al morir o abandonar se conserva el 50%.
- `UnlockEvaluator` (puro): `merged_progress()` suma lo de la run al progreso guardado y `evaluate()` devuelve los desbloqueos nuevos. Condiciones: `kill_species_total`, `reach_floor`, `defeat_boss`, `win_run`, `flee_count`, `no_item_use_run` y `coins_total`. Los desbloqueos se anuncian en el resumen, nunca en pleno juego.

## UI — design system «Grimorio de la Cripta»

Dirección de arte: grimorio de hierro remachado y vitela oscura, bronce, góticas con capitular roja, cursor de llama y foco de brasa; el azul frío queda solo para las **almas**, el rojo sangre para el HP y la amatista para la EXP. Todo es pixel art a 1x escalado ×2 (`UIStyle.PIXEL_SCALE`), sin suavizado.

- **Paleta** en `data/ui_palette.json` (44 colores + tokens con nombre de uso: `PANEL`, `TEXT`, `ACCENT`, `SOUL`, `HP`, `XP`...). `scripts/ui/ui_style.gd` (**UIStyle**) la repite como constantes (para usarlas en `const`) y es el único lugar con colores, tamaños de fuente y espaciados. `test_ui_kit.gd` falla si el JSON y UIStyle no coinciden, y `tools/lint` falla si aparece un `Color(` suelto en `scripts/ui`, `scripts/combat` o `SceneRouter`.
- **Kit**: `tools/ui/make_ui_kit.py` (Python + Pillow, determinista) dibuja marcos 9-slice, botones, ranuras, barras, pestañas, sellos, pips, llamas de alma, marcadores del mapa, el cursor de llama (5 cuadros), los 30 íconos de game-icons.net en varias rampas y el logo, todo en `ui/kit/ui_atlas.png` + `ui/kit/manifest.json`. `UIKit` (`scripts/ui/ui_kit.gd`) lee el manifiesto y arma `StyleBoxTexture`/`AtlasTexture`; **ThemeBuilder** arma con eso `ui/theme_main.tres`. Regenerar (en este orden): `python3 -I tools/ui/make_ui_kit.py` y `godot --headless --path . res://tools/build_theme.tscn`. Ver `tools/ui/README.md`.
- **Fuentes** (ver `assets/fonts/README.md`): Pixelify Sans (cuerpo), Micro 5 (cifras), Jacquard 12 / Jacquarda Bastarda 9 (minúsculas góticas) + Jersey 15 (mayúsculas góticas), Jacquard 24 (solo el logo, horneado en el atlas). Tamaños en múltiplos de la grilla de cada fuente.
- **Variaciones de theme**: etiquetas `HeadLabel/SubtitleLabel/DimLabel/DetailLabel/AccentLabel/GoodLabel/DangerLabel/SoulLabel`, cifras `NumLabel/NumSmallLabel/NumBigLabel/CoinLabel/CoinBigLabel/CoinDangerLabel/XpLabel/DamageLabel/HealLabel/RankLabel1..10`; botones `MenuItem/DangerButton/ItemSlot/ItemSlotLocked/NicheSlot`; paneles `PanelAlt/HudPanel/Card/CardSoul/CardFocus/PortraitFrame(Active)/RankPlaque/KeyCap/ToastPanel/RibbonSmall/DimOverlay/ScreenBg`; barras `HpGood/HpWarn/HpLow/HpFlash/EnemyBar/SoulBar/XpBar/XpThinBar/CoinBar/AccentBar/TrailBar`. Tipos propios: `GothicTitle`/`GothicQuote` (fuentes de `UIGothicLabel`) y `UIIcons` (todos los sprites del kit: `<ícono>_<rampa>`, `cursor_0..4`, pips, sellos, `map_*`, `logo`).
- **Componentes** (`scripts/ui/components/`, se arman por código): UIScreen (tapa de hierro con cimera, título gótico, placa de monedas o de conteo, cuerpo desplazable, pie con botones y cinta de pista; modo `compact` para la Pausa; apertura por pasos con sonido), ListDetailScreen (lista + detalle: Mejoras, Objetos, Bestiario), UIGothicLabel, UIMenuItem (llama + ícono + gótica), UIListRow, UIButton, UIPanel, UIDivider (filete con rombo), UIIcon, UISprite, UIFlameCursor, UICoinPlate, UIStatBar (con rastro al bajar y destello con HP bajo), UIPips, UISoulSlots, UILedgerRow (libro de cuentas con puntos guía), UIRankBadge (romanos), UISoulCard, UIItemSlot (fila o nicho de 80 px), UIPortrait, UIStatRadar, UITabs (Q/E en placas), UIMinimap (marcadores del kit), UICompass, UITooltip, UIToast (cintas: info/good/danger/coin/soul/level), UIDialog → UIConfirmDialog / UIChoiceDialog (sello de lacre; tonos normal/peligro/alma), UIProgressUnlock, UISoulMotes, UICinematic (franjas de cine y cartel de jefe), UISelector (fila con ‹ valor › que se cambia con ← →).
- **Sonidos de UI**: `SceneRouter.play_ui(kind)` (hover, click, cancel, open, close, page, coin, soul, error, level_up, reward, descend, item), CC0 de Kenney (`assets/audio/ui/README.md`); los de la sala del jefe (door_slam, brazier, boss) son sintetizados (`tools/audio/make_boss_sfx.py`). La transición de escena es un fundido con trama Bayer (`ui/shaders/ui_dither.gdshader`), que también da la viñeta del Hub.
- **Retratos**: `UIPortrait` (marco `PortraitFrame`, filtro nearest). Objetos: `items.json → retrato` (opcional; si está, `DataRegistry` valida que el archivo exista), PNG de 64 px horneados por `tools/portraits/` y mostrados a tamaño entero. **Héroes: pixel art por capas** (`HeroPortrait`, `scripts/ui/hero_portrait.gd`): las piezas de `tools/portraits/draw_hero_parts.py` (`assets/portraits/heroes/partes.png` + `.json`, con material y tono en cada píxel) pintadas con las paletas de `data/apariencia.json` según la apariencia del héroe (`MetaState.hero_look`), 48×48, a escala entera (96 = ×2, 192 = ×4) o, en huecos más chicos (HUD 28, combate 44, listas 32), recortado alrededor de la cara (`UIPortrait.set_hero`, sin escalar). Se arma una vez por apariencia y tamaño (caché; `MetaState.set_hero` la vacía).
- **Héroes** (Hub, `HeroesScreen`): una pestaña por héroe (Q/E), retrato ×4, nombre (`LineEdit`), Al azar / Como al principio y una fila `UISelector` (‹ valor ›, ← → cambian, muestra de color) por parte y color. Se guarda al instante (`MetaState.set_hero` + `SaveSystem.save_meta`); `GameState.new_run` toma el nombre de `MetaState.hero_name`. Solo apariencia. `MetaState.heroes` es un campo nuevo del guardado (opcional: los guardados viejos cargan con los valores de `balance.json → party[].apariencia`).
- **Escala de UI**: tres pasos (Compacta 0,8 / Normal 1 / Grande 1,25) en `GameSettings.UI_SCALE_STEPS`. `GameSettings.ui_factor()` redondea el `content_scale_factor` para que un píxel de arte mida un número entero de píxeles de pantalla en cualquier ventana (tabla en `tests/unit/test_ui_scale.gd`); `SceneRouter` lo recalcula al cambiar el tamaño de la ventana. Ventana base 1280×720 con `stretch canvas_items`. Con Grande en 1280×720 todo cabe porque los cuerpos se desplazan; Atributos baja el hexágono a la columna del héroe.
- `gui/common/show_focus_state_on_pointer_event=2`: el foco se dibuja igual con mouse que con teclado/mando (la brasa y la llama son el resaltado).

## Parches en `addons/psx` (reaplicar si se actualiza el addon)

- `PsxConversionDialog.gd` líneas 199/256: tipadas como `Variant`.
- `shaders/psx.gdshaderinc`:
  - **Niebla**: usaba `v_clip.w`, que en espacio de vista vale siempre 1, así que **la niebla nunca aparecía**. Ahora usa la distancia real a la cámara. Con niebla total el color es exactamente el de la niebla (en los materiales sombreados el albedo se apaga y la niebla entra por emisión; los sin sombrear usan `#define SHADING_UNSHADED`).
  - **Afín**: el truco UV·w / w necesita la w de **clip** (`v_w`); con la de vista no hacía nada.
  - **Snapping**: `min(v_clip.z, -0.001)` evita la división por cero (triángulos que desaparecían pegados a una pared).
  - `i_precision_uv/xy/z` pasaron de `instance uniform` a constantes: cada instancia gastaba 3 lugares del buffer de variables globales (4096 en Compatibilidad) y los pisos grandes lo agotaban ("Too many instances using shader instance variables").
- `scripts/PsxMaterial3D.gd`: la permutación "unshaded" agrega `#define SHADING_UNSHADED` (y las de `shaders/cache/` ya generadas se editaron a mano).
- **Las permutaciones de `shaders/cache/` se generan al usarse por primera vez y hay que commitearlas**: en un juego exportado no se pueden escribir y el material queda sin shader.

## Gotchas nuevos (además de los de CLAUDE.md)

- Texturas del mundo, de enemigos y de las hojas de sprites: `detect_3d/compress_to=0` en su `.import`. Si no, el editor las pasa a VRAM comprimida con mipmaps la primera vez que las ve en 3D y se pierde el píxel limpio.
- El esqueleto mide 1,775 m y el techo normal es de 2 m (escala 0,95–1,05 en `species.json`; la sala del jefe tiene 3,5 m). El sprite del nigromante llega a ~2,2 m de corona y ~2,5 m con el espectro alzado, por `scale_mult` del piso (1,0–1,16): si se agranda, revisar que no atraviese el techo de su sala.
- Llamar sin `await` a una función con `await` (una corrutina) es válido y no da warning: corre hasta su primer `await` y sigue. Para esperar su final hace falta una señal (p. ej. `UICinematic.title_done`). Revisar con `tools/enemy_preview.tscn` (líneas de 1, 2 y 3 m; `--preview-role`, `--preview-at`, `--preview-cam`, `--preview-only`).
- `tools/screenshot.gd --call=metodo:arg` pasa el argumento como texto ("true"/"false" se convierten a bool, los enteros a int).

- `RenderingServer.global_shader_parameter_get_list()` **solo funciona en el editor**: en el juego devuelve vacío y tira un error. Para saber si un global PSX ya existe se mira `ProjectSettings.has_setting("shader_globals/<nombre>")`.
- Los métodos de un autoload no pueden ser `static` si se llaman como `Autoload.metodo()`: da el warning *static called on instance*.
- `MenuButton` es una clase nativa: no se puede usar como nombre de variación de theme (se usa `MenuItem`).
- Nombres que pisan miembros de la clase base y dan *shadowed variable*: `panel` (UIScreen), `scale`, `hidden`, `tr`, `theme`. Usar `p_panel`, `scale_opt`, `is_hidden`...
- Un `ProgressBar` dibuja el relleno sobre todo su rectángulo: los rellenos del kit llevan márgenes de expansión negativos para quedar dentro del marco (`ThemeBuilder._fill`).
- Texto gótico solo con `UIGothicLabel` (mayúsculas en Jersey 15) y sin símbolos (◈ ✦ ↑...): las claves fijas van en `UIGothicLabel.FIXED_KEYS` y el test las revisa.
- Pantallas abiertas desde `tools/screenshot.gd --screen=Clase`: si tienen la propiedad `run` y la escena es la run, se les pasa; `--tab=N` elige la pestaña de Estado.
- `seed`, `wrap`, etc. son funciones globales de GDScript: no sirven como nombres de variable o parámetro (dan el warning *shadowed global identifier*).
- Recargar con `ResourceLoader.load(..., CACHE_MODE_IGNORE)` el script que se está ejecutando rompe su propia ejecución (lo evita `tools/lint.gd`).
- `get_error_line()` de `JSON` es 0-based: se le suma 1 en los mensajes.

## Cómo extender

- **Especie nueva**: una entrada en `species.json` (con `rank_range`, `tier`, `peso` y el bloque `visual`) y su alma en `souls.json`. Aparece en los pisos cuyo rango se cruce con su `rank_range`. Modelo nuevo: sumarlo a `ENEMIES` en `tools/assets/process_enemies.mjs` y revisar con `tools/enemy_preview.tscn`.
- **Bioma nuevo**: una entrada en `floors.json → themes`, sus 5 texturas (`tools/assets/make_textures.py`, tabla `THEMES`) y asignarlo a un piso con `"theme"`.
- **Pasiva nueva**: el tipo en `DataRegistry.PASSIVE_EFFECTS`, su `case` en `CombatManager` (o donde se aplique) y su texto `effect.<tipo>` en `texts.json`.
- **Objeto nuevo**: `items.json`. Si tiene un efecto nuevo: `DataRegistry.ITEM_EFFECTS`, `RunController.use_item_field()` y/o `CombatManager._on_item()`.
- **Condición de desbloqueo nueva**: `DataRegistry.UNLOCK_CONDITIONS` y su caso en `UnlockEvaluator.progress_of()`; si depende de un dato nuevo de la run, sumarlo a `GameState.snapshot()`.
- **Personaje nuevo**: una entrada en `balance.json → party` (con su `apariencia` de arranque).
- **Opción de apariencia nueva**: dibujarla en `tools/portraits/draw_hero_parts.py`, correr el script y sumar su nombre en `data/apariencia.json` (mismo id y orden; `DataRegistry` lo revisa).
- **Estadística nueva**: sumarla a `RunRules.STATS` (el orden es el del hexágono, empezando arriba), su `stat_*` y dónde se aplica, sus valores en `balance.json → stats`, los textos `stats.<id>.short/name/desc/effect` y su caso en `AttributesPage._desc/_effect`.
- **Pantalla nueva**: extender `UIScreen` (o `ListDetailScreen`), armarla solo con componentes y poner sus textos en `texts.json`.

## Tests

- `tests/unit/`: datos (validación, JSON roto, `stats_for_rank`, `make_soul`), guardado (ida y vuelta, `.bak`, migración v0, versión futura), reglas (costes con tope, curva de almas, huida, monedas), niveles (EXP, subidas dobles, tope, caídos, almas extra, reparto de puntos), recompensas, desbloqueos, generador (semilla, conectividad, jefe/salida, rangos, pesos, sala del jefe: el dibujo girado entero en las cuatro orientaciones, puerta hacia un pasillo alcanzable, puerta-jefe-salida en el eje, nada ajeno adentro), héroes (cada opción arma un retrato, cambiar una parte lo cambia, bajo capucha no se ve el pelo, tamaños enteros o recorte, apariencia guardada y sus límites), kit de UI (paleta = UIStyle, manifiesto al día con la paleta y el generador, regiones e íconos, Theme guardado al día, grillas de fuentes, góticas sin símbolos, romanos) y escala de UI (píxel de arte entero en 720p, 1080p y 1366×768).
- `tests/SmokeTest.tscn`: Boot → Hub → run con semilla fija → combate ganado con alma → combate jugado atacando turno a turno → EXP → poción usada desde el inventario → puntos repartidos y confirmados en Atributos (y la pregunta al cerrar con puntos pendientes) → caminar → jefe → piso 2 → muerte → resumen → Hub (monedas persistentes al recargar), después una run que entra a la **sala del jefe** (la puerta cerrada bloquea, chocarla la abre, entrar dispara la presentación acelerada → combate en modo `boss` con el jefe enfrente por la alfombra, puerta cerrada y braseros encendidos → victoria → puerta abierta) y se retira (100%), y abre todas las pantallas de UI. Antes de todo, cambia el nombre y el pelo de Bjorn en Héroes y comprueba que se guarda, que el retrato cambia y que la run usa ese nombre.
- `tools/balance_sim.tscn`: simulación de balance, con niveles y dos políticas de reparto (ver el README). Los jefes empiezan siempre con el turno gratis del equipo, como en el juego (modo `boss`). `-- --set=ruta=valor` pisa `balance.json` en memoria, así se pueden correr varias pruebas a la vez.

## Pendiente

- Más especies (candidatos ya evaluados: LibreQuake, BSD-3, zombi y caballero infernal); integrar Gothic Furniture; sonidos reales.
- Licencias: el pack de goblins no tiene (sus especies están inactivas); el pack PSX de cajas/barriles prohíbe redistribuirlo (revisar si el repo es público).
- Diferido: razas, árbol de habilidades, crafting, eventos mensuales.
