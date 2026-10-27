extends TestCase
## Almas: afinidades, pactos (SoulBuild) y las reglas del combate que las usan
## (CombatCore): recargas, estados del enemigo, escudo, Negarse a caer.

func _soul(id: String, rank := 9) -> Dictionary:
	return DataRegistry.make_soul(id, rank, "test")

func _hero(souls: Array, hp := 30, atk := 6) -> Dictionary:
	return {"id": "bjorn", "name": "Bjorn", "hp": hp, "max_hp": hp, "atk": atk, "def": 0,
		"ability_bonus": 0, "crit_bonus": 0.0, "souls": souls}

## Núcleo con un rng sin críticos (crit_chance 0 + rng fijo no alcanza: se
## fuerza con una semilla y sin pasivas de crítico).
func _core(souls: Array, enemy_hp := 100, enemy_atk := 5, kind := "normal", mode := "normal") -> CombatCore:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var c := CombatCore.new(rng)
	c.setup(_hero(souls), {"name": "Esqueleto", "hp": enemy_hp, "atk": enemy_atk, "kind": kind, "ability_name": "Golpe"}, mode)
	return c

func test_datos_de_sinergias() -> void:
	# Cada afinidad la tienen al menos 3 almas que se pueden conseguir (para
	# que su último nivel sea alcanzable) y cada pacto junta dos almas reales.
	var counts := {}
	for id: String in DataRegistry.souls.keys():
		if id == "jefe_senor":
			continue # la suelta el último jefe: la run termina ahí
		for a: Variant in DataRegistry.get_soul(id).afinidades:
			counts[String(a)] = int(counts.get(String(a), 0)) + 1
	for af in DataRegistry.affinity_ids():
		var levels: Array = DataRegistry.get_affinity(af).niveles
		var top := int((levels[levels.size() - 1] as Dictionary).cantidad)
		check(int(counts.get(af, 0)) >= top, "%s: %d almas para su nivel de %d" % [af, int(counts.get(af, 0)), top])
	for pid: String in DataRegistry.pacts.keys():
		for sid: Variant in DataRegistry.get_pact(pid).almas:
			check(not DataRegistry.get_soul(String(sid)).is_empty(), "pacto %s: %s existe" % [pid, sid])
	# Dos almas de jefe (garantizadas) no forman un pacto: saldría gratis.
	for pid: String in DataRegistry.pacts.keys():
		var pair: Array = DataRegistry.get_pact(pid).almas
		var bosses := 0
		for sid: Variant in pair:
			if String(DataRegistry.get_soul(String(sid)).species) == "nigromante":
				bosses += 1
		check(bosses < 2, "pacto %s no es de dos jefes" % pid)

func test_afinidades_y_niveles() -> void:
	var souls := [_soul("esbirro_tajo"), _soul("guardian_hacha")] # acero+sangre ×2
	var counts := SoulBuild.affinity_counts(souls)
	eq(int(counts.acero), 2, "dos de acero")
	eq(int(counts.sangre), 2, "dos de sangre")
	eq(SoulBuild.tier_reached("acero", 2), 1, "2 almas: primer nivel")
	eq(SoulBuild.tier_reached("acero", 1), 0, "1 alma: nada")
	eq(SoulBuild.tier_reached("acero", 9), 2, "muchas: todos los niveles")
	var fx := SoulBuild.effects(souls)
	near(float(fx.get("damage_bonus_flat", 0.0)), 1.0, "Acero I: +1 de daño")
	near(float(fx.get("bleed_on_hit", 0.0)), 1.0, "Sangre I: sangrado al atacar")
	near(float(fx.get("defend_bonus_multiplier", 0.0)), 0.25, "pasiva del hacha")
	var four := [_soul("esbirro_tajo"), _soul("guardian_hacha"), _soul("esbirro_escudazo"), _soul("arquero_flecha")]
	fx = SoulBuild.effects(four)
	near(float(fx.get("damage_bonus_flat", 0.0)), 2.0, "Acero II acumula con Acero I")
	near(float(fx.get("defend_counter", 0.0)), 1.0, "Acero II: contraataque")

