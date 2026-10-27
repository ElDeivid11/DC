# Sonidos de la UI

Todos son **CC0 1.0** de Kenney (www.kenney.nl): packs *UI Audio 1.0*,
*RPG Audio 1.0* e *Interface Sounds 1.0*. Licencias originales copiadas tal
cual en `LICENSE_Kenney_*.txt`. El crédito es opcional; se da igual en
Opciones → Créditos.

Copias tomadas del mirror `github.com/PIRuiz/TinyWorld` (commit
`d29e58d43a05d0b0f1a5b0f52cb74a6e7a43b6cb`, carpeta
`Assets/Kenney/Audio/<pack>/`), porque kenney.nl no estaba accesible. Los
archivos solo se renombraron.

| Archivo | Original | `SceneRouter.play_ui(kind)` | Evento |
|---|---|---|---|
| `ui_cursor_mover.ogg` | Interface Sounds / click_002 | `hover` | Mover el foco |
| `ui_confirmar.ogg` | RPG Audio / metalLatch | `click` | Confirmar |
| `ui_cancelar.ogg` | Interface Sounds / back_002 | `cancel` | Esc, "No", volver |
| `ui_menu_abrir.ogg` | RPG Audio / bookOpen | `open` | Abrir una pantalla |
| `ui_menu_cerrar.ogg` | RPG Audio / bookClose | `close` | Cerrar una pantalla |
| `ui_pagina_cambiar.ogg` | RPG Audio / bookFlip3 | `page` | Cambiar de pestaña |
| `ui_comprar_monedas.ogg` | RPG Audio / handleCoins2 | `coin` | Comprar, monedas, contador del resumen |
| `ui_alma.ogg` | Interface Sounds / maximize_006 | `soul` | Aparece o se asigna un alma |
| `ui_error.ogg` | Interface Sounds / error_008 | `error` | Acción inválida |
| `extra_subir_nivel.ogg` | Interface Sounds / confirmation_004 | `level_up` | Subida de nivel |
| `extra_recompensa_grande.ogg` | RPG Audio / handleCoins | `reward` | Total del resumen, cofre |
| `extra_bajar_piso_puerta.ogg` | RPG Audio / doorOpen_1 | `descend` | Iniciar expedición, bajar de piso |
| `extra_equipar_objeto.ogg` | RPG Audio / dropLeather | `item` | Usar o descartar un objeto |

## Sala del jefe (propios)

Sintetizados por código, sin samples (`python3 -I tools/audio/make_boss_sfx.py`): son del proyecto, CC0.

| Archivo | `SceneRouter.play_ui(kind)` | Evento |
|---|---|---|
| `extra_jefe_portazo.wav` | `door_slam` | La puerta de la sala del jefe se cierra de golpe detrás del equipo |
| `extra_jefe_brasero.wav` | `brazier` | Se enciende un brasero |
| `extra_jefe_entrada.wav` | `boss` | El jefe se levanta (golpe grave, coro y campana) |

## Combate (propios)

Sintetizados por código, sin samples (`python3 -I tools/audio/make_combat_sfx.py`): son del proyecto, CC0.

| Archivo | `SceneRouter.play_ui(kind)` | Evento |
|---|---|---|
| `combate_golpe.wav` | `hit` | Un golpe del héroe entra (golpe sordo y chasquido) |
| `combate_critico.wav` | `crit` | Crítico (chasquido seco, hierro que suena y un brillo) |
| `combate_herida.wav` | `hurt` | El héroe recibe daño |
| `combate_muerte.wav` | `kill` | El enemigo cae (huesos que se quiebran y el alma que se va) |
| `combate_sinergia.wav` | `proc` | Salta una sinergia: afinidad, pacto o pasiva |
