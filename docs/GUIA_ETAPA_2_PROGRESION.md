# Guía Etapa 2: progresión de personaje, retratos y correcciones

Documento de trabajo para Claude Code, del 20-oct-2026. Sale de las pruebas de
David sobre la rama `claude/dazzling-dijkstra-lqdk7k`, donde las fases 0–9 de
`docs/GUIA_CLAUDE_CODE.md` ya están hechas.

**Este documento reemplaza a `ADENDA_01_NIVELES_STATS_ITEMS_RETRATOS.md`.** Esa
adenda se escribió sin ver el código. Aquí se fusionó con un diagnóstico hecho
sobre el código real; si la encuentras, ignórala.

Las reglas de `CLAUDE.md` siguen vigentes:

- tipado explícito;
- `tools/verify.sh` en verde tras cada hito;
- textos en `data/texts.json`;
- colores solo desde `UIStyle`;
- datos en `data/*.json`;
- un commit por hito.

## 0. Qué confirmó David en esta etapa

- ✅ **Experiencia y niveles por personaje.** Antes estaba "diferido"; ahora entra.
- ✅ **Seis estadísticas** que se suben con puntos al subir de nivel, mostradas en
  un **gráfico radar hexagonal** como el de su referencia (6 ejes alrededor de un
  polígono azul relleno).
- ✅ **Cada 2 niveles, +1 espacio de alma.**
- ✅ **Uso de objetos del inventario fuera de combate.**
- ✅ **Retratos** para personajes y objetos.
- 🐞 **Los enemigos se desplazan de lado sin girar el cuerpo.**

Lo que David no fijó tiene un valor por defecto (🟡, ver §8). Va parametrizado en
`data/balance.json` y se le informa en el resumen final.

Actualizar `CLAUDE.md`: niveles/XP pasan a confirmados. Razas, crafting y eventos
mensuales siguen diferidos.

---

## 1. Hito A. Bug: enemigos que se mueven de lado sin girar

### Causa, verificada en el código

En `scripts/run/run_controller.gd`, dentro de `_enemies_act()`:

```gdscript
occupied.erase(ec)
occupied[target] = true
e["cell"] = target                 # ← se actualiza la celda PRIMERO
_turn_enemy_towards(e, target)     # ← y luego calcula target - e.cell = (0,0)
```

`_turn_enemy_towards()` calcula `target - e.cell`. Como `e.cell` ya es `target`,
la diferencia da `(0, 0)` y `DIRS.find()` devuelve `-1`, así que nunca rota. El
enemigo conserva el frente anterior y se desliza.

**No es un problema del eje del modelo.** Los modelos KayKit miran a +Z: en el
`.glb` el `control-toe-roll` está en z positivo. La fórmula `180 − facing×90` es
correcta, y `Walking_D_Skeletons` no gira la cadera. No hace falta reestructurar
con pivotes ni agregar offsets por especie para este bug.

### Qué hacer

- [ ] Girar **antes** de actualizar `e["cell"]`. Mejor aún, que la función reciba
      el origen explícito, `_turn_enemy_towards(e, from, to)`, para que no se pueda
      repetir.
- [ ] **Girar animado, no de golpe.** Hacer un tween de `rotation.y` con
      `lerp_angle`, por el camino corto y nunca 270°. Para el estilo PS1, hacerlo a
      pasos: 2 cuadros de 45° a 12 fps (~0,08 s cada uno) y **luego** el paso. Los
      180° se hacen como 90° + 90°. Si ya mira hacia donde va, no hay giro ni
      espera.
- [ ] Usar la misma función animada en `_wake_enemy`, en la emboscada y al iniciar
      combate: el enemigo gira para **mirar al equipo** antes de que empiece la
      vista de combate.
- [ ] Verificar que la **emboscada** (usa `e.facing`) siga siendo coherente ahora
      que el frente se actualiza de verdad.
- [ ] Revisar también los enemigos viejos (modelo quieto o caja), que usan la misma
      ruta.
- [ ] Debug (F1): botón "Patrulla de prueba", que haga caminar a un enemigo en los
      4 sentidos.
- [ ] Test en `tests/unit/`:
  - un paso al este da `facing == 1` y yaw objetivo 90°;
  - un giro de 180° se hace en dos pasos de 90°.
- [ ] Captura con `tools/screenshot.tscn` de un enemigo caminando de perfil, en
      `docs/capturas/`.