func test_pactos() -> void:
	var souls := [_soul("esbirro_tajo")]
	eq(SoulBuild.active_pacts(souls).size(), 0, "con una sola alma no hay pacto")
	var partial := SoulBuild.partial_pacts(souls)
	check(partial.any(func(p: Dictionary) -> bool: return String(p.id) == "hemorragia" and String(p.missing) == "arquero_veneno"), "Hemorragia a medias: falta la Flecha Envenenada")
	souls.append(_soul("arquero_veneno"))
	check(SoulBuild.active_pacts(souls).has("hemorragia"), "las dos juntas sellan el pacto")
	near(SoulBuild.total(souls, "bleed_apply_mult"), 1.0, "efecto del pacto")
	var diff := SoulBuild.diff_if_added([_soul("esbirro_tajo")], _soul("arquero_veneno"))
	check((diff.pacts as Array).has("hemorragia"), "el aviso dice que sella el pacto")
	check((diff.tiers as Array).any(func(t: Dictionary) -> bool: return String(t.id) == "sangre"), "y que activa Sangre I")
	var lost := SoulBuild.diff_if_added(souls, _soul("esbirro_terco"), 1)
	check((lost.pacts_lost as Array).has("hemorragia"), "cambiar una rompe el pacto")

func test_recarga_de_activas() -> void:
	var c := _core([_soul("esbirro_tajo")]) # recarga 2
	c.begin_hero_turn()
	check(c.ability_ready(0), "todas empiezan listas")
	c.ability(0)
	check(not c.ability_ready(0), "recién usada no está lista")
	c.begin_hero_turn()
	check(not c.ability_ready(0), "recarga 2: el turno siguiente tampoco")
	c.begin_hero_turn()
	check(c.ability_ready(0), "dos turnos después, lista")
	# Coro (Espíritu II) baja la recarga, nunca de 1.
	var fast := _core([_soul("esbirro_tajo")])
	fast.fx["cooldown_reduction"] = 5.0
	eq(fast.recharge(0), 1, "mínimo cada turno")

func test_poder_de_activa() -> void:
	var weak := _core([_soul("arquero_flecha", 9)])
	var strong := _core([_soul("arquero_flecha", 1)])
	check(strong.ability_power(0) > weak.ability_power(0), "alma de rango alto: más poder")
	eq(weak.ability_power(0), 6 + int(_soul("arquero_flecha", 9).bonus_poder), "poder = ataque + rango del alma")
	eq(weak.ability_hit(0), roundi(weak.ability_power(0) * 1.4), "Flecha Certera: 140% del poder")

func test_sangrado_y_aturdir() -> void:
	var c := _core([_soul("esbirro_tajo"), _soul("esbirro_escudazo")], 100)
	c.begin_hero_turn()
	c.ability(0)
	eq(c.bleed, 3, "Tajo Oxidado: 3 de sangrado")
	var hp := int(c.enemy.hp)
	c.enemy_turn_start()
	eq(int(c.enemy.hp), hp - 3, "el sangrado pega al empezar su turno")
	eq(c.bleed, 2, "y baja uno")
	c.ability(1)
	eq(c.stun, 1, "Escudazo aturde un turno")
	eq(c.enemy_intent(), "stunned", "aturdido no ataca")
	var hero_hp := int(c.hero.hp)
	c.enemy_act()
	eq(int(c.hero.hp), hero_hp, "pierde el turno")
	check(c.stun_immune, "después resiste")
	c.cooldowns[1] = 0
	c.ability(1)
	eq(c.stun, 0, "no se puede encadenar")
	c.enemy_act()
	check(not c.stun_immune, "al atacar vuelve a poder aturdirse")

