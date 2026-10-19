extends Node
## Señales globales del juego. Quien produce el hecho emite acá; quien necesita
## enterarse (HUD, log de debug, contadores de la run) se conecta acá, sin
## referencias cruzadas entre escenas.
##
## Las condiciones de desbloqueo NO se evalúan en pleno juego: GameState
## acumula los contadores de la run y al terminar UnlockEvaluator decide qué se
## ganó (se anuncia en el resumen de run).

# Las señales se emiten desde otros scripts, no desde este: sin esto Godot
# avisa "unused_signal" (y los warnings son errores en este proyecto).
@warning_ignore_start("unused_signal")

signal run_started(seed: int)
signal run_ended(snapshot: Dictionary)
signal floor_reached(n: int)
signal combat_started(species_id: String, is_boss: bool)
signal enemy_killed(species_id: String, first_time: bool)
signal boss_defeated(floor_n: int, species_id: String)
signal fled_combat(success: bool)
signal soul_acquired(member_id: String, soul: Dictionary)
signal item_picked(item_id: String)
signal item_used(item_id: String)
signal coins_changed(run_coins: int)
signal unlock_earned(unlock_id: String)
## Mensaje breve para el HUD de exploración (abajo al centro).
signal hud_message(text: String)

@warning_ignore_restore("unused_signal")
