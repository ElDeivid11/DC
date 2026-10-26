extends Node
## Estado de la RUN actual (expedición). Se descarta entero al terminar: lo
## único que sobrevive es lo que RunSummary aplica a MetaState a partir del
## snapshot() de acá.
##
## Lee MetaState (mejoras compradas, objetos disponibles) pero NUNCA lo
## escribe.
##
## Personaje (party[i]):
##   {id, name, base_hp, base_atk, hp, souls: [], soul_capacity,
##    level, xp, points, stats: {vit, atq, def, esp, agi, sue}}
##   base_hp/base_atk ya incluyen las mejoras de meta (se aplican al empezar).
##   max_hp/ataque efectivos = base + modificadores de sus almas + puntos de
##   estadística + bonus de la run (talismanes): member_max_hp() / member_atk().
##   Nivel, EXP y estadísticas son de la run: cada expedición empieza en 1.

var active := false
var ended := false
var test_room := false
var run_seed := 0
var rng := RandomNumberGenerator.new()

var floor_n := 1
var max_floor := 1
var party: Array = []
var inventory: Array[String] = []

var coin_breakdown: Dictionary = {}
var kills_by_species: Dictionary = {}
var kills_total := 0
var seen_species: Dictionary = {}
var souls_taken: Array = []
var souls_taken_by_species: Dictionary = {}
var items_used: Dictionary = {}
var flee_count := 0
var bosses_defeated: Array[int] = []
var boss_species: Array[String] = []
var elapsed_sec := 0.0

## Estado del piso actual (se limpia al bajar): celdas descubiertas para el
## minimapa, antorcha encendida, etc.
var visited: Dictionary = {}
var floor_flags: Dictionary = {}

var outcome := ""
var cause := ""
## Resultado ya calculado por RunRewards y aplicado (evita aplicar dos veces
## si se vuelve a entrar al resumen).
var last_result: Dictionary = {}
var result_applied := false

func _process(delta: float) -> void:
	# El reloj de la run se frena solo con el árbol en pausa (menú de pausa).
	if active and not ended:
		elapsed_sec += delta

# --- Ciclo de la run -------------------------------------------------------------

func new_run(p_seed: int, p_test_room := false) -> void:
	active = true
	ended = false
	test_room = p_test_room
	run_seed = p_seed
	rng.seed = p_seed
	floor_n = 1
	max_floor = 1
	coin_breakdown = {"kills": 0, "boss": 0, "chests": 0}
	kills_by_species = {}
	kills_total = 0
	seen_species = {}
	souls_taken = []
	souls_taken_by_species = {}
	items_used = {}
	flee_count = 0
	bosses_defeated = []
	boss_species = []
	elapsed_sec = 0.0
	visited = {}
	floor_flags = {}
	outcome = ""
	cause = ""
	last_result = {}
	result_applied = false

	# Valores por nivel pueden ser fraccionarios (balance fino): se redondea el total.
	var hp_bonus := roundi(MetaState.upgrade_bonus("max_hp_flat"))
	var atk_bonus := roundi(MetaState.upgrade_bonus("atk_flat"))
	var capacity := DataRegistry.bal_i("soul_capacity", 1)
	party = []
	for m: Variant in DataRegistry.bal("party", []):
		var md: Dictionary = m
		var member := {
			"id": String(md.id),
			"name": MetaState.hero_name(String(md.id)),
			"base_hp": int(md.base_hp) + hp_bonus,
			"base_atk": int(md.base_atk) + atk_bonus,
			"souls": [],
			"soul_capacity": capacity,
			"level": 1,
			"xp": 0,
			"points": 0,
			"stats": empty_stats(),
		}
		member["hp"] = member.base_hp
		party.append(member)

	inventory = []
	for it in MetaState.start_items():
		add_item(it, false)

	EventBus.run_started.emit(p_seed)
	EventBus.coins_changed.emit(run_coins())