func test_escudo_y_negarse_a_caer() -> void:
	var c := _core([_soul("guardian_muro")], 100, 10)
	c.begin_hero_turn()
	c.ability(0)
	var s := c.shield
	check(s > 0, "Muro de Bronce da escudo")
	c.hero["hp"] = 30
	c._hurt_hero(5, [])
	eq(int(c.hero.hp), 30, "el escudo absorbe")
	eq(c.shield, s - 5, "y se gasta")
	# Hueso II: un golpe mortal deja con 1 HP, una vez por combate.
	var b := _core([], 100, 50)
	b.fx["last_stand"] = 1.0
	b._hurt_hero(99, [])
	eq(int(b.hero.hp), 1, "se niega a caer")
	b._hurt_hero(99, [])
	check(b.hero_dead(), "la segunda vez cae")

func test_marca_y_ejecutar() -> void:
	var c := _core([_soul("arquero_fantasma"), _soul("guardian_hacha")], 200)
	c.begin_hero_turn()
	c.ability(0)
	near(c.mark, 0.5, "Flecha Fantasma marca +50%")
	var before := int(c.enemy.hp)
	c.attack()
	var with_mark := before - int(c.enemy.hp)
	near(c.mark, 0.0, "la marca se gasta en el golpe siguiente")
	check(with_mark >= roundi((6 - 1 + 1) * 1.5) - 1, "el golpe marcado pega más (%d)" % with_mark)
	c.enemy["hp"] = 30 # 15% de 200: debajo del umbral de Ejecutar
	check(c.execute_ready(1), "debajo del 35%: ejecuta")
	var e_before := int(c.enemy.hp)
	c.ability(1)
	check(e_before - int(c.enemy.hp) >= c.ability_hit(1) * 2 - 1, "Ejecutar duplica el daño")

func test_golpe_cargado_del_jefe() -> void:
	var c := _core([], 999, 10, RunRules.BOSS)
	var every := DataRegistry.bal_i("combat.boss_ability_every", 3)
	for i in every - 1:
		check(not c.enemy_special_next(), "turno %d: ataque normal" % (i + 1))
		c.enemy_act()
	check(c.enemy_special_next(), "lo anuncia antes")
	check(c.begin_hero_turn().size() > 0, "el registro avisa que carga")
	c.hero["hp"] = 999
	c.hero["max_hp"] = 999
	c.defend()
	c.enemy_act()
	var defended := 999 - int(c.hero.hp)
	eq(defended, int(roundi(10 * DataRegistry.bal_f("combat.boss_ability_mult", 1.6)) * (1.0 - DataRegistry.bal_f("combat.defend_block", 0.5))), "Defender frena la mitad")

func test_sorpresa_y_emboscada() -> void:
	var s := _core([], 100, 5, "normal", "surprise")
	s.begin_hero_turn()
	s.attack()
	eq(s.after_hero_action(), "free_turn", "sorpresa: el enemigo pierde su primer turno")
	s.begin_hero_turn()
	s.attack()
	eq(s.after_hero_action(), "enemy", "después, turnos normales")
	var a := _core([], 100, 4, "normal", "ambush")
	check(a.ambush_pending, "emboscada: el enemigo pega primero")
	a.enemy_act()
	check(30 - int(a.hero.hp) >= roundi(3 * DataRegistry.bal_f("combat.ambush_damage_mult", 1.5)), "y más fuerte")

func test_efectos_fuera_del_combate() -> void:
	GameState.new_run(11, false)
	var m := GameState.hero()
	GameState.add_soul("bjorn", _soul("arquero_veneno")) # Musgo de cripta: cura 3 al ganar
	m["hp"] = 10
	eq(GameState.heal_after_victory(), 3, "Musgo de cripta cura al ganar")
	var xp := GameState.kill_xp(9, RunRules.NORMAL)
	GameState.add_soul("bjorn", _soul("esbirro_terco"))
	GameState.add_soul("bjorn", _soul("arquero_doble"))
	GameState.add_soul("bjorn", _soul("jefe_archi"))
	check(GameState.kill_xp(9, RunRules.NORMAL) > xp, "Fortuna III: más EXP")
	check(GameState.soul_chance_bonus() >= 10.0, "Fortuna III: más almas")
	check(GameState.party_coin_bonus() >= 0.5, "Fortuna I + Diezmo: más monedas")
