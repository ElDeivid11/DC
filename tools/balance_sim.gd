extends Node
## Simulador de balance (herramienta de desarrollo, no es parte del juego):
##   godot --headless --path . res://tools/balance_sim.tscn
## Juega N runs "promedio" con las MISMAS reglas del juego (CombatCore,
## RunRules, balance.json, floors.json, almas y sinergias) y una política
## simple (curarse con pociones, defenderse del golpe cargado del jefe, usar
## la activa que más rinde o atacar; tomar almas y cambiarlas si mejora el
## conjunto), y reporta hasta qué piso se llega en tres configuraciones: sin
## mejoras, mejoras al máximo, y mejoras al máximo + todo desbloqueado.
##
## Objetivo (guía §9): sin mejoras → piso 2–3; todo al máximo → piso 4–5
## con riesgo real. Si el piso 1 queda trivial con todo maxeado, bajar el
## valor por nivel de las mejoras (no el tope).
##
## Niveles: cada kill da EXP (RunRules.kill_xp) y los puntos se reparten al
## momento con una de dos políticas: "parejo" (las 6 estadísticas en ronda)
## o "VIT/ATQ" (solo vida y ataque, la más agresiva). Cada configuración se
## reporta con las dos, más el nivel medio al terminar.
##
## Para probar valores sin tocar balance.json (se pueden correr varias a la vez):
##   godot --headless --path . res://tools/balance_sim.tscn -- \
##     --set=leveling.heal_on_level_pct=0.1 --set='leveling.xp_to_next=[20,30,40,55,70,90,110,135,160]'
## (el valor se lee como JSON; xp_to_next necesita max_level − 1 valores).

const RUNS := 300
## Fracción de enemigos normales del piso que el jugador termina peleando.
const ENCOUNTER_RATE := 0.75
## Cómo empiezan los combates (chocar primero / normal / emboscada). Los
## jefes siempre empiezan con sorpresa (ver _fight).
const START_SURPRISE := 0.6
const START_AMBUSH := 0.15

## Políticas de reparto de puntos (se recorren en ronda, un punto por vez).
const POLICIES := {
	"parejo": ["vit", "atq", "def", "esp", "agi", "sue"],
	"VIT/ATQ": ["vit", "atq"],
}

var rng := RandomNumberGenerator.new()
## % de HP del equipo al terminar el piso 1 (para ver si queda trivial).
var _floor1_hp: Array[float] = []
var _policy: Array = []
var _levels: Array[float] = []
## Al terminar cada run: almas puestas, niveles de afinidad y pactos activos.
var _souls: Array[float] = []
## Muertes contra el jefe del piso (del total de muertes).
var _boss_deaths := 0
var _deaths := 0
var _tiers: Array[float] = []
var _pacts: Array[float] = []

func _ready() -> void:
	rng.seed = 12345
	DebugTools.set("_log_file", null) # sin log de eventos: miles de runs
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--set="):
			_override(arg.substr(6))
	var t0 := Time.get_ticks_msec()
	var configs: Array = [
		["Sin mejoras", 0, false],
		["Mejoras al máximo", 5, false],
		["Máximo + todo desbloqueado", 5, true],
	]
	for cfg: Array in configs:
		for policy: String in POLICIES.keys():
			_policy = POLICIES[policy]
			_report("%s (%s)" % [cfg[0], policy], int(cfg[1]), bool(cfg[2]))
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
	_levels.clear()
	_souls.clear()
	_boss_deaths = 0
	_deaths = 0
	_tiers.clear()
	_pacts.clear()
	for i in RUNS:
		var f := _simulate_run()
		reached[f] += 1
		total_floor += mini(f, floors)
	var line := "%-40s piso medio %.2f |" % [label, float(total_floor) / RUNS]
	for f in range(1, floors + 1):
		line += " muere en %d: %3d%%" % [f, roundi(100.0 * reached[f] / RUNS)]
	line += " | victoria: %d%%" % roundi(100.0 * reached[floors + 1] / RUNS)
	line += " | HP al salir del piso 1: %d%%" % roundi(100.0 * _avg(_floor1_hp))
	line += " | muertes contra jefes: %d%%" % roundi(100.0 * _boss_deaths / maxf(_deaths, 1))
	line += " | al final: nivel %.1f, almas %.1f, niveles de afinidad %.1f, pactos %.1f" % [_avg(_levels), _avg(_souls), _avg(_tiers), _avg(_pacts)]
	print(line)

