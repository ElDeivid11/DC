class_name CombatCore
extends RefCounted
## Reglas del combate uno contra uno (el héroe contra un enemigo), sin UI.
## Las usan el CombatManager (que muestra cada paso) y el simulador de
## balance (que juega miles de combates con una política simple): las
## fórmulas están en un solo lugar.
##
## Cada acción devuelve una lista de EVENTOS, en orden, para presentar:
##   {log: texto, tone: info|hit|taken|heal|soul|crit}  línea del registro
##   {enemy_dmg: n, crit: bool, bleed: bool}            golpe al enemigo
##   {hero_dmg: n, absorbed: n}                         golpe al héroe
##   {heal: n} · {shield: n} · {coins: n}               cura, escudo, monedas
## (un evento puede traer varias claves a la vez).
##
## Turno: begin_hero_turn() → attack() | ability(i) | defend() | heal_hero()
## → after_hero_action() dice si sigue el enemigo; su turno es
## enemy_turn_start() (sangrado) → enemy_intent() (para animar) → enemy_act().
##
## Las almas dan: activas con efectos y recarga (DataRegistry.ACTIVE_TYPES),
## y efectos sumados de pasivas, afinidades y pactos (SoulBuild.effects).

var rng: RandomNumberGenerator
## {id, name, hp, max_hp, atk, def, ability_bonus, crit_bonus, souls}
var hero := {}
## {name, hp, max_hp, atk, kind, ability_name}
var enemy := {}
## Efectos de las almas del héroe (se calculan al empezar).
var fx := {}
## Turnos que le faltan a cada activa (índice = alma); 0 = lista.
var cooldowns: Array[int] = []
var shield := 0
var defending := false
var last_stand_used := false
## Estados del enemigo: sangrado (daño al empezar su turno, baja 1),
## aturdido (pierde turnos; después resiste sus próximas acciones), marca
## (el próximo golpe hace +x), debilitado (pega un x% menos unos turnos).
## Todos con tope (balance.json → combat.topes).
var bleed := 0
var stun := 0
## Acciones del enemigo que faltan para que se lo pueda volver a aturdir.
var stun_resist := 0
var mark := 0.0
var weak_turns := 0
var weak_pct := 0.0
var surprise_round := false
var ambush_pending := false
var enemy_turns := 0
## Monedas ganadas en el combate (críticos con Puntería codiciosa).
var bonus_coins := 0
var god_mode := false
var one_hit := false

func _init(p_rng: RandomNumberGenerator = null) -> void:
	rng = p_rng
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

static func _bal(path: String, default: float) -> float:
	return DataRegistry.bal_f("combat." + path, default)

func _fx(type: String) -> float:
	return float(fx.get(type, 0.0))

## Tope de un efecto que se acumula (balance.json → combat.topes.<nombre>).
static func cap(name: String, default: float) -> float:
	return DataRegistry.bal_f("combat.topes." + name, default)

func stun_immune() -> bool:
	return stun_resist > 0

func _add_bleed(n: int) -> void:
	bleed = mini(bleed + n, int(cap("sangrado", 12)))

func _add_shield(n: int) -> void:
	shield = mini(shield + n, maxi(roundi(int(hero.max_hp) * cap("escudo_pct_hp", 1.0)), 1))

