# Guía de trabajo para Claude Code — del prototipo al roguelike jugable

Documento maestro de **qué hay que hacer, en qué orden y con qué criterio de
"terminado"**. Complementa a `CLAUDE.md` (reglas), `docs/PLAN_DE_DISENO_ROGUELIKE.md`
(diseño) y `docs/ESTADO_TECNICO_PROTOTIPO.md` (arquitectura actual).

> **Estado (19-oct-2026):** fases 0–9 completas; todos los checkboxes están marcados. Las desviaciones y decisiones tomadas están anotadas con *Nota* en cada punto. El detalle técnico está en `docs/ESTADO_TECNICO_PROTOTIPO.md` y los valores por defecto en `README.md`.

**Objetivo de esta etapa:** tener un roguelike **completo y probable de punta a
punta** (hub → run → muerte/retiro → resumen → hub) con **todos los menús y
sistemas implementados con un diseño visual decente y consistente**, para que
David pueda hacer pruebas de juego reales. No es la versión final de arte ni de
balance: es una versión *jugable, legible y ajustable*.

---

## 0. Reglas de trabajo (leer primero)

1. **Verifica todo.** Tras cada cambio: `godot --headless --path . --import` y
   `godot --headless --path . --quit-after 120`. Cero errores y cero warnings
   (los warnings son errores en este proyecto). Si no encuentras el ejecutable
   de Godot, pregunta la ruta a David una sola vez y anótala en `CLAUDE.md`.
2. **Tipado explícito siempre** (ver gotchas en `CLAUDE.md`).
3. **Datos fuera del código.** Especies, almas, objetos, mejoras, condiciones de
   desbloqueo y números de balance viven en `data/` (JSON o `Resource`), no
   hardcodeados en `Main.gd`.
4. **Commits pequeños y por fase** (un commit por hito de esta guía). Mensajes en
   español, imperativo. Respeta la atribución indicada por el entorno.
5. **No inventes diseño en lo confirmado.** Lo ✅ de `PLAN_DE_DISENO_ROGUELIKE.md`
   es ley. Lo 🟡 tiene un **valor por defecto** en la sección 9 de esta guía:
   impleméntalo parametrizado (fácil de cambiar) y avísale a David en el resumen
   final, no lo bloquees preguntando.
6. **Diferido = no tocar:** razas, árbol de habilidades, crafting, eventos
   mensuales, 100 objetos numerados. (Niveles/EXP **por expedición** los pidió
   David el 20-oct-2026 y ya están: ver `docs/ESTADO_TECNICO_PROTOTIPO.md`.)
7. **Al terminar cada fase:** corre el *smoke test* (sección 8), actualiza
   `docs/ESTADO_TECNICO_PROTOTIPO.md` y marca los checkboxes de esta guía.
8. Si algo del prototipo estorba (p. ej. `Main.gd` de ~485 líneas), refactoriza,
   pero **sin romper lo que David ya validó**: movimiento en grilla, look PSX,
   flujo de combate y de almas.

---

## 1. Fase 0 — Base verificable y limpieza

- [x] Ejecutar import y quit-after; listar y corregir **todos** los errores.
- [x] Resolver el error abierto "variable type is being inferred from a Variant
      value" (líneas 199/256 de un archivo sin identificar). Buscar con grep
      `:=` sobre valores de Dictionary/Array en `scripts/` y en addons propios.
- [x] Crear escena de arranque real: `scenes/Boot.tscn` → decide si ir a Hub o
      a Run (por ahora al Hub). Configurar `run/main_scene`.
- [x] Crear `.gitignore` de Godot (`.godot/`, `*.import` no, builds, etc.) y
      `git init` si no hay repo.
- [x] Mover el contenido de `SPECIES_DB` a `data/species.json` y cargarlo con un
      `DataRegistry` (ver Fase 1). El juego debe verse y jugarse **igual** que antes.

**Hecho cuando:** el prototipo actual corre idéntico, sin warnings, con datos en JSON.

---

## 2. Fase 1 — Arquitectura base

### 2.1 Estructura de carpetas objetivo

