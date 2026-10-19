# Estado técnico del prototipo — handoff para Claude Code

Complemento técnico de CLAUDE.md (reglas y decisiones) y de docs/PLAN_DE_DISENO_ROGUELIKE.md (diseño vigente). El plan anterior (RPG de gestión) está archivado en docs/archive/.

> Nota (19-oct-2026): CLAUDE.md, PLAN_DE_DISENO_ROGUELIKE.md y docs/archive/ todavía no están subidos al repo.

**Dirección actual (19-oct-2026):** roguelike con hub mínimo, mejoras de stats por monedas (con tope), objetos desbloqueables por condiciones y almas que no persisten entre runs. El código descrito abajo es el prototipo de mecánicas (movimiento, combate, almas) sobre el que se construirá el bucle de run.

## Verificación

Probado con Godot 4.7.2 (Linux, headless):

```
godot --headless --path . --import
godot --headless --path . --quit-after 120
```

Ambos terminan sin errores ni warnings (salvo los avisos informativos de los .obj de KayKit al importar).

Problemas que se resolvieron al verificar por primera vez:

- **Error "variable type is being inferred from a Variant value" (líneas 199/256):** era `addons/psx/scenes/PsxConversionDialog.gd` (y su copia duplicada). Se tiparon como `Variant` las dos variables que reciben `convert_resource()`.
- **"Class Psx hides a global script class":** había una copia entera del plugin en `psx_visuals-<hash>/` además de `addons/psx/`. Se borró la copia (y también las de `godot-levelblock-3.0.2/` y `KayKit-Dungeon-Remastered-<hash>/`). `addons/psx/materials/psx_post_process.tres` apuntaba al shader de la copia; ahora apunta a `addons/psx/`.
- **La importación se cortaba** por `Crates_and_barrels.blend` (no hay Blender configurado). Las carpetas de packs originales (`GoblinPack_Free/`, `Gothic Furniture/`, `PSX Dungeon Boxes and Barrels Pack/`) llevan un `.gdignore`: Godot no las importa. El juego usa las copias en `assets/`.
- **`_ensure_psx_shader_globals()`** registraba globals que project.godot ya declara → 8 errores. Ahora solo registra los que faltan.
- **Fugas al salir:** la plantilla de props (`_props_template`) nunca entraba al árbol y no se liberaba. Ahora se libera en `Main._exit_tree()`.
- `.godot/` ya no se versiona (ver `.gitignore`).

## Motor y versión