## mode: "surprise" | "boss" (el equipo golpea primero ×1,5 y el enemigo
## pierde su primer turno) | "ambush" (el enemigo pega primero ×1,5) | "normal".
func setup(p_hero: Dictionary, p_enemy: Dictionary, mode := "normal") -> Array:
	hero = p_hero.duplicate()
	hero["hp"] = int(hero.get("hp", 1))
	hero["max_hp"] = int(hero.get("max_hp", hero.hp))
	hero["atk"] = int(hero.get("atk", 1))
	hero["def"] = int(hero.get("def", 0))
	hero["ability_bonus"] = int(hero.get("ability_bonus", 0))
	hero["crit_bonus"] = float(hero.get("crit_bonus", 0.0))
	hero["souls"] = hero.get("souls", [])
	enemy = {
		"name": String(p_enemy.get("name", "???")), "hp": int(p_enemy.get("hp", 1)),
		"max_hp": int(p_enemy.get("hp", 1)), "atk": int(p_enemy.get("atk", 1)),
		"kind": String(p_enemy.get("kind", RunRules.NORMAL)), "ability_name": String(p_enemy.get("ability_name", "")),
	}
	fx = SoulBuild.effects(hero.souls)
	cooldowns.clear()
	for i in (hero.souls as Array).size():
		cooldowns.append(0)
	surprise_round = mode == "surprise" or mode == "boss"
	ambush_pending = mode == "ambush"
	var ev: Array = []
	var start := int(_fx("start_shield"))
	if start > 0:
		_add_shield(start)
		ev.append({"shield": start, "log": DataRegistry.t("combat.log_start_shield", [start]), "tone": "soul"})
		_proc(ev, "start_shield")
	return ev

func hero_dead() -> bool:
	return int(hero.hp) <= 0

func enemy_dead() -> bool:
	return int(enemy.hp) <= 0

# --- Turno del héroe ----------------------------------------------------------------

## Empieza el turno del héroe: bajan las recargas y deja de defender. Si el
## jefe va a usar su habilidad en el próximo turno, lo avisa (para Defender).
func begin_hero_turn() -> Array:
	defending = false
	for i in cooldowns.size():
		cooldowns[i] = maxi(cooldowns[i] - 1, 0)
	var ev: Array = []
	if enemy_special_next():
		ev.append({"log": DataRegistry.t("combat.log_boss_charge", [enemy.name, enemy.ability_name]), "tone": "taken"})
	return ev

func attack() -> Array:
	var ev: Array = []
	var variance := int(_bal("damage_variance", 1))
	var base := maxi(int(hero.atk) + rng.randi_range(-variance, variance), 1)
	var h := _strike(float(base), 0.0, ev)
	h["log"] = DataRegistry.t("combat.log_attack_crit" if h.crit else "combat.log_attack", [hero.name, h.enemy_dmg])
	h["tone"] = "crit" if h.crit else "hit"
	# Afinidad Sangre: los ataques normales abren heridas.
	var b := int(_fx("bleed_on_hit"))
	if b > 0 and not enemy_dead():
		_add_bleed(b)
		_proc(ev, "bleed_on_hit")
	return ev

func defend() -> Array:
	defending = true
	return [{"log": DataRegistry.t("combat.log_defend", [hero.name]), "tone": "info"}]

## Cura del héroe (poción): no pasa del máximo.
func heal_hero(amount: int, item_name: String) -> Array:
	var ev: Array = []
	var healed := _heal(amount, ev)
	ev.append({"log": DataRegistry.t("combat.log_heal", [hero.name, item_name, healed]), "tone": "heal"})
	return ev

## Después de la acción del héroe: "victory" | "free_turn" (ronda sorpresa:
## el enemigo pierde su turno) | "enemy".
func after_hero_action() -> String:
	if enemy_dead():
		return "victory"
	if surprise_round:
		surprise_round = false
		if DataRegistry.bal("combat.surprise_free_turn", true):
			return "free_turn"
	return "enemy"

# --- Activas -----------------------------------------------------------------------------

func soul_count() -> int:
	return (hero.souls as Array).size()

func active_of(i: int) -> Dictionary:
	var soul: Dictionary = hero.souls[i]
	var a: Dictionary = soul.get("active", {})
	return a

func ability_ready(i: int) -> bool:
	return i >= 0 and i < cooldowns.size() and cooldowns[i] == 0

## Poder de la activa: ataque del héroe + el del rango del alma + ESP + Eco.
func ability_power(i: int) -> int:
	var soul: Dictionary = hero.souls[i]
	return int(hero.atk) + int(soul.get("bonus_poder", 0)) + int(hero.ability_bonus) + int(_fx("active_power_flat"))