```
res://
├── autoload/        EventBus.gd, GameState.gd, MetaState.gd, SaveSystem.gd,
│                    DataRegistry.gd, SceneRouter.gd, DebugTools.gd
├── data/            species.json, souls.json, items.json, upgrades.json,
│                    unlocks.json, floors.json, balance.json
├── scenes/
│   ├── Boot.tscn  Hub.tscn  Run.tscn  RunSummary.tscn
│   └── ui/        (pantallas y componentes reutilizables)
├── scripts/
│   ├── run/       RunController.gd, FloorGenerator.gd, FloorBuilder.gd
│   ├── combat/    CombatManager.gd (+ lo que se separe)
│   ├── world/     GridPlayer.gd, Enemy spawners, Pickups
│   └── ui/        theme_builder.gd, componentes
├── tests/           smoke_test.gd, unit tests de sistemas
└── docs/
```

### 2.2 Autoloads (singletons)

| Autoload | Responsabilidad |
|---|---|
| `EventBus` | Señales globales: `enemy_killed(species_id, first_time)`, `floor_reached(n)`, `boss_defeated(floor)`, `soul_acquired`, `item_picked`, `run_started`, `run_ended(result)`, `coins_changed`, `unlock_earned(id)`. Los desbloqueos escuchan esto. |
| `DataRegistry` | Carga `data/*.json` al inicio, valida esquema (falla ruidosamente con mensaje claro) y expone `get_species(id)`, `get_item(id)`, etc. |
| `GameState` | **Estado de la run actual** (se descarta al terminar): party, almas, inventario, piso, semilla, monedas de la run, stats de la run. |
| `MetaState` | **Estado persistente**: monedas totales, niveles de mejora, desbloqueos, bestiario, estadísticas globales, ajustes. |
| `SaveSystem` | Guardar/cargar `MetaState` en `user://save.json` (con `version`, escritura atómica `.tmp` → rename, copia `.bak`, migraciones). Autoguardado al terminar la run y al comprar mejoras. |
| `SceneRouter` | Cambio de escena con fundido a negro corto (reutilizable). |
| `DebugTools` | Panel de debug (sección 7). Solo activo en builds de debug. |

Regla de oro: **`GameState` nunca escribe en `MetaState` directamente**; al
terminar la run, `RunSummary` calcula las recompensas y se aplican de una vez.

### 2.3 Hecho cuando

- [x] Autoloads registrados en `project.godot`, sin dependencias circulares.
- [x] `DataRegistry` valida y falla con mensaje útil ante JSON roto.
- [x] Guardar/cargar `MetaState` probado con un test (escribir, reiniciar, leer).

---

## 3. Fase 2 — Bucle de run

```
Hub ──[Iniciar expedición]──▶ Run (piso 1) ──▶ … ──▶ Jefe de piso
                                   │                    │
                                   │              [retirarse | continuar]
                                   ▼                    ▼
                                Muerte ────────▶ RunSummary ──▶ Hub
```

### 3.1 RunController

- [x] `start_run(seed)`: crea `GameState` limpio, aplica mejoras de `MetaState`
      a los stats base del equipo, arma el pool de objetos disponible
      (solo los desbloqueados), genera el piso 1.
- [x] `advance_floor()`: escaleras/portal al final del piso (tras el jefe).
- [x] `retreat()`: permitido **solo** en puntos de retiro (tras jefe de piso)
      o con el objeto "Sello de Retiro" (ver objetos). Retirarse = run "exitosa
      parcial": conserva monedas de la run.
- [x] `die()`: permadeath. Se pierde todo lo de la run; se conserva una fracción
      de monedas (`balance.json: coin_keep_on_death`, defecto 0.5).
- [x] Al terminar, emitir `run_ended` y pasar a `RunSummary`.

### 3.2 Pantalla de resumen de run

Ver wireframe en sección 6. Debe mostrar: resultado (muerte/retiro/victoria),
piso alcanzado, tiempo, monedas ganadas (desglosadas), kills, **especies nuevas
al bestiario** (con el bonus de primera kill), **desbloqueos obtenidos** (con
animación de "revelar" al pulsar Continuar), almas obtenidas (solo informativo).

### 3.3 Hecho cuando

- [x] Se puede jugar: Hub → run → morir → resumen → Hub, con monedas persistentes
      tras cerrar y reabrir el juego.