static func _avg(values: Array[float]) -> float:
	var t := 0.0
	for v in values:
		t += v
	return t / maxf(values.size(), 1)

## Devuelve el piso donde murió (1..5) o floors+1 si ganó.
func _simulate_run() -> int:
	var f := _play_run()
	var m := GameState.hero()
	_levels.append(float(int(m.level)))
	_souls.append(float((m.souls as Array).size()))
	_tiers.append(float(_tier_count(m.souls)))
	_pacts.append(float(SoulBuild.active_pacts(m.souls).size()))
	return f

func _tier_count(souls: Array) -> int:
	var n := 0
	for row: Dictionary in SoulBuild.affinity_rows(souls):
		n += int(row.tier)
	return n

func _play_run() -> int:
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
			if not _fight(String(roll.species_id), int(roll.rank), String(roll.kind), ""):
				_deaths += 1
				return n
			_heal_between_fights()
		var b: Dictionary = def.boss
		if not _fight(String(b.species), int(b.rank), RunRules.BOSS, String(b.soul_id)):
			_deaths += 1
			_boss_deaths += 1
			return n
		if n == 1:
			var m := GameState.hero()
			_floor1_hp.append(float(int(m.hp)) / GameState.member_max_hp(m))
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

## Un combate con CombatCore (las reglas del juego) y una política simple:
## curarse con poción bajo el 30%; defenderse si el jefe carga su golpe y
## queda poca vida; si no, la activa lista que más rinde (o atacar). true = ganó.
func _fight(species_id: String, rank: int, kind: String, boss_soul: String) -> bool:
	var stats := RunRules.enemy_stats(rank, kind)
	var r := rng.randf()
	var mode := "surprise" if r < START_SURPRISE else ("ambush" if r < START_SURPRISE + START_AMBUSH else "normal")
	if kind == RunRules.BOSS:
		# En el juego el jefe no deambula (RunController._enemies_act lo salta):
		# se lo pelea después de su presentación, con el turno gratis del héroe
		# (modo "boss" del CombatManager, igual que un ataque sorpresa).
		mode = "boss"
	var m := GameState.hero()
	var core := CombatCore.new(rng)
	core.setup(GameState.combat_hero(m), {"name": "", "hp": stats.hp, "atk": stats.atk, "kind": kind}, mode)
	if core.ambush_pending:
		core.enemy_act()
	for turn in 80:
		if core.hero_dead():
			break
		core.begin_hero_turn()
		_policy_act(core)
		var next := core.after_hero_action()
		if next == "victory":
			break
		if next == "free_turn":
			continue
		core.enemy_turn_start()
		if core.enemy_dead():
			break
		core.enemy_act()
		if core.enemy_dead():
			break
	m["hp"] = maxi(int(core.hero.hp), 0)
	if core.bonus_coins > 0:
		GameState.add_coins(core.bonus_coins, "kills")
	if not core.enemy_dead():
		return false
	# Victoria: monedas, EXP, curas de almas y el alma (curva real).
	GameState.register_kill(species_id, rank, kind)
	GameState.add_xp(GameState.kill_xp(rank, kind))
	_spend_points()
	GameState.heal_after_victory()
	var chance := RunRules.soul_drop_chance(rank, kind, GameState.soul_chance_bonus())
	if rng.randf() < chance:
		var sid := boss_soul if boss_soul != "" else DataRegistry.roll_soul_id(species_id, rng)
		if sid != "":
			_offer_soul(DataRegistry.make_soul(sid, rank, "sim"))
	return true

func _policy_act(core: CombatCore) -> void:
	var hp_pct := float(int(core.hero.hp)) / maxi(int(core.hero.max_hp), 1)
	var heal_idx := _best_heal_item(true)
	if hp_pct < 0.3 and heal_idx >= 0:
		var it := DataRegistry.get_item(GameState.inventory[heal_idx])
		GameState.consume_item_at(heal_idx)
		core.heal_hero(int(it.efecto.valor), "")
		return
	if core.enemy_special_next() and hp_pct < 0.6 and core.shield <= 0:
		core.defend()
		return
	var best := -1
	var best_v := _attack_value(core)
	for i in core.soul_count():
		if not core.ability_ready(i):
			continue
		var v := _ability_value(core, i, hp_pct)
		if v > best_v:
			best_v = v
			best = i
	if best >= 0:
		core.ability(best)
	else:
		core.attack()