## Cada cuántos turnos se puede usar: la recarga menos Coro y pactos, pero
## nunca por debajo de almas.recarga_minima (o de la propia, si ya era menor):
## una activa lista todos los turnos deja a «Atacar» sin uso.
func recharge(i: int) -> int:
	var base := maxi(1, int(active_of(i).get("recarga", 1)))
	var floor_ := mini(base, maxi(1, DataRegistry.bal_i("almas.recarga_minima", 2)))
	return maxi(floor_, base - int(_fx("cooldown_reduction")))

## Daño de un golpe de la activa sin crítico ni marca (para el menú).
func ability_hit(i: int) -> int:
	return maxi(roundi(ability_power(i) * float(active_of(i).get("poder", 1.0)) + _fx("damage_bonus_flat")), 1)

## Golpes de una multigolpe (con Lluvia de acero).
func ability_hits(i: int) -> int:
	var a := active_of(i)
	return int(a.get("golpes", 1)) + int(_fx("extra_hits")) if String(a.get("tipo", "")) == "multigolpe" else 1

## Escudo que da una activa de tipo escudo.
func ability_shield(i: int) -> int:
	return roundi(ability_power(i) * float(active_of(i).get("poder", 1.0)) * (1.0 + _fx("shield_mult")))

## Sangrado que aplica (con Hemorragia).
func ability_bleed(i: int) -> int:
	return roundi(int(active_of(i).get("sangrado", 0)) * (1.0 + _fx("bleed_apply_mult")))

## Turnos de aturdimiento (con Cabeza dura), con tope; a un jefe, menos.
func ability_stun(i: int) -> int:
	var turns := mini(int(active_of(i).get("turnos", 0)) + int(_fx("stun_extra_turn")), int(cap("aturdir_turnos", 2)))
	if String(enemy.get("kind", "")) == RunRules.BOSS:
		turns = mini(turns, DataRegistry.bal_i("combat.boss_stun_max", 1))
	return turns

## Umbral de Ejecutar (con Verdugo).
func execute_threshold(i: int) -> float:
	return float(active_of(i).get("umbral", 0.0)) + _fx("execute_threshold_bonus")

func execute_ready(i: int) -> bool:
	return int(enemy.hp) <= roundi(int(enemy.max_hp) * execute_threshold(i))

