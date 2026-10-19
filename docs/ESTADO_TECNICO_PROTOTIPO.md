# Estado técnico — roguelike jugable de punta a punta

Complemento técnico de `CLAUDE.md` (reglas) y `docs/GUIA_CLAUDE_CODE.md` (plan por fases). Actualizado al terminar las fases 0–9 de la guía (19-oct-2026).

> `docs/PLAN_DE_DISENO_ROGUELIKE.md` y `docs/archive/` todavía no están en el repo.

## Verificación

```
tools/verify.sh
```

Corre import, lint, arranque (`--quit-after 120`), 38 tests unitarios y el smoke test. Todo pasa con **cero errores y cero warnings**: los warnings de GDScript se suben a error con un `override.cfg` temporal, porque fuera del editor Godot no los imprime. Godot 4.7.2 headless; en este entorno el comando es `godot`.

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
| `species.json` | Especies: rango, modelo o colores de caja, `soul_id`, familia y descripción. Las claves siguen las del prototipo (`display_name`, `rank`...). |
| `souls.json` | Plantillas de alma: `active{name}`, `passive{name, description, effect{type, value}}` o `null`, y `stat_modifiers`. Incluye las 5 almas de jefe con las pasivas nuevas. |
| `items.json` | 8 objetos: `nombre`, `descripcion`, `tipo` (consumible/pasivo), `efecto{tipo, valor, en_combate, fuera_combate}`, `peso_aparicion`, `unlock_id`. |
| `unlocks.json` | Condiciones: `condicion{tipo, parametros}`, `recompensa` (id de objeto) y `oculto`. |
| `upgrades.json` | Mejoras: `efecto{tipo, valor}` (el valor puede ser fraccionario; el total se redondea), `coste_base` y `max_nivel`. |
| `floors.json` | Generación (tamaño de salas, densidad...) y, por piso: tamaño, rango min/max, enemigos, cofres, objetos y jefe. |
| `balance.json` | Todos los números de balance (ver el README). |
| `texts.json` | **Todos** los textos de UI, con `%s/%d`. El lint revisa que cada `t("clave")` usada exista. |

## Sistemas

### Pisos — `FloorGenerator` → `FloorData` → `FloorBuilder`

- **Generador propio con semilla**: `hash([semilla, piso])`. Pone salas rectangulares sin solaparse y las une con pasillos en L, siempre a la sala más cercana ya conectada, más algunos lazos extra. El jefe va en la sala más lejana del inicio (por BFS), parado junto a la salida. Los cofres van en esquinas de sala y **solo se aceptan si no cortan ningún camino** (BFS). Los enemigos salen de las especies cuyo rango cae en el rango del piso, y algunos son élite. Los objetos sueltos salen de una tabla ponderada **solo con los objetos disponibles**. También pone props y columnas de decoración.
- `FloorGenerator.test_room()`: la sala 15×9 del prototipo, con los 5 enemigos, columnas y props en las mismas posiciones.
- **`addons/dungeon_crawler_3d` se evaluó y se descartó**: trabaja con escenas de salas 3D prearmadas, conectores y su propio grafo. Adoptarlo obligaba a rehacer la construcción del mapa (grilla lógica y geometría), y el generador propio produce el mismo formato `cells[y][x]` que ya usaba el prototipo.
- `FloorBuilder`: **la geometría del piso es UNA sola malla**, hecha con el mismo algoritmo de caras, UV y normales de `LevelBlock.create_mesh()`, así que el aspecto es idéntico. Con un nodo LevelBlock por celda (hasta ~900 en el piso 5) se agotaba el buffer de *instance uniforms* del shader PSX, que usa 3 por instancia, y eran cientos de draw calls. LevelBlock sigue habilitado para armar salas a mano en el editor (con su parche de `material: Material`).
- Los props del pack PSX ahora también reciben material PSX, con la misma niebla y snapping que el resto.

### Exploración — `RunController` (Run.tscn)

