# CLAUDE.md — Dungeon Crawler Roguelike (Godot 4, estética PS1)

Idioma de trabajo con el usuario (David): **español**. Código y nombres de identificadores: como ya están en el proyecto (mezcla; los datos de juego en español).

**Empieza por `docs/GUIA_CLAUDE_CODE.md`**: lista completa y ordenada de todo lo que hay que hacer (incluye el mandato de dar a TODOS los menús y sistemas un diseño decente y consistente para poder hacer pruebas de juego).

## Qué es el proyecto

Dungeon crawler en primera persona, movimiento en grilla de 90°, combate por turnos con cámara estática y UI superpuesta, estética PS1 (baja resolución, vertex snapping, niebla). Godot 4.7 / GDScript.

## Pivote (19-oct-2026): de RPG de gestión a ROGUELIKE

La visión original (mazmorra mensual, impuesto anual con pena de muerte, 10 pisos enormes, razas, crafting, eventos mensuales) era demasiado grande. Se pasa a roguelike. La visión anterior queda archivada en `docs/archive/`.

### Decisiones CONFIRMADAS

- **Run** = una expedición con permadeath. Al morir, termina la run.
- **Hub mínimo** entre runs (pantalla/UI simple, no un mundo explorable).
- **Meta-progresión en dos capas:**
  1. Mejoras de stats básicas compradas con **monedas** ganadas en las runs (con **tope**; deben ser chicas para no romper el roguelike).
  2. **Objetos** que pueden aparecer en las runs, **desbloqueados por CONDICIONES** (p. ej. "matar X", "llegar al piso N"), NO por monedas.
- **Las almas NO persisten entre runs.** Se ganan y se usan dentro de la run.
- Se mantiene: movimiento en grilla, combate por turnos en primera persona, estética PSX, sistema de almas por personaje, sistema de rangos (10 = más débil, 1 = más fuerte; monstruo rango N → alma rango N de esa especie).
- Almas: cada alma = 1 activa (siempre) + 1 pasiva opcional + `stat_modifiers`. Son por personaje (no del grupo); recogerla es opcional y el jugador elige a quién.
- Primera kill de una especie = bonus (bestiario persistente, ver abajo).
- **Niveles y EXP por expedición** (20-oct-2026): EXP por kill para cada personaje en pie; 3 puntos libres por nivel para repartir entre **VIT ATQ DEF ESP AGI SUE** (Estado → Atributos, con hexágono); **+1 espacio de alma cada 2 niveles**. Se pierde al terminar la run. **Retratos** de héroes y objetos: render 3D con filtro PS1 (`tools/portraits/`).

### Propuestas NO confirmadas (preguntar antes de asumir)

Tienen un valor por defecto en `docs/GUIA_CLAUDE_CODE.md` §9, implementado en `data/balance.json`:

- 5–6 pisos, run de 45–90 min.
- Alma garantizada en jefes; drop normal bajo (el 0,2% original no sirve en roguelike corto).
- "Impuesto": % de monedas al volver al hub, o tributo por piso.
- Equipo de 1–3 personajes.
- Razas, crafting, eventos mensuales: diferidos, no implementar.
- Alcance de persistencia del bestiario / bonus de primera kill.
- Si se adopta `addons/dungeon_crawler_3d` para generación procedural.

## Estado del código

Las fases 0–9 de la guía están hechas: el roguelike es **jugable de punta a punta** (Hub → run → muerte/retiro/victoria → resumen → Hub). Ver `docs/ESTADO_TECNICO_PROTOTIPO.md` (arquitectura, decisiones, gotchas, cómo extender) y `README.md` (controles y valores por defecto).