## Usa la activa del alma i (debe estar lista).
func ability(i: int) -> Array:
	var ev: Array = []
	if not ability_ready(i):
		return ev
	var a := active_of(i)
	var aname := String(a.name)
	var who := String(hero.name)
	var p := ability_power(i) * float(a.poder)
	cooldowns[i] = recharge(i)
	# Para la UI: qué activa se usó (el cartel con su nombre).
	ev.append({"ability": i})
	match String(a.tipo):
		"golpe":
			var h := _strike(p, float(a.get("critico", 0.0)), ev)
			_log_hit(h, "combat.log_ability", [who, aname, h.enemy_dmg])
		"multigolpe":
			var total := 0
			var done := 0
			var first: Dictionary = {}
			var any_crit := false
			for k in ability_hits(i):
				if enemy_dead():
					break
				var h := _strike(p, 0.0, ev)
				total += int(h.enemy_dmg)
				done += 1
				h["combo"] = done
				any_crit = any_crit or bool(h.crit)
				if first.is_empty():
					first = h
			first["log"] = DataRegistry.t("combat.log_multi", [who, aname, done, total])
			first["tone"] = "crit" if any_crit else "hit"
			if done > 1:
				ev.append({"combo_total": total, "hits": done})
			_proc(ev, "extra_hits")
		"sangrado":
			var h := _strike(p, 0.0, ev)
			var st := ability_bleed(i)
			if not enemy_dead():
				_add_bleed(st)
				_proc(ev, "bleed_apply_mult")
			_log_hit(h, "combat.log_bleed_apply", [who, aname, h.enemy_dmg, st])
		"aturdir":
			var h := _strike(p, 0.0, ev)
			if enemy_dead():
				_log_hit(h, "combat.log_ability", [who, aname, h.enemy_dmg])
			elif stun_immune():
				_log_hit(h, "combat.log_stun_resist", [who, aname, h.enemy_dmg, enemy.name])
			else:
				stun = maxi(stun, ability_stun(i))
				_log_hit(h, "combat.log_stun", [who, aname, h.enemy_dmg, enemy.name])
				_proc(ev, "stun_extra_turn")
		"drenar":
			var h := _strike(p, 0.0, ev)
			var healed := _heal(roundi(int(h.enemy_dmg) * (float(a.cura) + _fx("drain_bonus_pct"))), ev, true)
			_log_hit(h, "combat.log_drain", [who, aname, h.enemy_dmg, healed])
			_proc(ev, "drain_bonus_pct")
		"escudo":
			var before := shield
			_add_shield(ability_shield(i))
			var s := shield - before
			ev.append({"shield": s, "log": DataRegistry.t("combat.log_shield", [who, aname, s]), "tone": "soul"})
			_proc(ev, "shield_mult")
		"marca":
			var h := _strike(p, 0.0, ev)
			var m := float(a.marca) + _fx("mark_bonus")
			if not enemy_dead():
				mark = minf(maxf(mark, m), cap("marca", 1.0))
			_log_hit(h, "combat.log_mark", [who, aname, h.enemy_dmg, roundi(m * 100.0)])
			_proc(ev, "mark_bonus")
		"debilitar":
			var h := _strike(p, 0.0, ev)
			if not enemy_dead():
				weak_turns = maxi(weak_turns, int(a.turnos))
				weak_pct = minf(maxf(weak_pct, float(a.debilita)), cap("debilita", 0.6))
				_add_bleed(int(_fx("weaken_bleed")))
				_proc(ev, "weaken_bleed")
			_log_hit(h, "combat.log_weaken", [who, aname, h.enemy_dmg, enemy.name])
		"ejecutar":
			var low := execute_ready(i)
			var h := _strike(p * (float(a.mult) if low else 1.0), 0.0, ev)
			_log_hit(h, "combat.log_execute" if low else "combat.log_ability", [who, aname, h.enemy_dmg])
			if low:
				h["execute"] = true
				_proc(ev, "execute_threshold_bonus")
	return ev

## Para la UI: avisa que saltó una sinergia (si el héroe la tiene); el
## manager busca de dónde sale (SoulBuild.sources). No cambia nada.
func _proc(ev: Array, type: String) -> void:
	if _fx(type) > 0.0:
		ev.append({"proc": type})

func _log_hit(h: Dictionary, key: String, args: Array) -> void:
	h["log"] = DataRegistry.t(key, args)
	h["tone"] = "crit" if bool(h.get("crit", false)) else "hit"

## Un golpe del héroe: + bonus plano, ×1,5 en la ronda sorpresa, × la marca
## (se gasta), crítico (×2 + Asesino/Verdugo); después robo de vida, la marca
## de los críticos (Asesino) y las monedas por crítico. Agrega el evento del
## golpe a ev y lo devuelve (para ponerle el texto).
func _strike(base: float, extra_crit: float, ev: Array) -> Dictionary:
	var dmg := base + _fx("damage_bonus_flat")
	if surprise_round:
		dmg *= _bal("surprise_damage_mult", 1.5)
	var marked := mark > 0.0
	if marked:
		dmg *= 1.0 + mark
		mark = 0.0
	var crit := rng.randf() < _fx("crit_chance") + float(hero.crit_bonus) + extra_crit
	if crit:
		dmg *= minf(_bal("crit_mult", 2.0) + _fx("crit_damage_bonus"), cap("critico_mult", 3.0))
	var n := maxi(roundi(dmg), 1)
	if one_hit:
		n = maxi(n, int(enemy.hp))
	enemy["hp"] = int(enemy.hp) - n
	var h := {"enemy_dmg": n, "crit": crit, "marked": marked}
	ev.append(h)
	if crit:
		_proc(ev, "crit_chance")
		_proc(ev, "crit_damage_bonus")
	var steal := minf(_fx("lifesteal_pct"), cap("robo_de_vida", 0.4))
	if steal > 0.0 and _heal(roundi(n * steal), ev, true) > 0:
		_proc(ev, "lifesteal_pct")
	if crit:
		if _fx("crit_marks") > 0.0 and not enemy_dead():
			mark = minf(maxf(mark, _fx("crit_marks")), cap("marca", 1.0))
			_proc(ev, "crit_marks")
		var c := int(_fx("coin_on_crit"))
		if c > 0:
			bonus_coins += c
			ev.append({"coins": c})
			_proc(ev, "coin_on_crit")
	return h