## Al bajar de piso: cura un % del HP máximo (balance.json) y limpia el
## estado del piso.
func advance_floor() -> void:
	floor_n += 1
	max_floor = maxi(max_floor, floor_n)
	visited = {}
	floor_flags = {}
	var pct := DataRegistry.bal_f("heal_between_floors_pct", 0.0)
	for m: Dictionary in party:
		if int(m.hp) > 0:
			heal_member(m, ceili(float(member_max_hp(m)) * pct))
	EventBus.floor_reached.emit(floor_n)

## Cierra la run. outcome: "muerte" | "retiro" | "victoria" | "abandono".
func end_run(p_outcome: String, p_cause := "") -> Dictionary:
	outcome = p_outcome
	cause = p_cause
	ended = true
	active = false
	var snap := snapshot()
	EventBus.run_ended.emit(snap)
	return snap

## Todo lo que RunRewards necesita para calcular recompensas y desbloqueos.
func snapshot() -> Dictionary:
	var party_summary: Array = []
	for m: Dictionary in party:
		party_summary.append({"name": m.name, "hp": m.hp, "max_hp": member_max_hp(m), "souls": (m.souls as Array).size(), "level": int(m.get("level", 1))})
	return {
		"outcome": outcome,
		"cause": cause,
		"floor_n": floor_n,
		"max_floor": max_floor,
		"time_sec": elapsed_sec,
		"seed": run_seed,
		"test_room": test_room,
		"coin_breakdown": coin_breakdown.duplicate(),
		"run_coins": run_coins(),
		"kills_by_species": kills_by_species.duplicate(),
		"kills_total": kills_total,
		"seen_species": seen_species.duplicate(),
		"souls_taken": souls_taken.duplicate(true),
		"souls_taken_by_species": souls_taken_by_species.duplicate(),
		"items_used": items_used.duplicate(),
		"flee_count": flee_count,
		"bosses_defeated": bosses_defeated.duplicate(),
		"boss_species": boss_species.duplicate(),
		"party": party_summary,
	}

# --- Equipo ---------------------------------------------------------------------------

func get_member(member_id: String) -> Dictionary:
	for m: Dictionary in party:
		if m.id == member_id:
			return m
	return {}

func member_max_hp(m: Dictionary) -> int:
	var hp := int(m.base_hp) + RunRules.stat_hp(member_stat(m, "vit"))
	for soul: Dictionary in m.souls:
		var mods: Dictionary = soul.get("stat_modifiers", {})
		hp += int(mods.get("hp", 0)) + int(mods.get("max_hp", 0))
	return hp

func member_atk(m: Dictionary) -> int:
	var atk := int(m.base_atk) + run_atk_bonus() + RunRules.stat_atk(member_stat(m, "atq"))
	for soul: Dictionary in m.souls:
		var mods: Dictionary = soul.get("stat_modifiers", {})
		atk += int(mods.get("atk", 0))
	return atk

## Capacidad de almas: la base (+ Amuleto de hueso) + 1 cada 2 niveles.
func member_soul_capacity(m: Dictionary) -> int:
	return int(m.soul_capacity) + RunRules.level_soul_slots(int(m.get("level", 1)))

# --- Niveles y estadísticas ---------------------------------------------------------

func empty_stats() -> Dictionary:
	var s := {}
	for id in RunRules.STATS:
		s[id] = 0
	return s

func member_stat(m: Dictionary, stat: String) -> int:
	var s: Dictionary = m.get("stats", {})
	return int(s.get(stat, 0))

## Daño que resta DEF a cada golpe recibido.
func member_def(m: Dictionary) -> int:
	return RunRules.stat_def(member_stat(m, "def"))

## Daño extra de las habilidades de alma (ESP).
func member_ability_bonus(m: Dictionary) -> int:
	return RunRules.stat_esp(member_stat(m, "esp"))

## Probabilidad extra de crítico (AGI).
func member_crit_bonus(m: Dictionary) -> float:
	return RunRules.stat_crit(member_stat(m, "agi"))

## Suma de una estadística entre el equipo vivo (AGI para huir, SUE para
## almas y monedas: son del grupo, no de un golpe).
func party_stat_total(stat: String) -> int:
	var total := 0
	for m: Dictionary in alive_members():
		total += member_stat(m, stat)
	return total

