class_name UnlockEvaluator
extends RefCounted
## Evalúa las condiciones de desbloqueo de data/unlocks.json.
##
## Durante la run, GameState acumula los hechos (kills por especie, huidas,
## jefes, objetos usados...). Al terminar, RunRewards combina esos contadores
## con los acumulados de MetaState.progress (merged_progress) y pregunta acá
## qué condiciones se cumplen. Los desbloqueos se anuncian en el resumen de
## run, nunca en pleno juego.
##
## Tipos de condición (DataRegistry.UNLOCK_CONDITIONS):
##   kill_species_total {species: [ids] | id, n}   kills acumuladas
##   reach_floor {n}                               mejor piso alcanzado
##   defeat_boss {floor: n} | {species: id}        jefe derrotado alguna vez
##   win_run {n?}                                  runs ganadas (defecto 1)
##   flee_count {n}                                huidas exitosas acumuladas
##   no_item_use_run {item, resultados: [...]}     esta run, sin usar ese objeto
##   coins_total {n}                               monedas ganadas en total

## Progreso acumulado tras sumar lo de esta run (no modifica `meta_progress`).
static func merged_progress(meta_progress: Dictionary, snap: Dictionary, coins_earned: int) -> Dictionary:
	var p := meta_progress.duplicate(true)
	var kills: Dictionary = p.get("kills_by_species", {})
	for sid: Variant in (snap.get("kills_by_species", {}) as Dictionary).keys():
		kills[sid] = int(kills.get(sid, 0)) + int(snap.kills_by_species[sid])
	p["kills_by_species"] = kills
	p["flee_total"] = int(p.get("flee_total", 0)) + int(snap.get("flee_count", 0))
	var bosses: Dictionary = p.get("bosses_defeated", {})
	for f: Variant in snap.get("bosses_defeated", []):
		bosses[str(int(f))] = true
	for sid: Variant in snap.get("boss_species", []):
		bosses[String(sid)] = true
	p["bosses_defeated"] = bosses
	p["best_floor"] = maxi(int(p.get("best_floor", 0)), int(snap.get("max_floor", 0)))
	if snap.get("outcome", "") == "victoria":
		p["wins"] = int(p.get("wins", 0)) + 1
	p["coins_earned_total"] = int(p.get("coins_earned_total", 0)) + coins_earned
	return p

## (actual, objetivo) de una condición, para barras "7/10" en el Hub.
## `snap` solo hace falta para condiciones "de esta run" (no_item_use_run).
static func progress_of(unlock: Dictionary, progress: Dictionary, snap: Dictionary = {}) -> Vector2i:
	var cond: Dictionary = unlock.get("condicion", {})
	var params: Dictionary = cond.get("parametros", {})
	var n := int(params.get("n", 1))
	match String(cond.get("tipo", "")):
		"kill_species_total":
			var ids: Array = params.species if typeof(params.get("species")) == TYPE_ARRAY else [params.get("species", "")]
			var total := 0
			var kills: Dictionary = progress.get("kills_by_species", {})
			for sid: Variant in ids:
				total += int(kills.get(String(sid), 0))
			return Vector2i(mini(total, n), n)
		"reach_floor":
			return Vector2i(mini(int(progress.get("best_floor", 0)), n), n)
		"defeat_boss":
			var bosses: Dictionary = progress.get("bosses_defeated", {})
			var key := String(params.species) if params.has("species") else str(int(params.get("floor", 0)))
			return Vector2i(1 if bosses.has(key) else 0, 1)
		"win_run":
			return Vector2i(mini(int(progress.get("wins", 0)), n), n)
		"flee_count":
			return Vector2i(mini(int(progress.get("flee_total", 0)), n), n)
		"coins_total":
			return Vector2i(mini(int(progress.get("coins_earned_total", 0)), n), n)
		"no_item_use_run":
			if snap.is_empty():
				return Vector2i(0, 1)
			var outcomes: Array = params.get("resultados", ["victoria"])
			var used := int((snap.get("items_used", {}) as Dictionary).get(String(params.get("item", "")), 0))
			var ok: bool = outcomes.has(snap.get("outcome", "")) and used == 0
			return Vector2i(1 if ok else 0, 1)
	return Vector2i(0, 1)

static func is_met(unlock: Dictionary, progress: Dictionary, snap: Dictionary = {}) -> bool:
	var p := progress_of(unlock, progress, snap)
	return p.x >= p.y

## Desbloqueos NUEVOS (no estaban en `already`) que se cumplen ahora.
static func evaluate(unlocks: Dictionary, progress: Dictionary, snap: Dictionary, already: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var ids: Array = unlocks.keys()
	ids.sort()
	for uid: Variant in ids:
		if already.has(uid):
			continue
		if is_met(unlocks[uid], progress, snap):
			out.append(String(uid))
	return out
