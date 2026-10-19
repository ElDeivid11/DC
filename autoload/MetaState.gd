extends Node
## Estado PERSISTENTE entre runs: monedas, niveles de mejora, desbloqueos,
## bestiario, contadores para las condiciones de desbloqueo, estadísticas y
## ajustes. SaveSystem lo guarda/carga (user://save.json).
##
## Regla de oro: durante la run NADIE escribe acá. GameState acumula lo que
## pasa en la expedición y, al terminar, RunSummary calcula las recompensas
## (RunRewards) y las aplica de una vez con apply_run_result().
##
## Las almas NUNCA llegan acá: se ganan y se pierden dentro de la run.

## Versión del formato de guardado. Si cambia la estructura de to_dict(),
## subirla y agregar la migración correspondiente en SaveSystem.
const SAVE_VERSION := 1

signal changed

var coins := 0
var upgrades: Dictionary = {}      # upgrade_id -> nivel (int)
var unlocked: Dictionary = {}      # unlock_id -> true
var bestiary: Dictionary = {}      # species_id -> {seen, kills, first_kill_run, souls_taken}
var progress: Dictionary = {}      # contadores acumulados para las condiciones
var stats: Dictionary = {}         # estadísticas globales (pantalla Estadísticas)
var settings: Dictionary = {}

func _ready() -> void:
	reset()

func reset() -> void:
	coins = 0
	upgrades = {}
	unlocked = {}
	bestiary = {}
	progress = default_progress()
	stats = default_stats()
	settings = GameSettings.defaults()
	settings["retro_preset"] = String(DataRegistry.bal("render.preset_default", "clasico"))
	changed.emit()

func default_progress() -> Dictionary:
	return {
		"kills_by_species": {},
		"flee_total": 0,
		"bosses_defeated": {},   # "1".."5" (piso) y species_id -> true
		"best_floor": 0,
		"wins": 0,
		"coins_earned_total": 0,
	}

func default_stats() -> Dictionary:
	return {
		"runs": 0,
		"deaths": 0,
		"retreats": 0,
		"wins": 0,
		"total_kills": 0,
		"total_time_sec": 0.0,
		"best_floor": 0,
		"coins_earned_total": 0,
		"last_run": {},
	}

# --- Serialización ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"coins": coins,
		"upgrades": upgrades.duplicate(true),
		"unlocked": unlocked.duplicate(true),
		"bestiary": bestiary.duplicate(true),
		"progress": progress.duplicate(true),
		"stats": stats.duplicate(true),
		"settings": settings.duplicate(true),
	}

## Carga desde un dict ya migrado a SAVE_VERSION. Los campos que falten toman
## su valor por defecto (un guardado viejo o editado a mano no rompe nada).
func from_dict(d: Dictionary) -> void:
	reset()
	coins = int(d.get("coins", 0))
	upgrades = _int_values(d.get("upgrades", {}))
	unlocked = _dict_or_empty(d.get("unlocked", {}))
	bestiary = _dict_or_empty(d.get("bestiary", {}))
	progress = _merge(default_progress(), _dict_or_empty(d.get("progress", {})))
	stats = _merge(default_stats(), _dict_or_empty(d.get("stats", {})))
	var saved := _dict_or_empty(d.get("settings", {}))
	# Guardados anteriores a los presets de imagen: "pixelado: no" = limpio.
	if not saved.has("retro_preset") and saved.get("pixelated", true) == false:
		saved["retro_preset"] = "limpio"
	saved.erase("pixelated")
	settings = _merge(settings, saved)
	changed.emit()

static func _dict_or_empty(v: Variant) -> Dictionary:
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		return d.duplicate(true)
	return {}

static func _int_values(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in _dict_or_empty(v).keys():
		out[String(k)] = int((v as Dictionary)[k])
	return out

static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k: Variant in over.keys():
		out[k] = over[k]
	return out

# --- Mejoras ------------------------------------------------------------------

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))

func upgrade_max(id: String) -> int:
	return int(DataRegistry.get_upgrade(id).get("max_nivel", 0))

## Coste del SIGUIENTE nivel (coste_base × nivel siguiente); -1 si ya está al tope.
func upgrade_cost(id: String) -> int:
	return RunRules.upgrade_cost(DataRegistry.get_upgrade(id), upgrade_level(id))

func can_buy(id: String) -> bool:
	var cost := upgrade_cost(id)
	return cost >= 0 and coins >= cost

## Compra instantánea. Quien llama guarda (SaveSystem.save_meta()).
func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	coins -= upgrade_cost(id)
	upgrades[id] = upgrade_level(id) + 1
	changed.emit()
	return true