- Autoloads: `EventBus`, `DataRegistry`, `MetaState` (persistente), `SaveSystem`, `GameState` (run), `Controls`, `SceneRouter`, `DebugTools`.
- Escenas: `Boot` → `Hub` → `Run` (RunController) → `RunSummary`; `ui/UIGallery`.
- Niveles: `GameState.add_xp/apply_points`, fórmulas en `RunRules.stat_*`, valores en `balance.json → leveling/stats`; UI en `scripts/ui/screens/attributes_page.gd`.
- Datos de juego en `data/*.json` (especies, almas, objetos, desbloqueos, mejoras, pisos, balance, textos), validados por `DataRegistry`.
- UI «Grimorio de la Cripta» (hierro, vitela, bronce, góticas; azul solo para almas): paleta en `data/ui_palette.json` (espejada en `scripts/ui/ui_style.gd`) → kit pixel generado por `tools/ui/make_ui_kit.py` (`ui/kit/`) → un solo Theme generado por `scripts/ui/theme_builder.gd`; componentes en `scripts/ui/components/`. Ver `tools/ui/README.md` y `docs/ESTADO_TECNICO_PROTOTIPO.md` → UI.
- Plugins: `addons/psx` (PSX Visuals, **parcheado**: ver abajo), `addons/level_block` (parcheado; el juego usa su algoritmo en mallas propias), `addons/dungeon_crawler_3d` (evaluado y descartado) y `addons/kaykit_dungeon_remastered` (CC0; de ahí salen las antorchas).
- Enemigos en **pixel art estilo Dragon Quest HD-2D** por defecto (hasta 8 direcciones): `EnemySprite` + hojas en `assets/sprites/enemies/` (`species.json → visual.sprite`); hojas de prueba por código: el esbirro en **pixel art grueso** (sellos ASCII a mano en `tools/sprites/draw_esbirro.py`, 24 px/m, `flat_light`; estilo a confirmar por David antes de pasar los demás) y el resto con `tools/sprites/draw_monsters.py` (formas en 2,5D); guía de estilo y formato para el arte definitivo en `tools/sprites/README.md`; Opciones → Enemigos vuelve al modelo 3D (`EnemyVisual`). Ambos extienden `EnemyBody`, que es lo único que usa `RunController`. Modelos 3D: esqueleto realista CC0 (Kotelevets) + animaciones CC0 de Quaternius (UAL1/UAL2), armas de KayKit (CC0); armado con `tools/assets/` (`build_skeletons.py` con `bpy` + `process_enemies.mjs`) → `assets/enemies/`, animados por `scripts/world/enemy_visual.gd` según `species.json → visual`. Los goblins quedan `"activo": false` (sin licencia).
- Estilo Lunacid: biomas por piso en `floors.json → themes`, texturas CC0 (WRAD) en `assets/textures/<bioma>/`, imagen PS1 por `scripts/world/retro_view.gd` (presets en `balance.json → render.presets`).
- Las carpetas `GoblinPack_Free/`, `Gothic Furniture/` y `PSX Dungeon Boxes and Barrels Pack/` son las descargas originales: llevan `.gdignore`.

## Verificación

Godot en este entorno: `godot` (symlink a `/opt/godot/Godot_v4.7.2-stable_linux.x86_64`). Si no está, bajar el zip `Godot_v4.7.2-stable_linux.x86_64.zip` de los releases de GitHub. En la PC de David: `C:\Users\David Quezada\Downloads\Godot_v4.7.2-stable_win64.exe (1)`.

```
tools/verify.sh       # todo: import + lint + arranque (--quit-after 120) + tests + smoke test
```

- `tools/verify.sh` copia `tools/strict_warnings.cfg` como `override.cfg` mientras corre: Godot no imprime warnings de GDScript fuera del editor, así que se suben a error para detectarlos. `override.cfg` está en `.gitignore`; nunca se commitea.
- `tools/lint.tscn` carga todos los scripts/escenas propios (no addons) y revisa que cada `DataRegistry.t("clave")` exista en `data/texts.json`.
- Tests: `res://tests/TestRunner.tscn` (unitarios en `tests/unit/`) y `res://tests/SmokeTest.tscn` (de punta a punta, con guardado aparte).
- Kit y Theme: después de tocar `data/ui_palette.json`, `tools/ui/make_ui_kit.py` o la lista de íconos, correr `python3 -I tools/ui/make_ui_kit.py`; después de eso o de tocar `ui_style.gd`/`theme_builder.gd`, regenerar con `godot --headless --path . res://tools/build_theme.tscn`. Commitear `ui/kit/` y `ui/theme_main.tres` (`tests/unit/test_ui_kit.gd` falla si quedaron viejos o si la paleta del JSON y la de `UIStyle` no coinciden).
- Balance: `godot --headless --path . res://tools/balance_sim.tscn` (con niveles; `-- --set=ruta=valor` prueba valores sin tocar `balance.json`).
- Capturas reales (para revisar UI): `tools/screenshot.tscn` con `xvfb-run` y `--rendering-driver opengl3` (ver su encabezado; `--floor=N`, `--test-room`). Enemigos: `tools/enemy_preview.tscn`.
- Assets libres: pipeline en `tools/assets/` (Node + Python, ver su README). Solo CC0/CC-BY verificados leyendo el LICENSE.
- Comandos sueltos: `godot --headless --path . --import` y `godot --headless --path . --quit-after 120`.