**Hecho cuando:** ningún enemigo se desplaza sin mirar hacia donde camina, ni al
deambular, ni al perseguir, ni al despertar, ni en la emboscada.

---

## 2. Hito B. Estadísticas: datos y fórmulas

### 2.1 Las seis estadísticas

Las siglas están adaptadas de la referencia de David (que tiene ATQ y RES). Los ejes
del radar van en este orden, en sentido horario desde arriba:

| Clave | Sigla | Nombre | Efecto por punto (valores en `data/stats.json`) |
|---|---|---|---|
| `vit` | VIT | Vitalidad | +3 HP máx. |
| `atq` | ATQ | Ataque | +1 al daño del ataque básico |
| `hab` | HAB | Habilidad | +1 al daño de la activa de las almas |
| `res` | RES | Resistencia | −0,5 de daño recibido (plano, redondeo hacia abajo; el golpe mínimo sigue siendo 1 salvo por pasivas) y +2% de bloqueo al Defender (respeta `defend_block_max`) |
| `vel` | VEL | Velocidad | Orden de turnos (ver abajo), +2% de huida y +1% de evasión (tope 25%) |
| `sue` | SUE | Suerte | +1% de crítico, +0,5 puntos porcentuales de drop de alma y +2% de monedas de la run |

- **`data/stats.json`** define clave, sigla, nombre, descripción y los coeficientes.
  La UI lee las siglas y nombres de ahí. Nada de números mágicos en el código.
- **Orden de turnos por VEL.** Hoy actúa todo el equipo y después el enemigo. El
  enemigo tiene una velocidad derivada de su rango (`stats_for_rank` agrega
  `vel`). Los personajes con VEL **menor** que el enemigo actúan después de él
  dentro de la ronda. La cola de turnos que ya se muestra en combate debe reflejarlo.
  Los empates favorecen al equipo. El ataque sorpresa y la emboscada siguen teniendo
  prioridad.
- **Evasión (nueva):** si el golpe se evade, sale un número flotante "¡Esquiva!" con
  `DimLabel`, queda en el log y el daño es 0.
- **Crítico base:** `crit_base` (por defecto 0,03) existe aunque no haya almas. Hoy
  el crítico solo sale de pasivas.

### 2.2 Datos de personajes

- En `balance.json → party[]`, cada personaje agrega `base_stats` (los 6 valores) y
  opcionalmente `portrait`. Valores sugeridos:
  - **Bjorn:** VIT 3 · ATQ 3 · HAB 1 · RES 2 · VEL 1 · SUE 1
  - **Elena:** VIT 2 · ATQ 2 · HAB 3 · RES 1 · VEL 3 · SUE 2
- **Ajustar `base_hp` y `base_atk`** para que en nivel 1 queden con los **mismos
  números de hoy** (Bjorn 20 HP y 5 ATQ; Elena 16 HP y 4 ATQ). Así el balance actual
  no se rompe de entrada.
- Las almas pueden subir estadísticas: `stat_modifiers` acepta `vit, atq, hab, res,
  vel, sue`. Las claves viejas `atk` y `max_hp` se mantienen por compatibilidad.
  Agregar estadísticas a 3–4 almas existentes para que se note.
- Las mejoras del hub (`max_hp_flat`, `atk_flat`) siguen sumando al valor final como
  hoy. Los objetos de run (Talismán) también.

### 2.3 Código

- Todo el cálculo va en **un solo lugar**: `scripts/run/character_stats.gd` (clase
  estática). Debe exponer:
  - `stat(m, key)`: base + asignados + almas + objetos;
  - `max_hp(m)`, `atk(m)`, `ability_bonus(m)`, `damage_reduction(m)`;
  - `evasion(m)`, `crit_chance(m)`, `flee_bonus(m)`, `speed(m)`;
  - `soul_drop_bonus(party)`, `coin_mult(party)`.
- `GameState.member_max_hp` y `member_atk` delegan en ella. `CombatManager` y la UI
  usan las mismas funciones; no se duplican fórmulas.
- Cada miembro de `GameState.party` agrega: `level`, `xp`, `base_stats`,
  `stats_assigned` (puntos ya confirmados) y `unspent_points`.

**Hecho cuando:** pasan los tests de `character_stats` y una run sin subir de nivel
juega igual que antes, comprobado con `tools/balance_sim.tscn`.

---

## 3. Hito C. Experiencia y niveles

### 3.1 Reglas