func _attack_value(core: CombatCore) -> float:
	return float(int(core.hero.atk)) + core._fx("damage_bonus_flat") + core._fx("bleed_on_hit") * 1.5

## Cuánto rinde usar ahora la activa i (daño esperado + lo que vale su efecto).
func _ability_value(core: CombatCore, i: int, hp_pct: float) -> float:
	var a := core.active_of(i)
	var hit := float(core.ability_hit(i))
	var eatk := float(int(core.enemy.atk))
	var ehp := float(int(core.enemy.hp))
	match String(a.tipo):
		"multigolpe":
			return hit * core.ability_hits(i)
		"sangrado":
			var st := float(core.ability_bleed(i))
			return hit + minf(st * (st + 1.0) / 2.0, ehp) * 0.8
		"aturdir":
			return hit + (0.0 if core.stun_immune else eatk * core.ability_stun(i))
		"drenar":
			return hit * (1.0 + (float(a.cura) if hp_pct < 0.9 else 0.0))
		"escudo":
			return float(core.ability_shield(i)) * (1.0 if hp_pct < 0.8 else 0.4)
		"marca":
			return hit + float(a.marca) * float(int(core.hero.atk))
		"debilitar":
			return hit + eatk * float(a.debilita) * int(a.turnos)
		"ejecutar":
			return hit * (float(a.mult) if core.execute_ready(i) else 1.0)
	return hit

## Alma nueva: si hay lugar se toma; si no, se cambia por la que menos aporta
## si el cambio mejora el «puntaje» del conjunto (sinergias + poder).
func _offer_soul(soul: Dictionary) -> void:
	var m := GameState.hero()
	var souls: Array = m.souls
	if souls.size() < GameState.member_soul_capacity(m):
		GameState.add_soul(String(m.id), soul)
		return
	var base := _build_score(souls)
	var best_i := -1
	var best := base
	for i in souls.size():
		var trial := souls.duplicate()
		trial[i] = soul
		var sc := _build_score(trial)
		if sc > best:
			best = sc
			best_i = i
	if best_i >= 0:
		GameState.add_soul(String(m.id), soul, best_i)

func _build_score(souls: Array) -> float:
	var sc := 0.0
	for soul: Dictionary in souls:
		sc += float(soul.get("bonus_poder", 0)) * 0.5 + 1.0
	sc += _tier_count(souls) * 2.0 + SoulBuild.active_pacts(souls).size() * 2.5
	return sc

## Reparte todos los puntos libres según la política (en ronda, continuando
## desde lo que ya tiene cada personaje).
func _spend_points() -> void:
	for m: Dictionary in GameState.party:
		while int(m.points) > 0:
			var spent := 0
			for id: Variant in (m.stats as Dictionary).keys():
				spent += int(m.stats[id])
			var stat := String(_policy[spent % _policy.size()])
			GameState.apply_points(m, {stat: 1})

## "--set=a.b.c=valor": pisa balance.json en memoria (valor en JSON).
func _override(spec: String) -> void:
	var eq := spec.find("=")
	if eq < 0:
		printerr("balance_sim: --set sin '=': ", spec)
		return
	var parts := spec.substr(0, eq).split(".")
	var value: Variant = JSON.parse_string(spec.substr(eq + 1))
	var d: Dictionary = DataRegistry.balance
	for i in parts.size() - 1:
		d = d[parts[i]]
	d[parts[parts.size() - 1]] = value
	print("balance_sim: %s = %s" % [spec.substr(0, eq), value])
	# La misma regla que DataRegistry._validate_balance: una curva corta
	# funcionaría como un tope de nivel escondido.
	var curve: Variant = DataRegistry.bal("leveling.xp_to_next")
	if typeof(curve) != TYPE_ARRAY or (curve as Array).size() < RunRules.max_level() - 1:
		printerr("balance_sim: leveling.xp_to_next necesita al menos %d valores (max_level − 1)" % (RunRules.max_level() - 1))
		get_tree().quit(1)