## Suma del efecto de todas las mejoras de un tipo (nivel × valor).
func upgrade_bonus(effect_type: String) -> float:
	var total := 0.0
	for id: String in upgrades.keys():
		var up := DataRegistry.get_upgrade(id)
		if up.is_empty():
			continue
		var e: Dictionary = up.efecto
		if e.tipo == effect_type:
			total += float(e.valor) * upgrade_level(id)
	return total

## Objetos con los que arranca cada run: los de balance.json + Provisiones.
func start_items() -> Array[String]:
	var out: Array[String] = []
	for it: Variant in DataRegistry.bal("start_items", []):
		out.append(String(it))
	for id: String in upgrades.keys():
		var up := DataRegistry.get_upgrade(id)
		if up.is_empty() or up.efecto.tipo != "start_item":
			continue
		for i in int(float(up.efecto.valor) * upgrade_level(id)):
			out.append(String(up.efecto.item))
	return out

# --- Desbloqueos ----------------------------------------------------------------

func is_unlocked(unlock_id: String) -> bool:
	return unlocked.has(unlock_id)

## Un objeto está disponible si no requiere desbloqueo o si ya se cumplió su
## condición. Solo los disponibles entran a la tabla de aparición de la run.
func is_item_available(item_id: String) -> bool:
	var it := DataRegistry.get_item(item_id)
	if it.is_empty():
		return false
	return it.unlock_id == null or is_unlocked(String(it.unlock_id))

func available_items() -> Array[String]:
	var out: Array[String] = []
	for id: String in DataRegistry.items.keys():
		if is_item_available(id):
			out.append(id)
	return out

# --- Bestiario --------------------------------------------------------------------

func bestiary_entry(species_id: String) -> Dictionary:
	var e: Dictionary = bestiary.get(species_id, {})
	return _merge({"seen": false, "kills": 0, "first_kill_run": 0, "souls_taken": 0}, e)

func has_killed(species_id: String) -> bool:
	return int(bestiary_entry(species_id).kills) > 0

# --- Fin de run -------------------------------------------------------------------

## Aplica el resultado ya calculado por RunRewards.compute(). Única vía por
## la que una run modifica el estado persistente.
func apply_run_result(result: Dictionary) -> void:
	var snap: Dictionary = result.snapshot
	var coins_info: Dictionary = result.coins
	var run_number := int(stats.runs) + 1

	coins += int(coins_info.total)
	progress = (result.progress_after as Dictionary).duplicate(true)
	for uid: Variant in result.new_unlocks:
		unlocked[String(uid)] = true

	for sid: Variant in (snap.seen_species as Dictionary).keys():
		var e := bestiary_entry(String(sid))
		e["seen"] = true
		bestiary[String(sid)] = e
	for sid: Variant in (snap.kills_by_species as Dictionary).keys():
		var e := bestiary_entry(String(sid))
		if int(e.kills) == 0:
			e["first_kill_run"] = run_number
		e["kills"] = int(e.kills) + int(snap.kills_by_species[sid])
		e["seen"] = true
		bestiary[String(sid)] = e
	for sid: Variant in (snap.souls_taken_by_species as Dictionary).keys():
		var e := bestiary_entry(String(sid))
		e["souls_taken"] = int(e.souls_taken) + int(snap.souls_taken_by_species[sid])
		bestiary[String(sid)] = e

	stats["runs"] = run_number
	match String(snap.outcome):
		"victoria":
			stats["wins"] = int(stats.wins) + 1
		"retiro":
			stats["retreats"] = int(stats.retreats) + 1
		_:
			stats["deaths"] = int(stats.deaths) + 1
	stats["total_kills"] = int(stats.total_kills) + int(snap.kills_total)
	stats["total_time_sec"] = float(stats.total_time_sec) + float(snap.time_sec)
	stats["best_floor"] = maxi(int(stats.best_floor), int(snap.max_floor))
	stats["coins_earned_total"] = int(stats.coins_earned_total) + int(coins_info.total)
	stats["last_run"] = {
		"outcome": snap.outcome,
		"floor": snap.max_floor,
		"kills": snap.kills_total,
		"coins": coins_info.total,
		"cause": snap.cause,
		"time_sec": snap.time_sec,
	}
	changed.emit()

# --- Debug ------------------------------------------------------------------------

func debug_add_coins(amount: int) -> void:
	coins = maxi(coins + amount, 0)
	changed.emit()

func debug_shift_upgrades(delta: int) -> void:
	for id: String in DataRegistry.upgrades.keys():
		upgrades[id] = clampi(upgrade_level(id) + delta, 0, upgrade_max(id))
	changed.emit()

func debug_set_all_unlocked(value: bool) -> void:
	unlocked = {}
	if value:
		for id: String in DataRegistry.unlocks.keys():
			unlocked[id] = true
	changed.emit()