- [x] Retirarse tras el jefe del piso 1 funciona y conserva el 100% de monedas.

---

## 4. Fase 3 — Sistemas de juego

### 4.1 Pisos y generación

Recomendación: **generador propio simple** que produzca el mismo formato de
mapa (`Array` de celdas) que ya consume `Main._build_rooms_with_levelblock()`.
Algoritmo sugerido: BSP o salas + pasillos sobre grilla, con semilla
(`RandomNumberGenerator`) para reproducir bugs.

- [x] Evaluar `addons/dungeon_crawler_3d` máx. 1 hora; si exige rehacer demasiado,
      descartarlo y documentarlo en `ESTADO_TECNICO_PROTOTIPO.md`.
      *Nota: descartado (salas 3D prearmadas + grafo propio); generador propio con semilla.*
- [x] `FloorGenerator.generate(floor_index, seed) -> FloorData` con: grilla,
      posición de inicio, spawns de enemigos (por especie/rango según piso),
      cofres/objetos, sala del jefe, salida.
- [x] `FloorBuilder` construye la geometría (LevelBlock + PSX) y cajas/barriles
      como decoración.
- [x] **Minimapa** simple (celdas visitadas) — ver UI.
- [x] Tamaño por defecto: piso 1 ≈ 25×25, crece ~+5 por piso (parametrizado).
- [x] Rangos por piso (defecto): piso 1 → rangos 9–8; piso 2 → 8–6; piso 3 → 7–5;
      piso 4 → 6–3; piso 5 → 5–2; jefe = rango del piso − 1 (más fuerte).

### 4.2 Combate (completar)

Ya existe: ataque, habilidad (activa del alma), defender, flujo de alma.

- [x] **Ataque sorpresa**: si el jugador inicia el contacto (bump) → primer turno
      gratis + daño ×1.5 en ese turno (`balance.json`). Si el enemigo te alcanza
      por la espalda/alerta → penalización simétrica (opcional).
- [x] Menú de combate con: Atacar · Habilidad · Defender · **Objeto** · (Huir, 🟡
      con probabilidad según rangos).
- [x] **Uso de objetos** en combate (ver 4.4).
- [x] Orden de turnos mostrado visualmente (cola de turnos).
- [x] Números de daño flotantes, barras de HP, parpadeo al recibir golpe.
- [x] **Derrota** del equipo completo → `die()`.
- [x] Pantalla de resumen post-combate **separada**: XP/monedas, bonus de primera
      kill, y la **revelación del alma al pulsar Continuar** (el tiempo de carga
      de volver a exploración debe ser el mismo para no hacer esperar).

### 4.3 Almas

- [x] Datos en `data/souls.json` (activa, pasiva opcional con `effect`,
      `stat_modifiers`, rango, especie).
- [x] Capacidad de almas por personaje **parametrizada** (defecto 1; subible por
      mejora de meta o por objeto de run).
      *Nota: la sube el objeto Amuleto de hueso; no hay mejora de meta para esto (no estaba en la tabla de 4.6).*
- [x] Curva de drop (defecto): normales 8% × factor de rango; élite 25%; **jefe
      100%**. Flag de debug para forzar.
- [x] Más tipos de efecto de pasiva (mínimo 3 nuevos, p. ej. `lifesteal_pct`,
      `crit_chance`, `coin_bonus_pct`, `thorns_flat`). Agregar solo con `case` +
      texto de hint, sin tocar datos viejos.
- [x] Reemplazo de alma cuando el personaje está lleno: diálogo "Reemplazar /
      Descartar".
- [x] Las almas **no** pasan al `MetaState`.

### 4.4 Objetos de run (con desbloqueo por condiciones)

`data/items.json`. Cada objeto: `id`, `nombre`, `descripcion`, `tipo`
(consumible / pasivo de run), `efecto`, `peso_aparicion`, `unlock_id` (null =
disponible de inicio). Lista inicial sugerida (8):