- Mantiene el SubViewport de baja resolución del prototipo. **Arreglo**: con `SubViewportContainer.stretch = true` el tamaño lo decide el contenedor, y `viewport.size` se ignoraba, así que antes se renderizaba a resolución completa. Ahora `stretch_shrink` se calcula para llegar a unas 180 líneas. Se puede desactivar en Opciones → Pixelado PS1.
- **Arreglo**: el jugador y los enemigos van al **centro** de la celda (`cell*2 + 1`). Antes iban a la esquina (`cell*2`), con la cámara pegada al plano de la pared oeste.
- El jugador lleva una luz tenue (antorcha de mano), porque sin ella las paredes de espaldas a la luz direccional quedaban negras.
- Enemigos: tras cada paso del jugador, los que están a ≤ 5 pasos **de camino** se acercan por BFS y el resto deambula. Si uno llega a tu celda: de frente es combate normal; por la espalda o un costado, **emboscada**. Después de huir, el enemigo queda aturdido 2 turnos. El jefe no se mueve.
- Cofres: se abren chocándolos y dan monedas más un objeto de la tabla. Si el inventario está lleno, el objeto queda en el suelo. Los objetos sueltos se recogen al pisarlos.
- La salida está sellada hasta matar al jefe. Pisarla abre el **punto de retiro**: bajar / retirarse / quedarse. En el último piso, salir es la victoria.
- Menús: Pausa (el árbol queda en pausa y el reloj de la run también), Estado, Inventario (`use_item_field()`) y Mapa. Tab/I/M/Esc abren y cierran.

### Combate — `CombatManager`

- Autocontenido y sobre **copias**. Termina con `combat_ended(outcome, result)`, donde `outcome` es `victory`, `defeat` o `fled`, y `result` trae `{hp, items_used, soul_pick}`. RunController aplica eso a la run. *(Cambió respecto del prototipo, que emitía `(victory, soul_result)`.)*
- Acciones: Atacar · Habilidad (las activas de las almas de **ese** personaje) · Defender · Objeto · Huir.
- **Sorpresa**: el enemigo pierde su primer turno y hay ×1,5 de daño en esa ronda. **Emboscada**: el enemigo pega primero con ×1,5.
- Pasivas por tipo de efecto (`SoulEffects`): `damage_reduction_flat`, `defend_bonus_multiplier`, `damage_bonus_flat`, más tres nuevas, `lifesteal_pct`, `crit_chance`, `thorns_flat`, y `coin_bonus_pct`, que se aplica al calcular las monedas de cada kill.
- Jefes: stats ×1,5, cada 3 turnos usan una habilidad de área y no se puede huir de ellos.
- UI: enemigo con rango y HP, cola de turnos, tarjetas del equipo, registro compacto y menú de acciones. Hay números flotantes, parpadeo del panel y del modelo 3D al recibir golpes, y la cámara retrocede un poco para encuadrar al enemigo.
- Al ganar: resumen post-combate (monedas y bonus de primera kill) → Continuar → **revelación del alma**, si soltó una → recogerla o dejarla → a quién → si ese personaje está lleno, reemplazar una de sus almas o descartar la nueva.

### Almas, objetos, desbloqueos y monedas

- Curva de drop (`RunRules.soul_drop_chance`): normal `8% × (1 + 0,1 × (10 − rango))`, élite 25%, jefe 100%. Sabiduría suma puntos porcentuales. El flag de debug la fuerza.
- Monedas: por kill, `11 − rango` (élite ×2); jefe, `25 × piso`; cofres según el piso; primera kill de cada especie, `10 × (11 − rango)`, que se cobra en el resumen. Botín suma un % al total. Al morir o abandonar se conserva el 50%.
- `UnlockEvaluator` (puro): `merged_progress()` suma lo de la run al progreso guardado y `evaluate()` devuelve los desbloqueos nuevos. Condiciones: `kill_species_total`, `reach_floor`, `defeat_boss`, `win_run`, `flee_count`, `no_item_use_run` y `coins_total`. Los desbloqueos se anuncian en el resumen, nunca en pleno juego.

## UI — design system