Godot 4.7 (GDScript, no C#). `config/features` en project.godot dice "4.7".

## Estructura de archivos

```
├── project.godot
├── docs/                      # este doc
├── scenes/
│   └── Main.tscn              # escena raíz, solo un Node3D con Main.gd
├── scripts/
│   ├── Main.gd                # el más grande — orquesta todo (ver abajo)
│   ├── GridPlayer.gd          # movimiento en grilla 90° + detección de choque con enemigo
│   ├── CombatManager.gd       # combate por turnos, UI, flujo de alma
│   └── StatusMenu.gd          # menú de estado (Tab)
├── shaders/
│   └── psx_vertex.gdshader    # shader PS1 casero — YA NO SE USA (lo reemplazó el plugin PSX), queda de referencia
├── assets/
│   ├── psx_boxes_barrels/     # pack de cajas/barriles (glb), integrado
│   ├── goblin_pack/           # 3 modelos de goblin (glb), integrado
│   └── gothic_furniture/      # muebles góticos (fbx), NO integrado (ver Pendientes)
├── addons/
│   ├── psx/                   # plugin "PSX Visuals" de snotbane — integrado y en uso (1 parche de tipado)
│   ├── level_block/           # plugin "LevelBlock" — construye la sala, integrado y en uso (con 1 parche)
│   ├── kaykit_dungeon_remastered/ # assets KayKit, sin usar todavía
│   └── dungeon_crawler_3d/    # generador procedural de mazmorras — copiado, SIN CONECTAR a propósito
└── GoblinPack_Free/, Gothic Furniture/, PSX Dungeon Boxes and Barrels Pack/
                               # descargas originales, ignoradas por Godot (.gdignore)
```

## Arquitectura general

- **Main.gd** (extends Node3D, en Main.tscn) es el orquestador central. Todo lo 3D vive dentro de `world` (un Node3D metido en un SubViewport de baja resolución, ver más abajo). Main.gd también es dueño del bestiario (`SPECIES_DB`) y del roster del equipo (`party_roster`). Arma y destruye las instancias de CombatManager y StatusMenu como hijos directos de Main (fuera del SubViewport, a resolución nativa).
- **GridPlayer.gd** (extends Node3D, instanciado por Main.gd vía `set_script()`, sin class_name) maneja el movimiento: pasos y giros discretos con Tween. Chequea paredes (`dungeon.is_wall()`) y enemigos (`dungeon.get_enemy_at()`) contra Main.gd (referenciado como `dungeon`).
- **CombatManager.gd** (extends CanvasLayer, instanciado por `Main.start_combat()`) es autocontenido. Recibe datos por propiedades públicas ANTES de `add_child()` (`enemy_data`, `soul_data`, `guarantee_soul`, `party_roster`). Construye su propia UI por código (sin .tscn) y corre los turnos. Al terminar emite `combat_ended(victory, soul_result)`; Main.gd escucha esa señal y aplica los cambios persistentes (borrar el enemigo, agregar el alma al roster).
- **StatusMenu.gd** (extends CanvasLayer) sigue el mismo patrón: Main.gd lo instancia una vez en `_ready()` y lo muestra u oculta con Tab. Llama a `refresh(party_roster)` cada vez que se abre.

## Decisiones de implementación clave (y por qué)

- **Doble resolución (mundo 3D vs. UI):** `_setup_low_res_viewport()` mete todo lo 3D en un SubViewport de 320x180 con `texture_filter = NEAREST`. La UI va como CanvasLayer hijo directo de Main, a resolución nativa. Si la UI estuviera dentro del SubViewport quedaría gigante y pixelada.
- **Movimiento por grilla, no física:** no hay CharacterBody3D. Todo el bloqueo es lógico (array `test_map` + diccionarios), por eso los LevelBlock llevan `generate_collision = false`.
- **SPECIES_DB:** diccionario constante con rango, modelo o color y la estructura del alma. `stats_for_rank(rank)` calcula HP, ataque y daño de la activa (rango 1 = más fuerte, 10 = más débil).
- **Almas por personaje, no por grupo:** `party_roster` es la fuente de verdad. Cada combate recibe un `.duplicate(true)`. CombatManager nunca muta `Main.party_roster`; solo reporta por señal.
- **Pasivas por "tipo":** `effect: {"type", "value"}`. Tipos implementados: `damage_reduction_flat`, `defend_bonus_multiplier`, `damage_bonus_flat`. Para sumar un tipo nuevo hay que agregar un case en `_get_passive_effect()` y otro en `_passive_effect_hint()`.
- **LevelBlock:** hay un nodo por celda de PISO. La pared que se ve es la cara de la celda de piso vecina. Usa un atlas de 3 tiles generado por código (`_make_grid_atlas()`). LevelBlock genera cubos de lado fijo = `CELL_SIZE` (2.0), por eso `WALL_HEIGHT` también es 2.0.
- **Parche en `addons/level_block/level_block_node.gd`:** `material` pasó de `BaseMaterial3D` a `Material` para aceptar `PsxMaterial3D` (que es un ShaderMaterial).
- **Parche en `addons/psx/scenes/PsxConversionDialog.gd`:** se tipó como `Variant` (líneas 199 y 256) para que compile con warnings tratados como error.
- **Shader globals PSX:** `_ensure_psx_shader_globals()` es la primera línea de `_ready()`. Garantiza que los globals existan al correr la partida aunque el editor no haya cargado el plugin. Solo agrega los que falten.
- **Modelos de enemigo:** `_apply_psx_material_recursive()` arma un PsxMaterial3D para cada malla, reusando la textura original.

## Gotchas de GDScript (para no repetirlos)

`var x := algo.campo` o `var x := array[i]` falla (warning tratado como error) si `algo` o `array` no están tipados. La solución siempre es tipar explícito: `var x: Tipo = ...`, o `var x: Variant = ...` si puede ser null o de varios tipos.

Ejemplos corregidos:

- `var victory := enemy.hp <= 0` → `var victory: bool = enemy.hp <= 0`
- `var m = party[i]` → `var m: Dictionary = party[i]`
- `var passive = soul.get("passive")` → `var passive: Variant = soul.get("passive")`
- `const DIRS := [...]` → `const DIRS: Array[Vector2i] = [...]`

Otros bugs ya resueltos:

- **Rotación invertida:** Godot rota positivo en sentido antihorario, al revés de N→E→S→O. Por eso se usa signo negativo en `GridPlayer.setup()` y en `_turn()`.
- **@onready con nodos dinámicos:** hay que agregar los hijos (p. ej. Camera3D) ANTES de meter el padre en el árbol.

## Qué falta (reordenado para el roguelike)

**Núcleo roguelike (prioridad):**

1. Separar el estado de run del estado meta. Run = se descarta al morir. Meta = monedas, mejoras, desbloqueos y bestiario, guardados en JSON o ConfigFile versionado.
2. Bucle de run: hub → pisos → jefe → muerte o retiro → resumen → hub.
3. Hub mínimo con dos UIs: mejoras por monedas (con tope) y objetos con su condición de desbloqueo.
4. Sistema de condiciones de desbloqueo: datos + evaluador de eventos ("matar especie X", "llegar al piso N").
5. Mover `SPECIES_DB` fuera de Main.gd y agregar un pool de objetos.

**Pendientes heredados:**

6. Ataque sorpresa: atacar primero (bump) debería dar ventaja.
7. Probabilidad de alma: hoy está garantizada hasta que todo el roster tenga alma (`guarantee` en `start_combat()`). Pasar a una curva: garantizada en jefes, baja en enemigos normales, con flag de debug.
8. Pantalla de resumen post-combate con revelación del alma.
9. Capacidad de alma hardcodeada en 1 (`CombatManager._show_member_select()`, `m.souls.is_empty()`).
10. Gothic Furniture sin integrar (.fbx con texturas sueltas).
11. Generación procedural: `addons/dungeon_crawler_3d` está sin conectar y usa su propio modelo (salas, conectores, grafo).
12. Licencias: el pack de goblins no trae licencia.
13. Diferido (no implementar sin pedido): niveles/XP, razas, árbol de habilidades, crafting.

## Bestiario actual

| Especie | Rango | Modelo | Activa | Pasiva | Modificadores |
|---|---|---|---|---|---|
| Goblin explorador | 9 | Basic_Goblin.glb | Golpe Bárbaro | Piel Curtida (damage_reduction_flat 1) | — |
| Goblin arquero | 7 | Goblin_Archer.glb | Disparo Certero | Puntería Letal (damage_bonus_flat 1) | — |
| Goblin guerrero | 5 | Goblin_Warrior.glb | Estocada Brutal | — | atk +2, max_hp +2 |
| Rata de cripta | 8 | cubo de color | Mordisco Rabioso | — | atk +1 |
| Esqueleto guardián | 4 | cubo de color | Corte Óseo | Guardia Inquebrantable (defend_bonus_multiplier 0.25) | max_hp +3 |

Todo vive en `Main.SPECIES_DB` y `Main.enemy_species` (celda → especie).