| Objeto | Efecto | Disponible |
|---|---|---|
| Poción menor | Cura 8 HP en combate o fuera | Inicio |
| Venda | Cura 4 HP fuera de combate | Inicio |
| Antorcha vieja | +visión (reduce niebla) en el piso | Inicio |
| Sello de Retiro | Permite retirarse en cualquier momento (se rompe al salir) | Condición: llegar al piso 3 |
| Talismán de goblin | +1 ataque toda la run | Condición: matar 10 goblins (acumulado) |
| Bomba de humo | Huir garantizado de un combate (no jefe) | Condición: huir 3 veces |
| Amuleto de hueso | +1 capacidad de alma de un personaje | Condición: derrotar al esqueleto guardián |
| Poción mayor | Cura 20 HP | Condición: completar una run sin usar pociones menores |

- [x] Inventario de run con capacidad (defecto 8) y UI.
- [x] Objetos en el suelo / cofres con tabla de aparición ponderada que **solo
      incluye desbloqueados**.
- [x] Los objetos de run **se pierden al terminar la run** (no se guardan).

### 4.5 Desbloqueos por condición

- [x] `data/unlocks.json`: `id`, `nombre`, `descripcion` (texto de condición),
      `condicion` (`tipo` + `parametros`), `recompensa` (id de objeto).
- [x] Tipos de condición mínimos: `kill_species_total {species, n}`,
      `reach_floor {n}`, `defeat_boss {floor|id}`, `win_run`, `flee_count {n}`,
      `no_item_use_run {item}`, `coins_total {n}`.
- [x] `UnlockEvaluator` escucha `EventBus`, lleva progreso (p. ej. 7/10) en
      `MetaState` y emite `unlock_earned`. Los desbloqueos se **anuncian en
      el resumen de run**, no en pleno juego.
      *Nota: GameState acumula los hechos de la run; UnlockEvaluator (puro) los evalúa al terminar junto con `MetaState.progress`, y RunSummary emite `unlock_earned`. Así se respeta "GameState nunca escribe en MetaState".*
- [x] Hub muestra todos los desbloqueos: obtenidos, en progreso (barra) y
      bloqueados (condición visible; las ocultas pueden mostrarse como "???").

### 4.6 Monedas y mejoras (meta)

- [x] Monedas: por kill `= (11 - rango)`; jefe `= 25 × piso`; cofres según piso;
      bonus de primera kill de especie `= 10 × (11 - rango)` (una sola vez).
- [x] `data/upgrades.json`, con **tope por mejora** (defecto 5 niveles) y coste
      creciente (`base × nivel`):

| Mejora | Efecto por nivel | Coste base |
|---|---|---|
| Vitalidad | +2 HP máx. a todo el equipo | 20 |
| Fuerza | +1 ataque | 30 |
| Botín | +5% monedas | 25 |
| Provisiones | +1 Poción menor al inicio | 40 |
| Sabiduría | +2% prob. de alma | 50 |

- [x] Comprar es instantáneo y autoguardado; mostrar coste, nivel y efecto actual
      vs. siguiente.
- [x] Verificar que **todas las mejoras maxeadas** no vuelvan trivial el piso 1
      (ver balance en sección 9).
      *Nota: `tools/balance_sim.tscn`. Fuerza bajó a +0,6 ATK/nivel y Vitalidad a +1,6 HP/nivel (redondeo del total).*

### 4.7 Bestiario (persistente)

- [x] `MetaState.bestiary[species_id] = {kills, first_kill_run, souls_taken}`.
- [x] Pantalla de bestiario en el Hub: lista de especies (vistas/no vistas),
      rango, stats, alma que da (revelada solo si se obtuvo alguna vez).
- [x] Bonus de primera kill se otorga una vez por especie (en el resumen).

### 4.8 Jefes de piso

- [x] Un jefe por piso (5), reutilizando modelos con escala/color distinto si no
      hay arte propio. Stats = `stats_for_rank(rango_jefe) × 1.5`.
- [x] Siempre sueltan alma (100%) y abren **punto de retiro** + salida.

---

## 5. Fase 4 — Hub y navegación de menús

Hub **mínimo**: una sola pantalla de menú (fondo PSX estilizado, p. ej. la
cámara girando lentamente sobre una sala con niebla), sin exploración.

Menú principal del Hub:

1. **Iniciar expedición**
2. **Mejoras** (monedas)
3. **Objetos y desbloqueos**
4. **Bestiario**
5. **Estadísticas** (runs, mejor piso, kills, tiempo)
6. **Opciones** (volumen, pantalla completa, escala UI, controles, idioma ES)
7. **Salir**