| Concepto | Regla |
|---|---|
| XP por enemigo | `(11 − rango) × xp.per_rank` (4). Élite ×2. Jefe ×3. |
| Primera kill de especie | En toda la partida, según el bestiario: **XP ×2**. Viene del diseño original. |
| Reparto | Cada miembro **vivo** al terminar el combate recibe la XP completa (no se divide). Los caídos reciben 0. |
| Curva | XP para pasar de L a L+1: `xp.curve_base + xp.curve_step × (L − 1)`, es decir 20, 35, 50… Total a nivel 10: 720. |
| Tope | `xp.max_level` = 10 (5 pisos). |
| Al subir | +`xp.points_per_level` puntos (2). +2 HP máx. automáticos y el HP actual sube lo mismo (no cura completo). En nivel par, **+1 espacio de alma** (Hito D). |

Si se sube varias veces en un mismo combate, las subidas se resuelven en orden y
se muestran todas.

### 3.2 Flujo y UI

- **Resumen post-combate** (ya existe): una fila por personaje con:
  - retrato pequeño, "+XP" y la barra de XP animada;
  - si sube: **"¡NIVEL 4!"** en `AccentLabel`, "+2 puntos" y, cuando toque,
    "¡Nueva ranura de alma!".
  - La revelación del alma sigue después, como ahora.
- **Barra de XP** ("XP actual / siguiente") visible en el HUD (fina, bajo el HP),
  en las tarjetas de combate y en Estado.
- **Puntos sin gastar:** marca ◆ junto al retrato en el HUD y en la pestaña
  Estadísticas. Al salir del combate, toast: "Bjorn tiene 2 puntos (Tab)". Desde el
  resumen se puede ir directo a asignarlos.
- Se asigna **fuera de combate**, en cualquier momento (Hito E).
- El resumen de la run muestra el nivel final de cada personaje.
- `EventBus`: agregar `xp_gained(member_id, amount)` y `level_up(member_id, new_level)`.
- `UnlockEvaluator`: nuevo tipo `reach_level {n}` y su desbloqueo de ejemplo (ver
  Hito G).
- `MetaState.stats`: registrar "nivel máximo alcanzado" como estadística global
  (solo informativa).

### 3.3 Persistencia 🟡

**El nivel, la XP y las estadísticas asignadas pertenecen a la run.** Se reinician
al terminarla, igual que las almas, y no van a `MetaState`. Es coherente con el
roguelike y con que las mejoras del hub sean la progresión permanente. Dejarlo tras
la bandera `xp.persist_between_runs: false`. **No implementar la variante
persistente** sin que David la confirme.

**Hecho cuando:** matar enemigos da XP, se sube de nivel con los efectos de arriba y
el resumen lo muestra. Agregar tests de la curva y de la XP por rango, élite, jefe y
primera kill.

---

## 4. Hito D. Espacios de alma por nivel

- **Espacios** = `soul_capacity` base (1) + `floor(nivel / 2)` + bonus de objetos
  (Amuleto de hueso), con tope `soul_capacity_max`.
- Por defecto el tope es **6**. Así se respeta "cada 2 niveles" hasta el nivel 10:
  - nivel 2 → 2 espacios;
  - nivel 4 → 3;
  - nivel 6 → 4;
  - nivel 8 → 5;
  - nivel 10 → 6.
  - Si en el balance resulta demasiado, bajar el tope y avisarle a David.
- `GameState.member_soul_capacity()` pasa a calcularse; deja de ser un campo fijo.
  El bonus de objetos se guarda aparte, en `soul_capacity_bonus`.
- La UI de almas (pestaña Almas, elección de receptor y diálogo de reemplazo)
  muestra los espacios vacíos como ranuras punteadas y los bloqueados como "Nv 4",
  "Nv 6"…
- La oferta de alma deja elegir receptor entre quienes tienen ranura libre, o
  reemplazar una con confirmación.
- Con más espacios el drop pesa más. **Revisar `soul_drop` con `balance_sim`**: en
  una run normal, al llegar al jefe del piso 3 los espacios desbloqueados deberían
  estar llenos **a medias**.

---

## 5. Hito E. Pestaña Estadísticas con gráfico radar

### 5.1 Dónde

Nueva pestaña **"Estadísticas"** en `StatusScreen` (Tab), entre Equipo y Almas.
Desde exploración y desde Pausa; **nunca en combate**. También se llega desde el
resumen post-combate cuando hay puntos sin gastar.

### 5.2 Componente `UIRadarChart` (`scripts/ui/components/ui_radar_chart.gd`)

Es un `Control` con `_draw()`, sin imágenes, y reutilizable.

