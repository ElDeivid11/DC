# Dungeon Grid — roguelike en primera persona (Godot 4, estética PS1)

Dungeon crawler por grilla (giros de 90°), combate por turnos con cámara estática y estética PS1 (baja resolución, vertex snapping, niebla). Una **expedición** = una run con permadeath: bajas pisos generados al azar, juntas almas y objetos que solo sirven en esa run, y al volver al **Hub** gastas las monedas en mejoras chicas y permanentes.

![Hub](docs/capturas/hub_demo.png)

## Cómo jugarlo

1. Abre el proyecto con **Godot 4.7** (`project.godot`). La primera vez tarda un poco: reimporta modelos y texturas.
2. Pulsa **F5**. Arranca en el Hub.

### Controles

| Acción | Teclado | Mando |
|---|---|---|
| Avanzar / retroceder | ↑ ↓ o W S | Cruceta / stick |
| Girar 90° | ← → o A D | Cruceta / stick |
| Atacar a un enemigo | caminar contra él (= **ataque sorpresa**) | — |
| Abrir un cofre | caminar contra él | — |
| Estado del equipo | Tab | Y / △ |
| Inventario | I | X / □ |
| Mapa del piso | M | Select |
| Pausa | Esc | Start |
| Menús | ↑↓ · Enter · Esc (atrás) · Q/E pestañas | Cruceta · A · B · LB/RB |
| Panel de debug | F1 (solo en el editor / builds de debug) | — |

## Una expedición

- **Pisos 1 a 5**, cada uno más grande (25×25 → 45×45) y con enemigos de rango más fuerte. Rango 10 = más débil, 1 = más fuerte.
- Los enemigos **deambulan y te persiguen**. Si chocas tú primero: **ataque sorpresa** (turno gratis y daño ×1,5). Si te alcanzan **por la espalda o un costado: emboscada** (pegan primero ×1,5).
- Cada piso tiene un **jefe** que custodia la salida. Al vencerlo eliges: **bajar**, **retirarte con el botín** o quedarte.
- **Almas**: a veces un enemigo suelta su alma (los jefes siempre). Se revela al pulsar Continuar; recogerla es opcional y eliges quién la lleva (1 activa + pasiva opcional + modificadores). **No salen de la cripta.**
- **Objetos**: en cofres y en el suelo. Solo aparecen los ya desbloqueados.
- **Morir** conserva el 50% de las monedas; **retirarse** o **ganar**, el 100%.

## Entre expediciones (Hub)

- **Mejoras** con monedas, con tope de 5 niveles: Vitalidad, Fuerza, Botín, Provisiones y Sabiduría.
- **Objetos y desbloqueos**: los objetos nuevos se desbloquean **por condiciones** (llegar al piso 3, matar 10 goblins, huir 3 veces…), nunca con monedas. Se ve el progreso (7/10).
- **Bestiario**: especies vistas, kills y el alma que dan. La primera kill de cada especie da un bonus una sola vez.
- **Estadísticas** y **Opciones**: volumen, pantalla completa, escala de UI 80–150%, pixelado PS1 y controles.

| Combate | Revelación del alma | Resumen de la expedición |
|---|---|---|
| ![](docs/capturas/combat.png) | ![](docs/capturas/soul.png) | ![](docs/capturas/summary_revealed.png) |

## Valores por defecto que hay que revisar (🟡)

Todos se cambian en `data/balance.json` (y en los otros JSON de `data/`) sin tocar código.

