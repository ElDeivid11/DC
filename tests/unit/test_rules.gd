extends TestCase
## RunRules + mejoras de MetaState: costes con tope, curva de almas, huida,
## monedas por kill.

func test_coste_de_mejoras_con_tope() -> void:
	var vit := DataRegistry.get_upgrade("vitalidad")
	eq(RunRules.upgrade_cost(vit, 0), 20, "nivel 1 = coste base")
	eq(RunRules.upgrade_cost(vit, 4), 100, "nivel 5 = base × 5")
	eq(RunRules.upgrade_cost(vit, 5), -1, "al tope no hay siguiente nivel")

func test_comprar_mejora() -> void:
	MetaState.reset()
	MetaState.coins = 25
	check(MetaState.buy("vitalidad"), "alcanza para el nivel 1")
	eq(MetaState.coins, 5, "descuenta el coste")
	eq(MetaState.upgrade_level("vitalidad"), 1, "sube de nivel")
	check(not MetaState.buy("vitalidad"), "el nivel 2 cuesta 40")
	MetaState.coins = 100000
	MetaState.upgrades["vitalidad"] = 5
	check(not MetaState.can_buy("vitalidad"), "tope de 5 niveles aunque sobren monedas")
	near(MetaState.upgrade_bonus("max_hp_flat"), 5 * float(DataRegistry.get_upgrade("vitalidad").efecto.valor), "5 niveles × valor por nivel")

func test_provisiones_suma_pociones() -> void:
	MetaState.reset()
	var base := MetaState.start_items().size()
	MetaState.upgrades["provisiones"] = 2
	eq(MetaState.start_items().size(), base + 2, "+1 poción por nivel")

func test_curva_de_almas() -> void:
	near(RunRules.soul_drop_chance(3, RunRules.BOSS, 0.0), 1.0, "jefe siempre")
	near(RunRules.soul_drop_chance(9, RunRules.ELITE, 0.0), 0.25, "élite")
	near(RunRules.soul_drop_chance(10, RunRules.NORMAL, 0.0), 0.08, "normal rango 10")
	near(RunRules.soul_drop_chance(9, RunRules.NORMAL, 0.0), 0.088, "normal rango 9 (factor 1.1)")
	near(RunRules.soul_drop_chance(10, RunRules.NORMAL, 10.0), 0.18, "Sabiduría +10 puntos")

func test_huida_segun_rango() -> void:
	# Piso 1: rangos 8–9 → rango medio 8.5.
	near(RunRules.flee_chance(9, 1), 0.55, "enemigo más débil que la media")
	near(RunRules.flee_chance(8, 1), 0.45, "enemigo más fuerte que la media")
	near(RunRules.flee_chance(1, 1), 0.1, "mínimo")

func test_monedas_por_kill() -> void:
	eq(RunRules.kill_coins(9, RunRules.NORMAL, 1), 2, "11 − rango")
	eq(RunRules.kill_coins(9, RunRules.ELITE, 1), 4, "élite ×2")
	eq(RunRules.kill_coins(5, RunRules.BOSS, 2), 50, "jefe = 25 × piso")
	eq(RunRules.first_kill_bonus(4), 70, "primera kill = 10 × (11 − rango)")

func test_stats_de_jefe() -> void:
	# Stats del rango × boss_stat_mult, redondeado.
	var boss := RunRules.enemy_stats(7, RunRules.BOSS)
	var base := DataRegistry.stats_for_rank(7)
	var mult := DataRegistry.bal_f("enemies.boss_stat_mult", 1.5)
	eq(int(boss.hp), roundi(int(base.hp) * mult), "hp × boss_stat_mult")
	eq(int(boss.atk), roundi(int(base.atk) * mult), "atk × boss_stat_mult")
	check(int(boss.hp) > int(base.hp), "el jefe tiene más HP que un normal del mismo rango")