- **Fondo:**
  - hexágono con 4–5 anillos guía y 6 radios en `BORDER`;
  - un anillo exterior grueso y oscuro tipo metal, como en la referencia.
- **Polígono actual:** relleno `UIStyle.SOUL` a ~70% de opacidad
  (`draw_colored_polygon`) con contorno sólido de 2 px.
- **Polígono de previsualización** (puntos pendientes sin confirmar): solo contorno
  en `ACCENT`.
- **Etiquetas:** las 6 siglas fuera de los vértices, con el valor debajo. El eje
  seleccionado va en `ACCENT`, como el "RÁF" resaltado de la referencia.
- **Escala fija 0–10** (`radar_max`). Lo que se pase por almas u objetos se dibuja
  recortado al borde, con una marca "+".
- **Animación:** ~0,15 s al cambiar valores, a pasos.
- Bordes rectos, sin antialiasing. Mínimo 260×260 a 100% de escala de UI.
- **Usos:**
  - pestaña Estadísticas;
  - **Bestiario**, para las estadísticas de enemigos derivadas de `stats_for_rank`;
  - `UIGallery`, con datos de ejemplo.

### 5.3 Layout

```
┌ ESTADO ─ [Equipo] [Estadísticas] [Almas] [Objetos] ─────── ◈ 86 ─┐
│ ┌────┐ Bjorn   Nv 4   XP ▮▮▮▮▯▯ 62/95        Puntos libres: 2 ◆   │
│ │ret.│                                                             │
│ └────┘            VIT                    ┌ Ataque (ATQ) ─────────┐ │
│              SUE  ╱‾‾‾‾╲  ATQ            │ 5  →  6                │ │
│                  │ ███ │                 │ +1 daño de ataque      │ │
│              VEL  ╲____╱  HAB            │ Ataque: 9 → 10         │ │
│                   RES                    └────────────────────────┘ │
│  ◀ ▶ estadística   ▲ +1   ▼ −1         [Confirmar]  [Deshacer]     │
│  Q/E cambia de personaje                                            │
└─────────────────────────────────────────────────────────────────────┘
```

- **Navegación:**
  - ◀/▶ eligen la estadística (también clic en el radar o en la lista);
  - ▲/+ suma un punto pendiente; ▼/− lo quita;
  - con mando: cruceta, A confirma, B deshace/vuelve;
  - Q/E o LB/RB cambian de personaje.
- **Panel de detalle:** valor actual → nuevo, efecto por punto y efecto real
  recalculado ("Evasión: 3% → 4%").
- **Confirmar** aplica los pendientes, previa confirmación con `UIConfirmDialog`
  porque no hay vuelta atrás. **Deshacer** solo borra los pendientes.
- No hay redistribución, salvo con el objeto del Hito G.
- Tope de **10 puntos asignados por estadística**
  (`stats.max_assigned_per_stat`). Al llegar, el + se deshabilita y un tooltip
  explica el motivo.

**Hecho cuando:**

- se reparten puntos con teclado, mando y mouse;
- radar y números se actualizan en vivo;
- se ve bien con valores 0, intermedios y máximos;
- hay capturas a 1280×720 y 1920×1080 en `docs/capturas/`.

---

## 6. Hito F. Retratos de personajes e íconos de objetos

### 6.1 Convención (David podrá soltar PNGs reales después sin tocar código)

| Tipo | Archivo | Tamaño |
|---|---|---|
| Personaje | `assets/portraits/char_<id>.png` | 64×64 |
| Especie (bestiario y combate) | `assets/portraits/species_<id>.png` | 64×64 |
| Objeto | `assets/icons/item_<id>.png` | 32×32 |
| Alma (opcional) | `assets/icons/soul_<id>.png` | 32×32; si falta, ícono genérico teñido por rango |

- PNG con filtro **Nearest**, mostrados a escala entera (×1/×2/×3).
- Campo `portrait` / `icono` **opcional** en los datos, como ruta explícita. Si no
  está, se usa la convención de nombres.
- **`PortraitResolver.get(kind, id) -> Texture2D`** (autoload o clase estática):
  usa el PNG si existe; si no, genera y cachea un **respaldo procedural** (inicial o
  glifo sobre el color de la especie o tipo, con borde pixelado). **Nunca falla por
  falta de archivo.**
- **Componentes:**
  - `UIPortraitFrame`: marco del Theme, insignia de nivel o rango en una esquina y
    marca ◆ de puntos sin gastar;
  - `UIItemIcon`: con cantidad "x3" si se agrupan iguales en la vista.