| Decisión abierta | Valor usado |
|---|---|
| Pisos por run | 5, con un jefe por piso (`floors_per_run`, `data/floors.json`) |
| Equipo | 2 personajes, Bjorn y Elena (`party`; admite 1–3) |
| "Impuesto" | No hay sumidero: al morir se conserva el 50% (`coins.coin_keep_on_death`) |
| Bestiario | Persistente; bonus de primera kill = 10 × (11 − rango), una sola vez |
| Almas | Capacidad 1 por personaje (el Amuleto de hueso la sube). Drop: normal 8% × factor de rango, élite 25%, jefe 100% |
| Inventario | 8 objetos; se empieza con 1 Poción menor (`start_items`) |
| Mejoras | Tope 5 niveles; coste = base × nivel. Fuerza +0,6 ATK y Vitalidad +1,6 HP por nivel, redondeado (ver *Balance*) |
| Huir | 50% ± 10% por rango de diferencia con la media del piso; no contra jefes. Si fallas, pierdes el turno |
| Curación entre pisos | 30% del HP máximo al bajar (`heal_between_floors_pct`) |
| Élites | 10% de los enemigos: stats ×1,25, monedas ×2, tinte dorado |
| Jefes | Stats × 1,5; cada 3 turnos usan una habilidad que golpea a todo el equipo |
| "Completar una run sin pociones" | Cuenta retirarse o ganar (no morir) |

### Balance

`tools/balance_sim.tscn` juega cientos de runs con las fórmulas reales del juego, con una política simple: atacar, usar la mejor activa y curarse.

| Configuración | Piso medio | Victorias |
|---|---|---|
| Sin mejoras | 2,4 | 0% |
| Todo al máximo | 3,9 | ~10% |

Esto coincide con el objetivo de la guía: sin mejoras se llega al piso 2–3, y con todo al máximo al 4–5 con riesgo real.

## Herramientas

- **F1 — panel de debug**: monedas, mejoras ±1, desbloquear o bloquear todo, saltar de piso, pelear con el más cercano o con el jefe, curar, ganar el combate, forzar alma o ataque sorpresa, god mode, matar de un golpe, semilla fija, reiniciar guardado, sala de pruebas y galería de UI. Muestra FPS, celda y estado de la run. Registra los eventos en `user://debug.log`.
- **Sala de pruebas**: la sala 15×9 del prototipo con los 5 enemigos conocidos. Se abre desde Opciones (en debug) o con F1. No guarda progreso.
- **Galería de UI**: todos los componentes del design system en una pantalla.
- `tools/verify.sh`: verificación completa (import, lint con warnings como errores, arranque, 38 tests unitarios y smoke test de punta a punta).
- `tools/screenshot.tscn`: capturas con Xvfb (ver el encabezado del script).

## Estructura

```
autoload/   EventBus, DataRegistry, MetaState, SaveSystem, GameState, Controls, SceneRouter, DebugTools
data/       species, souls, items, unlocks, upgrades, floors, balance, texts (todo en JSON)
scenes/     Boot, Hub, Run, RunSummary, ui/UIGallery
scripts/    run/ (RunController, FloorGenerator, FloorBuilder, reglas, recompensas, desbloqueos)
            combat/ (CombatManager, pasivas) · world/ (GridPlayer) · ui/ (theme, componentes, pantallas, HUD)
ui/         theme_main.tres (generado por scripts/ui/theme_builder.gd)
tests/      TestRunner (unitarios) y SmokeTest
tools/      verify.sh, lint, build_theme, balance_sim, screenshot
docs/       GUIA_CLAUDE_CODE.md, ESTADO_TECNICO_PROTOTIPO.md, capturas/
```

## Licencias

- Fuentes: Pixelify Sans, Noto Sans Symbols y Noto Sans Symbols 2 (SIL OFL 1.1, ver `assets/fonts/`). Las Noto están recortadas y con las métricas ajustadas.
- Pack PSX de cajas/barriles: `assets/psx_boxes_barrels/Licence.txt`. KayKit, PSX Visuals y LevelBlock: ver sus carpetas en `addons/`.
- **El pack de goblins no trae licencia: confirmarla antes de publicar.**

## Pendiente / diferido

- Diferido a propósito, sin pedido no se implementa: razas, árbol de habilidades, crafting, eventos mensuales, niveles/XP.
- `addons/dungeon_crawler_3d` quedó sin usar: el generador propio produce la grilla que ya consume el juego (ver `docs/ESTADO_TECNICO_PROTOTIPO.md`).
- Gothic Furniture sigue sin integrar (los `.fbx` necesitan materiales asignados a mano).
- Arte propio de jefes: ahora reutilizan modelos, con escala y tinte.
- Sonidos: hay blips generados por código; faltan sonidos reales.
