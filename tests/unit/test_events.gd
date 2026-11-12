extends TestCase
## Eventos de sala (fuente, santuario, trampa, mercader) y forja de almas:
## dónde los pone el generador y las reglas de GameState.

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _soul(id: String, rank := 9) -> Dictionary:
	return DataRegistry.make_soul(id, rank, "test")

func test_el_generador_pone_los_eventos() -> void:
	for n in range(1, DataRegistry.floor_count() + 1):
		var want: Dictionary = DataRegistry.get_floor(n).get("eventos", {})
		for s in [3, 4, 5]:
			var fd := FloorGenerator.generate(n, s, [])
			var got := {}
			var used := {}
			for ev: Dictionary in fd.events:
				got[String(ev.type)] = int(got.get(String(ev.type), 0)) + 1
				check(not used.has(ev.cell) and not fd.chests.has(ev.cell), "piso %d: una cosa por celda" % n)
				used[ev.cell] = true
				check(not fd.is_wall(ev.cell) and ev.cell != fd.start_cell, "piso %d: el evento está en el piso" % n)
				check(fd.enemy_at(ev.cell).is_empty(), "piso %d: sin enemigo encima" % n)
			for type in FloorGenerator.EVENT_TYPES:
				eq(int(got.get(type, 0)), int(want.get(type, 0)), "piso %d semilla %d: %s" % [n, s, type])
			eq(fd.traps.size(), int(want.get("trampas", 0)), "piso %d: trampas" % n)
			for c in fd.traps:
				check(not fd.is_wall(c) and c != fd.start_cell and not used.has(c) and not fd.chests.has(c), "piso %d: trampa en piso libre" % n)
				check(not fd.boss_room.has_point(c), "piso %d: sin trampas en la sala del jefe" % n)

func test_fuente_y_trampa() -> void:
	GameState.new_run(1, false)
	var m := GameState.hero()
	var max_hp := GameState.member_max_hp(m)
	m["hp"] = 1
	var healed := GameState.drink_fountain()
	eq(healed, roundi(max_hp * DataRegistry.bal_f("eventos.fuente_cura", 0.4)), "la fuente cura su parte")
	m["hp"] = max_hp
	var r := GameState.spring_trap(_rng(1))
	check(not bool(r.dodged) and int(r.dmg) > 0 and int(m.hp) == max_hp - int(r.dmg), "la trampa lastima")
	m["hp"] = 1
	GameState.spring_trap(_rng(1))
	eq(int(m.hp), 1, "pero no mata")
	# Con mucha AGI se esquiva a veces (con tope).
	(m.stats as Dictionary)["agi"] = 200
	var dodges := 0
	var rng := _rng(2)
	for i in 400:
		m["hp"] = max_hp
		if bool(GameState.spring_trap(rng).dodged):
			dodges += 1
	var cap := DataRegistry.bal_f("eventos.trampa_esquive_max", 0.6)
	check(absf(dodges / 400.0 - cap) < 0.08, "esquive con tope (%d de 400)" % dodges)
	GameState.new_run(1, false)

func test_santuario_y_bendiciones() -> void:
	GameState.new_run(1, false)
	var m := GameState.hero()
	var hp := int(m.hp)
	var options := GameState.roll_blessings(_rng(3))
	eq(options.size(), DataRegistry.bal_i("eventos.santuario_opciones", 2), "ofrece sus opciones")
	check(options[0] != options[1], "sin repetir")
	check(GameState.pray("filo"), "se puede rezar con vida")
	eq(int(m.hp), hp - GameState.shrine_cost(), "cuesta sangre")
	check(not GameState.roll_blessings(_rng(4)).has("filo"), "no vuelve a ofrecer la que ya se tiene")
	var core := CombatCore.new(_rng(5))
	core.setup(GameState.combat_hero(m), {"name": "x", "hp": 50, "atk": 1})
	eq(core._fx("damage_bonus_flat"), float((DataRegistry.get_blessing("filo").efectos[0] as Dictionary).value), "la bendición entra al combate")
	check(GameState.pray("codicia"), "otra")
	check(GameState.party_coin_bonus() >= 0.25, "y a las monedas")
	m["hp"] = GameState.shrine_cost()
	check(not GameState.pray("ojo") and int(m.hp) == GameState.shrine_cost(), "con poca vida no reza (no mata)")
	for id: String in DataRegistry.blessings.keys():
		var b := DataRegistry.get_blessing(id)
		check(UIIcon.texture_for(String(b.icono), String(b.rampa)) != null, "el ícono de %s existe" % id)
	GameState.new_run(1, false)
	check(GameState.blessings.is_empty(), "las bendiciones no pasan a la run siguiente")

