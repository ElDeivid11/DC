extends Node
## Simulador de balance (herramienta de desarrollo, no es parte del juego):
##   godot --headless --path . res://tools/balance_sim.tscn
## Juega N runs "promedio" con las MISMAS fórmulas del juego (RunRules,
## balance.json, floors.json, almas y pasivas) y una política simple
## (atacar, usar la mejor activa, curarse con pociones), y reporta hasta qué
## piso se llega en tres configuraciones: sin mejoras, mejoras al máximo, y
## mejoras al máximo + todo desbloqueado.
##
## Objetivo (guía §9): sin mejoras → piso 2–3; todo al máximo → piso 4–5
## con riesgo real. Si el piso 1 queda trivial con todo maxeado, bajar el
## valor por nivel de las mejoras (no el tope).

const RUNS := 300
## Fracción de enemigos normales del piso que el jugador termina peleando.
const ENCOUNTER_RATE := 0.75
## Cómo empiezan los combates (chocar primero / normal / emboscada).
const START_SURPRISE := 0.6
const START_AMBUSH := 0.15

var rng := RandomNumberGenerator.new()
## % de HP del equipo al terminar el piso 1 (para ver si queda trivial).
var _floor1_hp: Array[float] = []

func _ready() -> void:
	rng.seed = 12345
	DebugTools.set("_log_file", null) # sin log de eventos: miles de runs
	var t0 := Time.get_ticks_msec()
	var configs: Array = [
		["Sin mejoras", 0, false],
		["Mejoras al máximo", 5, false],
		["Máximo + todo desbloqueado", 5, true],
	]
	for cfg: Array in configs:
		_report(String(cfg[0]), int(cfg[1]), bool(cfg[2]))
	print("(%d runs por configuración, %.1f s)" % [RUNS, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit()

func _report(label: String, upgrade_level: int, unlock_all: bool) -> void:
	MetaState.reset()
	for id: String in DataRegistry.upgrades.keys():
		MetaState.upgrades[id] = mini(upgrade_level, MetaState.upgrade_max(id))
	MetaState.debug_set_all_unlocked(unlock_all)
	var floors := DataRegistry.bal_i("floors_per_run", 5)
	var reached: Array[int] = []
	reached.resize(floors + 2)
	reached.fill(0)
	var total_floor := 0
	_floor1_hp.clear()
	for i in RUNS:
		var f := _simulate_run()
		reached[f] += 1
		total_floor += mini(f, floors)
	var line := "%-28s piso medio %.2f |" % [label, float(total_floor) / RUNS]
	for f in range(1, floors + 1):
		line += " muere en %d: %3d%%" % [f, roundi(100.0 * reached[f] / RUNS)]
	line += " | victoria: %d%%" % roundi(100.0 * reached[floors + 1] / RUNS)
	var avg := 0.0
	for v in _floor1_hp:
		avg += v
	line += " | HP al salir del piso 1: %d%%" % roundi(100.0 * avg / maxf(_floor1_hp.size(), 1))
	print(line)

## Devuelve el piso donde murió (1..5) o floors+1 si ganó.
func _simulate_run() -> int:
	GameState.new_run(rng.randi(), false)
	var pool := MetaState.available_items()
	var floors := DataRegistry.bal_i("floors_per_run", 5)
	for n in range(1, floors + 1):
		var def := DataRegistry.get_floor(n)
		var species_pool := FloorGenerator.species_pool(int(def.rank_min), int(def.rank_max))
		# Botín del piso: cofres y objetos sueltos.
		for c in int(def.chests) + int(def.floor_items):
			var id := FloorGenerator.roll_item(rng, pool)
			if id != "":
				GameState.add_item(id, false)
		var fights := roundi(int(def.enemies) * ENCOUNTER_RATE)
		for k in fights:
			# Mismo sorteo que el generador de pisos (especie, rango y tipo).
			var roll := FloorGenerator.roll_enemy(rng, species_pool, int(def.rank_min), int(def.rank_max))
			var sp := DataRegistry.get_species(String(roll.species_id))
			if not _fight(int(roll.rank), String(roll.kind), String(sp.soul_id), n):
				return n
			_heal_between_fights()
		var b: Dictionary = def.boss
		if not _fight(int(b.rank), RunRules.BOSS, String(b.soul_id), n):
			return n
		if n == 1:
			var hp := 0
			var max_hp := 0
			for m: Dictionary in GameState.party:
				hp += int(m.hp)
				max_hp += GameState.member_max_hp(m)
			_floor1_hp.append(float(hp) / max_hp)
		if n < floors:
			GameState.advance_floor()
	return floors + 1

func _heal_between_fights() -> void:
	for m: Dictionary in GameState.alive_members():
		while float(m.hp) / GameState.member_max_hp(m) < 0.5:
			var idx := _best_heal_item(false)
			if idx < 0:
				return
			var it := DataRegistry.get_item(GameState.inventory[idx])
			GameState.heal_member(m, int(it.efecto.valor))
			GameState.consume_item_at(idx)

func _best_heal_item(in_combat: bool) -> int:
	var best := -1
	var best_v := 0
	for i in GameState.inventory.size():
		var it := DataRegistry.get_item(GameState.inventory[i])
		if it.efecto.tipo != "curar":
			continue
		if in_combat and not bool(it.efecto.en_combate):
			continue
		if int(it.efecto.valor) > best_v:
			best_v = int(it.efecto.valor)
			best = i
	return best

## Combate con las fórmulas del CombatManager. true = ganó.
func _fight(rank: int, kind: String, soul_id: String, _floor_n: int) -> bool:
	var stats := RunRules.enemy_stats(rank, kind)
	var ehp := int(stats.hp)
	var eatk := int(stats.atk)
	var r := rng.randf()
	var mode := "surprise" if r < START_SURPRISE else ("ambush" if r < START_SURPRISE + START_AMBUSH else "normal")
	var surprise := mode == "surprise"
	var enemy_turns := 0
	if mode == "ambush":
		_enemy_attack(eatk, DataRegistry.bal_f("combat.ambush_damage_mult", 1.5), kind, enemy_turns)
	for round_i in 60:
		for m: Dictionary in GameState.alive_members():
			if ehp <= 0:
				break
			var max_hp := GameState.member_max_hp(m)
			var heal_idx := _best_heal_item(true)
			if float(m.hp) / max_hp < 0.3 and heal_idx >= 0:
				var it := DataRegistry.get_item(GameState.inventory[heal_idx])
				GameState.heal_member(m, int(it.efecto.valor))
				GameState.consume_item_at(heal_idx)
				continue
			var base := maxi(GameState.member_atk(m) + rng.randi_range(-1, 1), 1)
			for soul: Dictionary in m.souls:
				base = maxi(base, int(soul.active.damage))
			var dmg := base + int(SoulEffects.total(m, "damage_bonus_flat"))
			if surprise:
				dmg = roundi(dmg * DataRegistry.bal_f("combat.surprise_damage_mult", 1.5))
			if rng.randf() < SoulEffects.total(m, "crit_chance"):
				dmg = roundi(dmg * DataRegistry.bal_f("combat.crit_mult", 2.0))
			ehp -= dmg
			var steal := SoulEffects.total(m, "lifesteal_pct")
			if steal > 0.0:
				GameState.heal_member(m, roundi(dmg * steal))
		if ehp <= 0:
			break
		if surprise:
			surprise = false
			continue
		enemy_turns += 1
		ehp -= _enemy_attack(eatk, 1.0, kind, enemy_turns)
		if GameState.is_party_dead():
			return false
	if ehp > 0:
		return false
	# Victoria: monedas, alma (curva real) y asignación al que tenga lugar.
	GameState.register_kill(DataRegistry.get_soul(soul_id).get("species", ""), rank, kind)
	var chance := RunRules.soul_drop_chance(rank, kind, MetaState.upgrade_bonus("soul_chance_pct"))
	if rng.randf() < chance:
		for m: Dictionary in GameState.party:
			if int(m.hp) > 0 and (m.souls as Array).size() < GameState.member_soul_capacity(m):
				GameState.add_soul(String(m.id), DataRegistry.make_soul(soul_id, rank, "sim"))
				break
	return true

## Devuelve el daño de espinas que recibe el enemigo.
func _enemy_attack(eatk: int, mult: float, kind: String, enemy_turns: int) -> int:
	var alive := GameState.alive_members()
	if alive.is_empty():
		return 0
	var every := DataRegistry.bal_i("combat.boss_ability_every", 3)
	var targets: Array = alive
	var raw := roundi((eatk + rng.randi_range(-1, 1)) * mult)
	if kind == RunRules.BOSS and every > 0 and enemy_turns > 0 and enemy_turns % every == 0:
		raw = maxi(roundi(eatk * DataRegistry.bal_f("combat.boss_ability_mult", 0.7) * mult), 1)
	else:
		targets = [alive[rng.randi_range(0, alive.size() - 1)]]
	var thorns := 0
	for t: Dictionary in targets:
		var dmg := maxi(raw - int(SoulEffects.total(t, "damage_reduction_flat")), 0)
		t["hp"] = maxi(int(t.hp) - dmg, 0)
		if dmg > 0:
			thorns += int(SoulEffects.total(t, "thorns_flat"))
	return thorns