- `scripts/ui/ui_style.gd` (**UIStyle**) es el único lugar con colores, tamaños de fuente y espaciados. `ThemeBuilder` arma con eso `ui/theme_main.tres`, el tema del proyecto. **Regenerarlo** después de tocar cualquiera de los dos: `godot --headless --path . res://tools/build_theme.tscn`.
- Variaciones de theme: `HeroLabel/TitleLabel/SubtitleLabel/DimLabel/DetailLabel/AccentLabel/CoinLabel/SoulLabel/GoodLabel/DangerLabel`, `MenuItem/DangerButton/ItemSlot`, `PanelAlt/Card/HudPanel/ScreenBg/DimOverlay` y `HpGood/HpWarn/HpLow/SoulBar/CoinBar/AccentBar`.
- Componentes (`scripts/ui/components/`, `class_name` que se arman por código, igual que el resto del proyecto): UIButton, UIMenuItem, UIPanel, UIStatBar, UIRankBadge, UISoulCard, UIItemSlot, UITooltip (aparece al enfocar y con el mouse), UIConfirmDialog, UIChoiceDialog, UIToast, UIProgressUnlock, UITabs, UIMinimap y UIScreen (base de todas las pantallas: fondo atenuado, panel, título y monedas, cuerpo desplazable siguiendo al foco, pie con botones, Esc para atrás).
- Fuentes: Pixelify Sans, más Noto Sans Symbols 1 y 2 de respaldo para ◈ ✦ ▶ ★ ← ↑… Todas sin antialiasing desde el `.import`. **Gotcha**: Godot calcula la altura de línea con la fuente más alta de la cadena de respaldo. Por eso las Noto están recortadas y con ascent/descent igualados a Pixelify; si no, el interlineado se duplica.
- Ventana base 1280×720 con `stretch canvas_items`: se ve igual a 1080p. La escala de UI (80–150%) es `content_scale_factor`. A 150% en 1280×720 todo cabe, porque los cuerpos se desplazan.

## Gotchas nuevos (además de los de CLAUDE.md)

- `RenderingServer.global_shader_parameter_get_list()` **solo funciona en el editor**: en el juego devuelve vacío y tira un error. Para saber si un global PSX ya existe se mira `ProjectSettings.has_setting("shader_globals/<nombre>")`.
- Los métodos de un autoload no pueden ser `static` si se llaman como `Autoload.metodo()`: da el warning *static called on instance*.
- `MenuButton` es una clase nativa: no se puede usar como nombre de variación de theme (se usa `MenuItem`).
- `seed`, `wrap`, etc. son funciones globales de GDScript: no sirven como nombres de variable o parámetro (dan el warning *shadowed global identifier*).
- Recargar con `ResourceLoader.load(..., CACHE_MODE_IGNORE)` el script que se está ejecutando rompe su propia ejecución (lo evita `tools/lint.gd`).
- `get_error_line()` de `JSON` es 0-based: se le suma 1 en los mensajes.

## Cómo extender

- **Especie nueva**: una entrada en `species.json` y su alma en `souls.json`. Aparece en los pisos cuyo rango la incluya.
- **Pasiva nueva**: el tipo en `DataRegistry.PASSIVE_EFFECTS`, su `case` en `CombatManager` (o donde se aplique) y su texto `effect.<tipo>` en `texts.json`.
- **Objeto nuevo**: `items.json`. Si tiene un efecto nuevo: `DataRegistry.ITEM_EFFECTS`, `RunController.use_item_field()` y/o `CombatManager._on_item()`.
- **Condición de desbloqueo nueva**: `DataRegistry.UNLOCK_CONDITIONS` y su caso en `UnlockEvaluator.progress_of()`; si depende de un dato nuevo de la run, sumarlo a `GameState.snapshot()`.
- **Pantalla nueva**: extender `UIScreen` (o `ListDetailScreen`), armarla solo con componentes y poner sus textos en `texts.json`.

## Tests

- `tests/unit/`: datos (validación, JSON roto, `stats_for_rank`, `make_soul`), guardado (ida y vuelta, `.bak`, migración v0, versión futura), reglas (costes con tope, curva de almas, huida, monedas), recompensas, desbloqueos y generador (semilla, conectividad, jefe/salida, rangos, pesos).
- `tests/SmokeTest.tscn`: Boot → Hub → run con semilla fija → combate ganado con alma → combate jugado atacando turno a turno → caminar → jefe → piso 2 → muerte → resumen → Hub (monedas persistentes al recargar), después una run con retiro (100%), y abre todas las pantallas de UI.
- `tools/balance_sim.tscn`: simulación de balance (ver el README).

## Pendiente

- Arte propio de jefes; integrar Gothic Furniture; sonidos reales.
- Confirmar la licencia del pack de goblins antes de publicar.
- Diferido: razas, árbol de habilidades, crafting, eventos mensuales, niveles/XP.