## Convenciones y gotchas (leer antes de editar)

- **Tipado explícito siempre. Las advertencias son errores en este proyecto.** `var x := dict["k"]` o `array[i]` sobre Dictionary/Array sin tipar falla → usar `var x: Tipo = ...` o `var x: Variant = ...`. `const DIRS: Array[Vector2i]`.
- **JSON → números float.** Todo número de `data/*.json` llega como `float`; `DataRegistry` normaliza a `int` los campos enteros al validar.
- **Textos**: todo texto visible sale de `data/texts.json` vía `DataRegistry.t("clave", [args])`. Los nombres/descripciones de especies, objetos, etc. salen de sus propios JSON.
- **Rotación**: en Godot el giro positivo es antihorario; `GridPlayer` usa signo negativo. No cambiar el orden de `DIRS` sin revisarlo.
- **UI fuera del SubViewport.** Lo 3D va en un SubViewport de baja resolución (filtro nearest); `CanvasLayer` de UI es hijo directo de la escena, a resolución nativa. Ojo: con `SubViewportContainer.stretch = true` el tamaño del SubViewport lo decide el contenedor (`stretch_shrink`), no `viewport.size`.
- **Shader globals PSX**: `_ensure_psx_shader_globals()` debe correr antes de crear materiales PSX; sin eso, el Play sale negro. Solo registra los globals que falten (project.godot ya los declara).
- **Parche en LevelBlock**: `level_block_node.gd` tiene `@export var material:Material` (antes `BaseMaterial3D`) para aceptar `PsxMaterial3D`. Reaplicar si se actualiza el addon. **Parches en PSX** (lista completa en `docs/ESTADO_TECNICO_PROTOTIPO.md`): `PsxConversionDialog.gd` líneas 199/256 tipadas como `Variant`; en `psx.gdshaderinc` la niebla y el afín (antes no funcionaban), la protección de z=0 y los `i_precision_*` como constantes; `#define SHADING_UNSHADED` en `PsxMaterial3D.gd`. Las permutaciones nuevas de `addons/psx/shaders/cache/` se commitean.
- **La trama PS1 va dentro del SubViewport** (`RetroView`), no en el autoload del addon (`psx_bit_depth` = 0): si no, cubre la UI.
- `CombatManager`: pasar datos por propiedades ANTES de `add_child`; `party_roster` es `Array` (no `Array[Dictionary]`). Trabaja sobre copias y nunca muta `GameState`: termina con `combat_ended(outcome, result)` (`victory|defeat|fled`, `{hp, items_used, soul_pick}`) y `RunController` lo aplica.
- **GameState nunca escribe en MetaState.** La run solo toca lo persistente en `RunSummary`, con `RunRewards.compute()` + `MetaState.apply_run_result()` (una vez) + `SaveSystem.save_meta()`.
- **UI**: nada de colores ni estilos sueltos. Usar las variaciones del Theme y los componentes `UI*`; los colores solo vienen de `UIStyle` (`tools/lint` rechaza `Color(` literales en `scripts/ui`, `scripts/combat` y `SceneRouter`). Cada pantalla extiende `UIScreen` (o `ListDetailScreen`) y deja el foco inicial puesto. Todo texto gótico va con `UIGothicLabel` y sin símbolos (sus claves fijas, en `UIGothicLabel.FIXED_KEYS`). Íconos con `UIIcon.make(id, rampa)`, sonidos con `SceneRouter.play_ui(tipo)`. Imágenes de píxel siempre a escala entera (retratos de 96/64 px a ×1 o ×2).
- **Licencia**: el pack de goblins no trae licencia; verificar antes de publicar.
- **Cambios de diseño grandes: confirmar con el usuario**; él decide el rumbo.