## Cura (sin pasar del máximo). Agrega el evento si curó algo; devuelve cuánto.
## steal: viene del enemigo (robo de vida, Drenar): la UI la dibuja viajando.
func _heal(amount: int, ev: Array, steal := false) -> int:
	if amount <= 0 or hero_dead():
		return 0
	var healed := mini(amount, int(hero.max_hp) - int(hero.hp))
	if healed <= 0:
		return 0
	hero["hp"] = int(hero.hp) + healed
	ev.append({"heal": healed, "steal": steal})
	return healed

# --- Turno del enemigo -------------------------------------------------------------

## ¿La próxima acción del enemigo es la habilidad de jefe? (cada N turnos
## suyos; aturdido no cuenta).
func enemy_special_next() -> bool:
	var every := int(_bal("boss_ability_every", 3))
	return String(enemy.kind) == RunRules.BOSS and every > 0 and stun == 0 and (enemy_turns + 1) % every == 0

## Qué va a hacer: "stunned" | "special" | "attack".
func enemy_intent() -> String:
	if stun > 0:
		return "stunned"
	return "special" if enemy_special_next() else "attack"

## Al empezar su turno el sangrado le hace daño (y baja uno).
func enemy_turn_start() -> Array:
	var ev: Array = []
	if bleed <= 0 or enemy_dead():
		return ev
	var dmg := bleed + int(_fx("bleed_damage_bonus"))
	bleed -= 1
	enemy["hp"] = int(enemy.hp) - dmg
	ev.append({"enemy_dmg": dmg, "bleed": true, "log": DataRegistry.t("combat.log_bleed_tick", [enemy.name, dmg]), "tone": "hit"})
	_proc(ev, "bleed_damage_bonus")
	var steal := minf(_fx("bleed_lifesteal_pct"), cap("robo_de_vida_sangrado", 0.5))
	if steal > 0.0 and _heal(roundi(dmg * steal), ev, true) > 0:
		_proc(ev, "bleed_lifesteal_pct")
	return ev

## La acción del enemigo: aturdido pierde el turno; si no, golpea (la
## habilidad de jefe pega más fuerte; Defender la frena).
func enemy_act() -> Array:
	var ev: Array = []
	var intent := enemy_intent()
	if intent == "stunned":
		stun -= 1
		if stun == 0:
			stun_resist = maxi(1, DataRegistry.bal_i("combat.stun_resist_actions", 2))
		ev.append({"log": DataRegistry.t("combat.log_enemy_dazed", [enemy.name]), "tone": "info"})
	else:
		enemy_turns += 1
		stun_resist = maxi(stun_resist - 1, 0)
		var raw: float
		if intent == "special":
			raw = int(enemy.atk) * _bal("boss_ability_mult", 1.6)
			ev.append({"log": DataRegistry.t("combat.log_boss_ability", [enemy.name, enemy.ability_name]), "tone": "taken"})
		else:
			var variance := int(_bal("damage_variance", 1))
			raw = int(enemy.atk) + rng.randi_range(-variance, variance)
		if ambush_pending:
			raw *= _bal("ambush_damage_mult", 1.5)
			ambush_pending = false
		if weak_turns > 0:
			raw *= 1.0 - weak_pct
		_hurt_hero(maxi(roundi(raw), 0), ev)
	# Debilitado dura turnos del enemigo (actúe o no).
	if weak_turns > 0:
		weak_turns -= 1
		if weak_turns == 0:
			weak_pct = 0.0
	return ev