Menús en run: **Pausa** (Esc: continuar, estado, inventario, opciones, abandonar
run con confirmación), **Estado** (Tab, ya existe: mejorarlo con pestañas Equipo /
Almas / Objetos), **Inventario**, **Minimapa**.

- [x] Todo navegable con **teclado y mando** (focus ring visible, orden lógico,
      Esc/B = atrás).
- [x] Cada pantalla tiene estado vacío legible (p. ej. "Aún no has encontrado
      esta criatura").

---

## 6. Diseño visual de menús y UI (OBLIGATORIO en esta etapa)

**Mandato:** *todos* los menús y sistemas deben tener un diseño decente y
consistente desde ya. Nada de botones grises por defecto de Godot. La meta es que
David pueda probar **sintiendo** el juego, no leyendo texto crudo.

### 6.1 Dirección visual

Gótico oscuro + PS1: fondos casi negros con tinte azul/verde apagado, bordes
finos de piedra/metal envejecido, acentos cálidos (ámbar) para lo interactivo y
rojo apagado para peligro. Pixelado nítido (sin suavizado), esquinas rectas.

### 6.2 Design system (un solo `Theme`)

Crear `scripts/ui/theme_builder.gd` que **construye por código** un `Theme` y lo
guarda en `res://ui/theme_main.tres`; aplicarlo como tema por defecto del
proyecto (`gui/theme/custom`). Todo estilo sale de aquí; prohibido estilizar
nodos sueltos con colores sueltos.

Paleta base (ajustable, definida como constantes en un solo lugar):

| Token | Hex | Uso |
|---|---|---|
| `bg_deep` | `#0c0d12` | Fondo de pantallas |
| `panel` | `#161821` | Paneles |
| `panel_alt` | `#1d2030` | Paneles anidados / hover suave |
| `border` | `#3a3f55` | Bordes |
| `border_focus` | `#e0a63a` | Foco / selección |
| `text` | `#d8d4c8` | Texto principal |
| `text_dim` | `#8a8778` | Texto secundario |
| `accent` | `#e0a63a` | Acento (ámbar) |
| `good` | `#6fae5a` | HP, éxito |
| `danger` | `#b04a4a` | Daño, peligro |
| `soul` | `#6ab7d9` | Almas / magia |
| `coin` | `#e8c85a` | Monedas |

- Tipografía: una fuente pixel libre (licencia OFL, p. ej. *Pixelify Sans*,
  *VT323* o *Silkscreen*) en `assets/fonts/` con su licencia. Si no puedes
  descargarla, usa la fuente por defecto con `antialiasing` desactivado y deja
  una constante `FONT_PATH` lista para cambiarla. Tamaños: título 28, subtítulo
  20, cuerpo 16, detalle 13. Filtro de textura **Nearest**.
- Espaciado en múltiplos de 4 px; márgenes de pantalla 24 px; botones de al
  menos 40 px de alto.
- Estados de botón: normal / hover / pressed / focus / disabled, todos con
  `StyleBoxFlat` (borde 2 px, sin bordes redondeados).

### 6.3 Componentes reutilizables (escenas en `scenes/ui/`)

`MenuButton` · `Panel` con título · `StatBar` (HP/progreso, con valor numérico) ·
`ItemSlot` / `SoulCard` (nombre, rango como insignia, activa/pasiva con colores) ·
`RankBadge` (10→1, color por rango) · `Tooltip` (al foco/hover) ·
`ConfirmDialog` · `Toast` (avisos breves) · `ProgressBar` de desbloqueo ·
`TabBar`. Cada pantalla se arma **solo** con estos componentes.
*Nota: son clases (`class_name`) en `scripts/ui/components/` armadas por código, como el resto de la UI del proyecto; la "UI Gallery" sí es una escena (`scenes/ui/UIGallery.tscn`).*

### 6.4 Wireframes (referencia; adaptar proporciones a 16:9)

**Hub**
```
┌──────────────────────────────────────────────────────────────┐
│  [título del juego]                      Monedas: ◈ 1,240     │
│                                                              │
│   ▶ Iniciar expedición                ┌────────────────────┐ │
│     Mejoras                           │ Última run         │ │
│     Objetos y desbloqueos             │ Piso 3 · 18 kills  │ │
│     Bestiario                         │ Murió ante: Esq... │ │
│     Estadísticas                      │ ◈ +86              │ │
│     Opciones                          └────────────────────┘ │
│     Salir                                                    │
└──────────────────────────────────────────────────────────────┘
```

**Mejoras**
```
┌ MEJORAS ─────────────────────────────── ◈ 1,240 ─┐
│ ▶ Vitalidad   ■■■□□  +2 HP máx.   Siguiente: 60 ◈ │
│   Fuerza      ■□□□□  +1 ataque    Siguiente: 60 ◈ │
│   Botín       □□□□□  +5% monedas  Siguiente: 25 ◈ │
│ ───────────────────────────────────────────────── │
│ Descripción / efecto actual → siguiente            │
│ [Comprar]                                [Volver]  │
└────────────────────────────────────────────────────┘
```

**Combate** (UI sobre la vista en primera persona)
```
┌──────────────────────────────────────────────────────────────┐
│ [Enemigo: Goblin  R9 ▮▮▮▮▯▯]            Cola: B › E › G › …  │
│                                                              │
│                 (vista 3D del enemigo)                       │
│                                                              │
│ ┌ Bjorn ▮▮▮▮▮▯ 14/18 ┐ ┌ Elena ▮▮▮▯▯▯ 8/16 ┐  ┌ Acciones ─┐ │
│ │ Alma: Golpe Bárbaro │ │ (sin alma)         │  │▶Atacar    │ │
│ └─────────────────────┘ └────────────────────┘  │ Habilidad │ │
│ Registro: «Bjorn golpea al Goblin (5)»          │ Defender  │ │
│                                                 │ Objeto    │ │
│                                                 └───────────┘ │
└──────────────────────────────────────────────────────────────┘
```

**Resumen de run**
```
┌ EXPEDICIÓN TERMINADA ─ Muerte · Piso 3 · 24:12 ──────────────┐
│ Monedas: kills +42 · jefe +25 · primera kill +30 = ◈ 97       │
│ Bestiario: ★ Esqueleto guardián (nuevo)                      │
│ Desbloqueo: «Amuleto de hueso» — ¡Presiona CONTINUAR!        │
│                                              [ Continuar ]   │
└──────────────────────────────────────────────────────────────┘
```

**HUD de exploración**: esquina sup. izq. HP del equipo (barras compactas); sup.
der. minimapa 7×7 celdas + brújula N/E/S/O; inf. centro mensajes breves; inf.
der. monedas de la run y piso. Mantener el HUD **fuera del SubViewport** (nítido).

### 6.5 Usabilidad mínima

- [x] Foco inicial correcto en cada pantalla; nunca queda sin foco.
- [x] Textos largos con `autowrap`; nada se corta a 1280×720 ni a 1920×1080.
- [x] Escalado de UI configurable (80–150%) en Opciones.
- [x] Transiciones cortas (≤ 200 ms) y sonidos placeholder opcionales (clic, hover).
- [x] Texto del juego centralizado en un solo lugar (diccionario/CSV) para poder
      pulirlo después.

---

## 7. Herramientas de prueba y debug (para que David pruebe rápido)

Panel de debug (F1, solo en debug) con botones:

- Dar monedas (+100 / +1000) · Subir/bajar todas las mejoras
- Desbloquear todo / Bloquear todo
- Saltar al piso N · Matar enemigo del frente · Curar equipo
- Forzar drop de alma (checkbox) · Forzar ataque sorpresa
- God mode / Un golpe
- Fijar semilla de la run (campo de texto) y mostrarla siempre en el HUD de debug
- Reiniciar guardado (con confirmación)
- Mostrar FPS, celda actual y estado de `GameState`

- [x] Un **modo "Sala de pruebas"** accesible desde Opciones/debug que cargue la
      sala 15×9 original con los 5 enemigos conocidos, para validar combate y almas.
- [x] Log a archivo `user://debug.log` con eventos de `EventBus`.

---

## 8. Pruebas automáticas

- [x] `tests/smoke_test.gd`: escena headless que recorre Boot → Hub → inicia run
      → avanza un piso con la semilla fija → fuerza un combate ganado → fuerza
      muerte → resumen → vuelve al Hub, y sale con código 0 si todo pasó.
      Ejecutar con `godot --headless --path . --script tests/smoke_test.gd` (o
      escena equivalente con `--quit-after`).
- [x] Tests unitarios (script simple con asserts) para: `stats_for_rank`, curva de
      drop de almas, evaluador de desbloqueos, costes de mejoras con tope,
      guardado/carga/migración de versión, cálculo de recompensas de run.
- [x] Carga de **todas** las escenas de UI en headless para detectar errores de
      parseo/recursos faltantes.
- [x] Documentar cómo correr todo en `CLAUDE.md` (sección "Verificación").

---

## 9. Valores por defecto de las decisiones abiertas (🟡)

Implementar en `data/balance.json`, cambiables sin tocar código. Informar a
David de estos valores en el resumen final.

| Decisión | Valor por defecto |
|---|---|
| Pisos por run | 5 (+ jefe cada uno) |
| Duración objetivo | 45–60 min |
| Equipo | 2 personajes (Bjorn, Elena); soportar 1–3 por datos |
| Impuesto | **No implementar** como sumidero; en su lugar `coin_keep_on_death = 0.5` |
| Alcance de bestiario | Persistente entre runs; primera kill = bonus una sola vez |
| Capacidad de alma | 1 por personaje (mejora/objeto la sube a 2) |
| Capacidad de inventario | 8 objetos |
| Tope de mejoras | 5 niveles c/u |
| Huir | Disponible, éxito = 50% ± 10% por diferencia de rango; no en jefes |

**Objetivo de balance para pruebas:** una run "normal" sin mejoras debería llegar
al piso 2–3; con todas las mejoras maxeadas, al piso 4–5 con riesgo real. Si el
piso 1 queda trivial con todo maxeado, reducir el valor por nivel (no el tope).

---

## 10. Orden de ejecución y entregables

| # | Hito | Resultado verificable |
|---|---|---|
| 0 | Base verificable | Import + quit-after sin errores; datos en JSON |
| 1 | Arquitectura | Autoloads, DataRegistry, SaveSystem con test |
| 2 | Theme + componentes UI | Pantalla de demo "UI Gallery" con todos los componentes |
| 3 | Hub + menús (mejoras, desbloqueos, bestiario, stats, opciones) | Navegables con teclado/mando |
| 4 | Bucle de run + resumen | Hub → run → muerte → resumen → Hub con persistencia |
| 5 | Generación de pisos + minimapa + HUD | 5 pisos con semilla |
| 6 | Combate completo (sorpresa, objetos, huir, resumen, jefe) | Run jugable de punta a punta |
| 7 | Almas, objetos, desbloqueos y bestiario conectados | Evaluador y UI funcionando |
| 8 | Debug panel + sala de pruebas + smoke test | `smoke_test` verde |
| 9 | Pulido de UI y balance inicial | Checklist de 6.5 y objetivos de la sección 9 |

Crear primero la **"UI Gallery"** (hito 2) ayuda mucho: permite revisar el diseño
de todos los componentes en una sola escena antes de armar pantallas.

**Entrega final de la etapa:** build jugable desde el editor (F5), `README` con
controles, lista de valores por defecto usados, lista de cosas pendientes/diferidas
y de decisiones que David debe revisar. Actualizar `CLAUDE.md` y
`docs/ESTADO_TECNICO_PROTOTIPO.md`.

---

## 11. Qué NO hacer

- No reescribir desde cero lo que David ya validó (movimiento, look PSX, flujo de
  almas por personaje).
- No introducir razas, crafting ni eventos mensuales. Niveles/EXP: solo por
  expedición, como están (nada que persista entre runs sin preguntarle a David).
- No persistir almas entre runs.
- No desbloquear objetos con monedas (solo condiciones).
- No dejar estilos sueltos fuera del `Theme` ni textos duros dispersos.
- No subir builds, `.godot/` ni binarios grandes al repo.
- No usar assets sin licencia clara en algo que se vaya a publicar (goblins: sin
  licencia confirmada).