### 6.2 De dónde sacar el arte (solo licencias verificadas leyendo el LICENSE)

- **Personajes:** renderizar retratos de modelos 3D **CC0** con el pipeline de
  `tools/assets/`, el mismo que se usó para los esqueletos. Sugerencia: **KayKit
  Character Pack: Adventurers** (CC0); bárbaro para Bjorn, maga o pícara para Elena.
  - `tools/portrait_render.tscn`: encuadre de cabeza y hombros a 3/4, luz cálida de
    antorcha lateral, fondo `BG_DEEP` con viñeta y la misma trama/paleta PS1 de
    `RetroView`. Exporta a 64×64.
  - Si no se puede descargar desde el entorno, dejar la herramienta lista y pedirle
    a David que suba el pack.
- **Especies:** la misma herramienta sobre los modelos de `assets/enemies/` (como
  `tools/enemy_preview.tscn`), cacheada como PNG.
- **Objetos:** [game-icons.net](https://game-icons.net) (SVG, **CC BY 3.0**, exige
  atribución). Convertir a PNG 32×32 con tinte por tipo (curación `GOOD`, almas
  `SOUL`, utilidad `ACCENT`) y borde oscuro de 1 px, con un script en
  `tools/assets/`.
- **`docs/CREDITOS.md`**: cada asset con autor, licencia y enlace. Obligatorio para
  CC BY.

### 6.3 Dónde se muestran

- **Combate:** retrato a la izquierda de cada tarjeta de personaje; destello rojo
  al recibir daño y gris si cae. Retrato de la especie en el panel del enemigo.
- **Estado:** pestañas Equipo y Estadísticas.
- **Diálogo "¿A quién?"** (pociones, almas, amuleto): hoy es solo texto. Agregar
  retrato, HP y espacios de alma en cada opción.
- **HUD de exploración:** retrato chico + mini HP + barra de XP + ◆.
- **Resúmenes:** post-combate y de la run.
- **Bestiario:** retrato y radar de cada especie vista.
- **Objetos:** `UIItemSlot` (inventario y pestaña Objetos), menú Objeto en
  combate, toasts de "recogiste X", cofres y pantalla de desbloqueos del hub.

**Hecho cuando:** cada personaje, objeto y especie muestra imagen (real o de
respaldo) en todas esas pantallas; un PNG con el nombre correcto la reemplaza sin
tocar código; `CREDITOS.md` está completo.

---

## 7. Hito G. Objetos fuera de combate: pulirlos y hacerlos visibles

**Ya existe una base:** la tecla **I** abre el inventario con el botón **Usar**, y
`RunController.use_item_field()` resuelve curar, antorcha, capacidad de alma y
sello. `items.json` ya tiene `efecto.en_combate` y `efecto.fuera_combate`: **usar
esos campos**, no duplicarlos. David lo pidió como si faltara, así que **primero
hay que verificar que funcione de verdad en partida y que se pueda descubrir**.

- [ ] Probar cada objeto usable fuera de combate y agregarlo al smoke test.
- [ ] **Hacerlo visible:**
  - hint permanente en el HUD, "I Inventario · Tab Estado";
  - la pestaña **Objetos** del Estado también permite usar;
  - foco inicial en el primer objeto usable.
- [ ] Agregar `objetivo` a `items.json`: `"aliado" | "equipo" | "ninguno"`. Hoy se
      deduce del tipo de efecto.
- [ ] **Diálogo de objetivo con retratos y previsualización**, por ejemplo "Elena
      8/16 → 16/16" en verde. Si no haría nada (HP lleno, sin espacio que subir),
      la opción va deshabilitada con el motivo y **no se consume**. Esc/B cancela en
      cualquier paso.
- [ ] Los objetos solo de combate aparecen deshabilitados fuera de combate, con el
      motivo.
- [ ] Usar un objeto fuera de combate **no gasta turno**: los enemigos no se mueven.
      Va en `balance.json → items.field_use_costs_turn: false`. Mover y girar queda
      bloqueado con el menú abierto.
- [ ] Agrupar iguales en la vista ("Poción menor x3") y ordenar por tipo. El
      inventario interno sigue siendo una lista de ids.
- [ ] Opcional: teclas 1–4 para los primeros 4 consumibles, con selector de
      personaje.
- [ ] **Objetos nuevos** ligados a la progresión, con ícono y condición:

