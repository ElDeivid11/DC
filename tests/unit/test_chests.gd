extends TestCase
## Cofres con tragaperras (RunRules.chest_slots + GameState.open_chest): el
## resultado sale antes de girar, el premio es raro y solo con tres iguales,
## los «casi» son los dos primeros iguales, y cada premio se aplica.

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

## Corre f con chest_slots.<key> = value y lo deja como estaba.
func _with_slots(key: String, value: Variant, f: Callable) -> void:
	var slots: Dictionary = DataRegistry.balance.chest_slots
	var before: Variant = slots[key]
	slots[key] = value
	f.call()
	slots[key] = before

func test_premio_raro_y_solo_con_tres_iguales() -> void:
	var rng := _rng(11)
	var n := 4000
	var prizes := 0
	var teased := 0
	var prize_ids := DataRegistry.balance.chest_slots.premios as Dictionary
	for i in n:
		var r := RunRules.chest_slots(rng)
		var reels: Array = r.reels
		eq(reels.size(), 3, "tres rodillos")
		var prize := String(r.prize)
		if prize != "":
			prizes += 1
			check(prize_ids.has(prize), "%s es un premio" % prize)
			check(reels[0] == prize and reels[1] == prize and reels[2] == prize, "el premio son tres iguales")
		else:
			check(not (reels[0] == reels[1] and reels[1] == reels[2]), "sin premio nunca hay tres iguales (%s)" % [reels])
			if reels[0] == reels[1]:
				teased += 1
				check(String(reels[0]) != RunRules.SLOT_FILLER, "el «casi» es de un premio")
	var rate := float(prizes) / n
	var target := DataRegistry.bal_f("chest_slots.premio_chance", 0.1)
	check(absf(rate - target) < 0.03, "premio en %.1f%% de los cofres (se pide %.0f%%)" % [rate * 100.0, target * 100.0])
	check(teased * 5 > n, "hay «casi» para la tensión (%d de %d)" % [teased, n])

func test_mismo_azar_mismo_cofre() -> void:
	GameState.new_run(5, false)
	var pool := MetaState.available_items()
	var a := GameState.open_chest(_rng(3), pool, false)
	GameState.new_run(5, false)
	var b := GameState.open_chest(_rng(3), pool, false)
	eq(a.reels, b.reels, "mismos rodillos")
	eq(a.coins, b.coins, "mismas monedas")
	eq(a.items, b.items, "mismos objetos")

func test_cada_premio_se_aplica() -> void:
	var pool := MetaState.available_items()
	_with_slots("premio_chance", 1.0, func() -> void:
		for prize: String in DataRegistry.CHEST_PRIZES:
			_with_slots("premios", {prize: 1}, func() -> void:
				GameState.new_run(9, false)
				GameState.inventory.clear()
				var streak := GameState.soul_dry_streak
				var r := GameState.open_chest(_rng(4), pool, false)
				eq(String(r.prize), prize, "sale %s" % prize)
				eq(int(GameState.coin_breakdown.get("chests", 0)), int(r.coins), "las monedas se cobran")
				match prize:
					"moneda":
						eq(int(r.coins), int(r.coins_base) * DataRegistry.bal_i("chest_slots.monedas_mult", 2), "monedas ×2")
					"trofeo":
						eq(int(r.coins), int(r.coins_base) * DataRegistry.bal_i("chest_slots.trofeo_mult", 3), "monedas ×3")
						eq((r.items as Array).size(), 2, "trofeo: un objeto más")
					"objeto":
						eq((r.items as Array).size(), 2, "un objeto más")
						eq(int(r.coins), int(r.coins_base), "monedas de siempre")
					"alma":
						eq(GameState.soul_dry_streak, streak + DataRegistry.bal_i("chest_slots.racha_alma", 4), "la racha de alma sube")
						check(int(r.streak) > 0, "lo dice para mostrarlo")
				eq(GameState.inventory.size(), (r.items as Array).size(), "los objetos van al inventario")))
	GameState.new_run(1, false)

func test_inventario_lleno() -> void:
	GameState.new_run(2, false)
	GameState.inventory.clear()
	for i in GameState.inventory_capacity():
		GameState.inventory.append("venda")
	var r := GameState.open_chest(_rng(8), MetaState.available_items(), false)
	eq((r.left as Array).size(), (r.items as Array).size(), "lo que no entra queda afuera (para dejarlo en el piso)")
	GameState.new_run(1, false)

func test_textos_de_premios() -> void:
	for prize: String in DataRegistry.CHEST_PRIZES:
		check(DataRegistry.has_text("chest.prize." + prize), "chest.prize.%s tiene texto" % prize)
		check(UIChestSlots.SYMBOLS.has(prize), "%s tiene símbolo en los rodillos" % prize)
	check(UIChestSlots.SYMBOLS.has(RunRules.SLOT_FILLER), "el relleno tiene símbolo")
	for sym: String in UIChestSlots.SYMBOLS.keys():
		var spec: Array = UIChestSlots.SYMBOLS[sym]
		check(UIIcon.texture_for(String(spec[0]), String(spec[1])) != null, "el ícono de %s existe en el kit" % sym)