## Promedio de una estadística entre el equipo vivo.
func party_stat_average(stat: String) -> float:
	var alive := alive_members()
	return float(party_stat_total(stat)) / alive.size() if not alive.is_empty() else 0.0

## Suma EXP a cada personaje vivo. Devuelve las subidas de nivel
## [{member_id, name, level, slots}] (slots = almas extra que ganó).
func add_xp(amount: int) -> Array:
	var ups: Array = []
	for m: Dictionary in alive_members():
		m["xp"] = int(m.xp) + amount
		while RunRules.xp_to_next(int(m.level)) > 0 and int(m.xp) >= RunRules.xp_to_next(int(m.level)):
			m["xp"] = int(m.xp) - RunRules.xp_to_next(int(m.level))
			var old_slots := member_soul_capacity(m)
			m["level"] = int(m.level) + 1
			m["points"] = int(m.points) + DataRegistry.bal_i("leveling.points_per_level", 3)
			heal_member(m, ceili(member_max_hp(m) * DataRegistry.bal_f("leveling.heal_on_level_pct", 0.0)))
			ups.append({"member_id": m.id, "name": m.name, "level": int(m.level), "slots": member_soul_capacity(m) - old_slots})
			EventBus.level_up.emit(String(m.id), int(m.level))
		if RunRules.xp_to_next(int(m.level)) == 0:
			m["xp"] = 0 # nivel máximo: la EXP ya no se acumula
	return ups

## Reparte puntos: alloc = {stat: cantidad}. Falla (sin tocar nada) si pide
## más puntos de los que tiene o una estadística que no existe. Lo que suba
## VIT también sube el HP actual.
func apply_points(m: Dictionary, alloc: Dictionary) -> bool:
	var total := 0
	for stat: Variant in alloc.keys():
		if not RunRules.STATS.has(String(stat)) or int(alloc[stat]) < 0:
			return false
		total += int(alloc[stat])
	if total <= 0 or total > int(m.points):
		return false
	var old_max := member_max_hp(m)
	var s: Dictionary = m.stats
	for stat: Variant in alloc.keys():
		s[String(stat)] = int(s.get(String(stat), 0)) + int(alloc[stat])
	m["points"] = int(m.points) - total
	if int(m.hp) > 0:
		m["hp"] = mini(int(m.hp) + maxi(member_max_hp(m) - old_max, 0), member_max_hp(m))
	return true

## Bonus de monedas por kill del grupo: pasivas de codicia + SUE.
func party_coin_bonus() -> float:
	return party_passive_total("coin_bonus_pct") + RunRules.stat_coins(party_stat_total("sue"))

func points_pending() -> bool:
	return party.any(func(m: Dictionary) -> bool: return int(m.get("points", 0)) > 0)

func alive_members() -> Array:
	return party.filter(func(m: Dictionary) -> bool: return int(m.hp) > 0)

func is_party_dead() -> bool:
	return alive_members().is_empty()

## Devuelve cuánto curó de verdad (no pasa del máximo, no revive caídos).
func heal_member(m: Dictionary, amount: int) -> int:
	if int(m.hp) <= 0:
		return 0
	var before := int(m.hp)
	m["hp"] = mini(before + amount, member_max_hp(m))
	return int(m.hp) - before

## Agrega un alma al personaje. replace_index >= 0 reemplaza esa (capacidad
## llena). Al ganar max_hp por el alma, el HP actual sube lo mismo.
func add_soul(member_id: String, soul: Dictionary, replace_index := -1) -> void:
	var m := get_member(member_id)
	if m.is_empty():
		return
	var old_max := member_max_hp(m)
	var souls: Array = m.souls
	if replace_index >= 0 and replace_index < souls.size():
		souls[replace_index] = soul
	else:
		souls.append(soul)
	var gained := member_max_hp(m) - old_max
	m["hp"] = clampi(int(m.hp) + maxi(gained, 0), 0, member_max_hp(m))
	var sid := String(soul.get("species", ""))
	souls_taken.append({"member": m.name, "name": soul.active.name, "species": soul.get("source_species", ""), "rank": soul.get("source_rank", 0)})
	souls_taken_by_species[sid] = int(souls_taken_by_species.get(sid, 0)) + 1
	EventBus.soul_acquired.emit(member_id, soul)