func test_mercader() -> void:
	GameState.new_run(1, false)
	GameState.inventory.clear()
	var pool := MetaState.available_items()
	var stock := GameState.roll_shop(_rng(6), pool)
	check(stock.size() > 0 and stock.size() <= DataRegistry.bal_i("eventos.mercader_stock", 3), "tiene qué vender")
	var id: String = stock[0]
	eq(GameState.buy_item(id), "coins", "sin monedas no se compra")
	GameState.add_coins(500, "kills")
	var before := GameState.run_coins()
	eq(GameState.buy_item(id), "", "con monedas sí")
	eq(GameState.run_coins(), before - GameState.shop_price(id), "y se descuentan")
	check(GameState.inventory.has(id), "el objeto va al inventario")
	check(GameState.shop_price("pocion_mayor") > GameState.shop_price("pocion_menor"), "lo raro cuesta más")
	while not GameState.inventory_full():
		GameState.inventory.append("venda")
	eq(GameState.buy_item(id), "full", "con el inventario lleno, no")
	# Lo gastado se descuenta de lo que vuelve al Hub.
	GameState.outcome = "retiro"
	var res := RunRewards.compute(GameState.snapshot(), MetaState)
	eq(int(res.coins.gastos), GameState.shop_price(id), "el resumen cuenta lo gastado")
	GameState.new_run(1, false)

func test_forja() -> void:
	GameState.new_run(1, false)
	var m := GameState.hero()
	GameState.add_soul(String(m.id), _soul("esbirro_tajo", 9))
	GameState.add_soul(String(m.id), _soul("esbirro_tajo", 8))
	GameState.add_soul(String(m.id), _soul("arquero_doble", 9))
	var souls: Array = m.souls
	# Templar: cuesta monedas y sube un rango.
	check(not GameState.temper_soul(2), "sin monedas no se templa")
	GameState.add_coins(1000, "kills")
	var power := int((souls[2] as Dictionary).bonus_poder)
	var cost := GameState.temper_cost(souls[2])
	var coins := GameState.run_coins()
	check(GameState.temper_soul(2), "templar")
	eq(int((souls[2] as Dictionary).source_rank), 8, "un rango mejor")
	check(int((souls[2] as Dictionary).bonus_poder) >= power, "con más poder")
	eq(GameState.run_coins(), coins - cost, "y se paga")
	check(GameState.temper_cost(souls[2]) > cost, "cada rango cuesta más")
	# Fundir: dos iguales quedan en una, mejor.
	eq(GameState.fusable_pairs(), [[0, 1]], "hay un par de almas iguales")
	check(GameState.fuse_souls(0, 1), "fundir")
	eq(souls.size(), 2, "queda una sola y se libera un espacio")
	eq(int((souls[0] as Dictionary).source_rank), 8 - DataRegistry.bal_i("eventos.forja_fundir_rangos", 2), "dos rangos mejor que la mejor")
	check(not GameState.fuse_souls(0, 1), "dos distintas no se funden")
	# Sacrificar: se pierde y da monedas.
	coins = GameState.run_coins()
	var value := GameState.sacrifice_value(souls[1])
	eq(GameState.sacrifice_soul(1), value, "da su valor")
	eq(souls.size(), 1, "y se pierde")
	eq(GameState.run_coins(), coins + value, "las monedas entran")
	# El rango no pasa de 1.
	(souls[0] as Dictionary)["source_rank"] = 1
	check(not GameState.can_temper(0), "rango máximo")
	GameState.new_run(1, false)