| Objeto | Efecto | Uso | Desbloqueo |
|---|---|---|---|
| Cristal de memoria | +30 XP a un personaje | Fuera de combate | Llegar a nivel 8 en una run (`reach_level`) |
| Fruta del vigor | +1 punto de estadística libre | Fuera de combate | Derrotar al jefe del piso 2 |
| Agua de olvido | Devuelve todos los puntos asignados de un personaje | Fuera de combate | Ganar una run |

**Hecho cuando:** con el equipo herido, se abre el inventario, se usa una Poción
menor en un personaje concreto y se ven el HP actualizado y la cantidad reducida,
sin combate.

---

## 8. Valores por defecto 🟡 (en `balance.json` / `stats.json`)

| Parámetro | Defecto |
|---|---|
| `xp.per_rank` | 4 |
| `xp.elite_mult` / `xp.boss_mult` | 2 / 3 |
| `xp.first_kill_mult` | 2 |
| `xp.curve_base` / `xp.curve_step` | 20 / 15 |
| `xp.max_level` | 10 |
| `xp.points_per_level` | 2 |
| `xp.hp_per_level` | 2 |
| `xp.persist_between_runs` | false |
| `soul_capacity` / `soul_capacity_max` | 1 / 6 (+1 cada 2 niveles) |
| `stats.max_assigned_per_stat` / `radar_max` | 10 / 10 |
| `stats.crit_base` | 0.03 |
| Coeficientes por estadística | Tabla del §2.1 |
| `items.field_use_costs_turn` | false |

### Objetivo de balance (el de la guía anterior se mantiene)

- **Sin mejoras del hub:** llegar al piso 2–3, con nivel ~4–5 al morir.
- **Con todo maxeado:** piso 4–5 con riesgo real, nivel ~8–10.
- **Run promedio:** nivel 3 al terminar el piso 1.
- Si los niveles vuelven fácil el juego, ajustar en este orden: la curva de XP,
  luego los coeficientes de estadísticas y al final los stats de enemigos.
- `tools/balance_sim`: agregar un reparto automático de puntos (por ejemplo, voraz
  hacia ATQ y VIT) para simular.

### Debug (F1), botones nuevos

"+XP", "Subir nivel", "+5 puntos", "Dar objeto…" y "Patrulla de prueba".

---

## 9. Orden de ejecución y entrega

| # | Hito | Verificación |
|---|---|---|
| A | Bug de giro de enemigos | Test de facing + captura |
| B | Estadísticas: `stats.json` + `character_stats` + orden por VEL + evasión | Tests; balance igual en nivel 1 |
| C | XP y niveles + resumen post-combate + barra XP | Tests de curva y XP |
| D | Espacios de alma por nivel | Test de capacidad por nivel |
| E | Pestaña Estadísticas + `UIRadarChart` (+ bestiario) | UIGallery + capturas |
| F | Retratos e íconos: resolver, pipeline, integración | Ninguna pantalla sin imagen + `CREDITOS.md` |
| G | Objetos fuera de combate (pulido) + 3 objetos nuevos | Smoke test usa objetos en exploración |
| H | Balance + documentación | `balance_sim` en objetivo; actualizar `README`, `ESTADO_TECNICO_PROTOTIPO.md` y `CLAUDE.md` |

**Entrega:**

- `tools/verify.sh` en verde.
- Capturas nuevas en `docs/capturas/`: radar, subida de nivel, combate con
  retratos, inventario con íconos y diálogo "¿A quién?".
- Resumen para David con:
  1. los valores por defecto usados;
  2. qué arte es temporal y cómo reemplazarlo (§6.1);
  3. lo pendiente.

**Preguntas para David** (no bloquean; usar los defectos):

1. ¿Nivel por run (lo asumido) o persistente entre runs?
2. ¿Le sirven las siglas VIT/ATQ/HAB/RES/VEL/SUE y sus efectos?
3. ¿Tope de 6 ranuras de alma o menos?

## 10. Qué NO hacer en esta etapa

- No hacer persistentes el nivel, la XP ni las estadísticas sin confirmación.
- No asignar puntos en combate.
- No usar arte sin licencia verificada ni sin crédito.
- No duplicar fórmulas entre `GameState`, `CombatManager` y la UI; todo pasa por
  `character_stats`.
- No romper guardados viejos de `MetaState`: si cambia su esquema, subir la versión
  y escribir la migración.
- No reestructurar los nodos de enemigos para arreglar el giro: el bug es de orden
  de dos líneas (§1).
