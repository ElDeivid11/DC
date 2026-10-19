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

Ver `docs/ESTADO_TECNICO_PROTOTIPO.md` (arquitectura completa, actualizada por fase).

- Datos de juego en `data/*.json`, cargados y validados por el autoload `DataRegistry` (falla ruidosamente con archivo/campo/línea).
- Plugins: `addons/psx` (PSX Visuals), `addons/level_block` (parcheado), `addons/dungeon_crawler_3d` y `addons/kaykit_dungeon_remastered` (copiados, NO conectados).
- Las carpetas `GoblinPack_Free/`, `Gothic Furniture/` y `PSX Dungeon Boxes and Barrels Pack/` son las descargas originales: llevan `.gdignore` (Godot no las importa). El juego usa las copias de `assets/`.

## Verificación

Godot en este entorno: `godot` (symlink a `/opt/godot/Godot_v4.7.2-stable_linux.x86_64`). Si no está, bajar el zip `Godot_v4.7.2-stable_linux.x86_64.zip` de los releases de GitHub. En la PC de David: `C:\Users\David Quezada\Downloads\Godot_v4.7.2-stable_win64.exe (1)`.

```
tools/verify.sh       # todo: import + lint + arranque (--quit-after 120) + tests + smoke test
```

- `tools/verify.sh` copia `tools/strict_warnings.cfg` como `override.cfg` mientras corre: Godot no imprime warnings de GDScript fuera del editor, así que se suben a error para detectarlos. `override.cfg` está en `.gitignore`; nunca se commitea.
- `tools/lint.tscn` carga todos los scripts/escenas propios (no addons) y revisa que cada `DataRegistry.t("clave")` exista en `data/texts.json`.
- Comandos sueltos: `godot --headless --path . --import` y `godot --headless --path . --quit-after 120`.

## Convenciones y gotchas (leer antes de editar)

- **Tipado explícito siempre. Las advertencias son errores en este proyecto.** `var x := dict["k"]` o `array[i]` sobre Dictionary/Array sin tipar falla → usar `var x: Tipo = ...` o `var x: Variant = ...`. `const DIRS: Array[Vector2i]`.
- **JSON → números float.** Todo número de `data/*.json` llega como `float`; `DataRegistry` normaliza a `int` los campos enteros al validar.
- **Textos**: todo texto visible sale de `data/texts.json` vía `DataRegistry.t("clave", [args])`. Los nombres/descripciones de especies, objetos, etc. salen de sus propios JSON.
- **Rotación**: en Godot el giro positivo es antihorario; `GridPlayer` usa signo negativo. No cambiar el orden de `DIRS` sin revisarlo.
- **UI fuera del SubViewport.** Lo 3D va en un SubViewport de baja resolución (filtro nearest); `CanvasLayer` de UI es hijo directo de la escena, a resolución nativa. Ojo: con `SubViewportContainer.stretch = true` el tamaño del SubViewport lo decide el contenedor (`stretch_shrink`), no `viewport.size`.
- **Shader globals PSX**: `_ensure_psx_shader_globals()` debe correr antes de crear materiales PSX; sin eso, el Play sale negro. Solo registra los globals que falten (project.godot ya los declara).
- **Parche en LevelBlock**: `level_block_node.gd` tiene `@export var material:Material` (antes `BaseMaterial3D`) para aceptar `PsxMaterial3D`. Reaplicar si se actualiza el addon. **Parche en PSX**: `PsxConversionDialog.gd` líneas 199/256 tipadas como `Variant`.
- `CombatManager` y `StatusMenu`: pasar datos por propiedades ANTES de `add_child`; `party_roster` es `Array` (no `Array[Dictionary]`). `CombatManager` nunca muta el estado de la run; solo reporta por señal.
- **Licencia**: el pack de goblins no trae licencia; verificar antes de publicar.
- **Cambios de diseño grandes: confirmar con el usuario**; él decide el rumbo.