## Suma de una pasiva de alma de un tipo entre TODO el equipo vivo (p. ej.
## coin_bonus_pct, que no es de un golpe puntual sino del grupo).
func party_passive_total(effect_type: String) -> float:
	var total := 0.0
	for m: Dictionary in alive_members():
		for soul: Dictionary in m.souls:
			var passive: Variant = soul.get("passive")
			if passive == null:
				continue
			var effect: Dictionary = (passive as Dictionary).get("effect", {})
			if effect.get("type", "") == effect_type:
				total += float(effect.get("value", 0))
	return total

# --- Monedas, kills y especies ----------------------------------------------------------

func run_coins() -> int:
	var total := 0
	for k: Variant in coin_breakdown.keys():
		total += int(coin_breakdown[k])
	return total

func add_coins(amount: int, category: String) -> void:
	coin_breakdown[category] = int(coin_breakdown.get(category, 0)) + amount
	EventBus.coins_changed.emit(run_coins())

func register_seen(species_id: String) -> void:
	seen_species[species_id] = true

## Registra una kill: monedas (con pasivas de codicia), contadores y señales.
## Devuelve las monedas ganadas.
## coin_bonus: el bonus de monedas fijado al empezar el combate (el mismo que
## mostró el resumen); -1 = calcularlo ahora con el equipo vivo.
func register_kill(species_id: String, rank: int, kind: String, coin_bonus := -1.0) -> int:
	var first_time := not MetaState.has_killed(species_id) and not kills_by_species.has(species_id)
	kills_by_species[species_id] = int(kills_by_species.get(species_id, 0)) + 1
	kills_total += 1
	seen_species[species_id] = true
	var coins := RunRules.kill_coins(rank, kind, floor_n)
	var bonus := coin_bonus if coin_bonus >= 0.0 else party_coin_bonus()
	coins = roundi(float(coins) * (1.0 + bonus))
	add_coins(coins, "boss" if kind == RunRules.BOSS else "kills")
	EventBus.enemy_killed.emit(species_id, first_time)
	if kind == RunRules.BOSS:
		bosses_defeated.append(floor_n)
		boss_species.append(species_id)
		EventBus.boss_defeated.emit(floor_n, species_id)
	return coins

func register_flee(success: bool) -> void:
	if success:
		flee_count += 1
	EventBus.fled_combat.emit(success)

# --- Inventario --------------------------------------------------------------------------

func inventory_capacity() -> int:
	return DataRegistry.bal_i("inventory_capacity", 8)

func inventory_full() -> bool:
	return inventory.size() >= inventory_capacity()

func add_item(item_id: String, announce := true) -> bool:
	if inventory_full() or DataRegistry.get_item(item_id).is_empty():
		return false
	inventory.append(item_id)
	if announce:
		EventBus.item_picked.emit(item_id)
	return true

## Saca un objeto del inventario porque se usó (cuenta para condiciones
## como "sin usar pociones menores").
func consume_item_at(index: int) -> String:
	if index < 0 or index >= inventory.size():
		return ""
	var id := inventory[index]
	inventory.remove_at(index)
	items_used[id] = int(items_used.get(id, 0)) + 1
	EventBus.item_used.emit(id)
	return id

## +ataque de la run por objetos pasivos en el inventario (Talismán de hueso).
func run_atk_bonus() -> int:
	var bonus := 0
	for id in inventory:
		var it := DataRegistry.get_item(id)
		if it.get("tipo", "") == "pasivo" and it.efecto.tipo == "ataque_run":
			bonus += int(it.efecto.valor)
	return bonus

## Índice del primer objeto del inventario con ese efecto (-1 si no hay).
func find_item_with_effect(effect_type: String) -> int:
	for i in inventory.size():
		var it := DataRegistry.get_item(inventory[i])
		if it.efecto.tipo == effect_type:
			return i
	return -1