## Golpe al héroe: Defender bloquea un % (más con algunas pasivas), las
## reducciones planas pueden dejarlo en 0, la DEF (puntos + Armazón) no baja
## de 1, el escudo absorbe, Negarse a caer salva una vez; después espinas y
## el contragolpe de Maestro de armas.
func _hurt_hero(raw: int, ev: Array) -> void:
	var dmg := raw
	if defending:
		var block := clampf(_bal("defend_block", 0.5) + _fx("defend_bonus_multiplier"), 0.0, _bal("defend_block_max", 0.9))
		dmg = int(dmg * (1.0 - block))
	dmg = maxi(dmg - int(_fx("damage_reduction_flat")), 0)
	var def := int(hero.def) + int(_fx("def_flat"))
	if def > 0 and dmg > 1:
		dmg = maxi(dmg - def, 1)
	if god_mode:
		dmg = 0
	var absorbed := mini(shield, dmg)
	shield -= absorbed
	dmg -= absorbed
	var saved := false
	if dmg >= int(hero.hp) and _fx("last_stand") > 0.0 and not last_stand_used:
		dmg = int(hero.hp) - 1
		last_stand_used = true
		saved = true
	hero["hp"] = int(hero.hp) - dmg
	var text := DataRegistry.t("combat.log_enemy_hit_shield", [enemy.name, hero.name, dmg, absorbed]) if absorbed > 0 \
		else DataRegistry.t("combat.log_enemy_hit", [enemy.name, hero.name, dmg])
	ev.append({"hero_dmg": dmg, "absorbed": absorbed, "log": text, "tone": "taken", "guarded": defending})
	if defending:
		_proc(ev, "defend_bonus_multiplier")
	if saved:
		ev.append({"last_stand": true, "log": DataRegistry.t("combat.log_last_stand", [hero.name]), "tone": "soul"})
		_proc(ev, "last_stand")
	var thorns := int(_fx("thorns_flat"))
	if thorns > 0 and dmg + absorbed > 0 and not enemy_dead():
		enemy["hp"] = int(enemy.hp) - thorns
		ev.append({"enemy_dmg": thorns, "thorns": true, "log": DataRegistry.t("combat.log_thorns", [hero.name, thorns]), "tone": "soul"})
		_proc(ev, "thorns_flat")
	var counter := _fx("defend_counter")
	if defending and counter > 0.0 and not enemy_dead() and not hero_dead():
		var c := maxi(roundi(int(hero.atk) * counter), 1)
		enemy["hp"] = int(enemy.hp) - c
		ev.append({"enemy_dmg": c, "counter": true, "log": DataRegistry.t("combat.log_counter", [hero.name, c]), "tone": "hit"})
		_proc(ev, "defend_counter")
	if hero_dead():
		hero["hp"] = 0
		ev.append({"log": DataRegistry.t("combat.log_fallen", [hero.name]), "tone": "taken"})

# --- Para la UI ----------------------------------------------------------------------

## Estados del enemigo para mostrar: [{id, value}] (sangrado, aturdido,
## marca en %, debilitado en turnos, carga = prepara la habilidad de jefe).
func enemy_statuses() -> Array:
	var out: Array = []
	if bleed > 0:
		out.append({"id": "sangrado", "value": bleed})
	if stun > 0:
		out.append({"id": "aturdido", "value": stun})
	if mark > 0.0:
		out.append({"id": "marca", "value": roundi(mark * 100.0)})
	if weak_turns > 0:
		out.append({"id": "debil", "value": weak_turns})
	if enemy_special_next():
		out.append({"id": "carga", "value": 0})
	return out
