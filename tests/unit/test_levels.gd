extends TestCase
## Niveles, EXP y estadísticas de la run (GameState + RunRules).

func _member() -> Dictionary:
	GameState.new_run(5, false)
	return GameState.party[0]

func test_exp_y_subida_de_nivel() -> void:
	var m := _member()
	eq(int(m.level), 1, "empieza en nivel 1")
	var need := RunRules.xp_to_next(1)
	var ups := GameState.add_xp(need - 1)
	check(ups.is_empty(), "sin llegar no sube")
	ups = GameState.add_xp(1)
	eq(int(m.level), 2, "sube al llegar a la EXP del nivel")
	eq(int(m.points), DataRegistry.bal_i("leveling.points_per_level", 3), "gana puntos")
	eq(ups.size(), GameState.party.size(), "sube todo el equipo vivo")
	eq(int(m.xp), 0, "la EXP sobrante arranca de cero")

func test_dos_niveles_de_una() -> void:
	var m := _member()
	GameState.add_xp(RunRules.xp_to_next(1) + RunRules.xp_to_next(2) + 3)
	eq(int(m.level), 3, "una kill grande puede subir dos niveles")
	eq(int(m.xp), 3, "sobra lo que pasó")

func test_nivel_maximo() -> void:
	var m := _member()
	GameState.add_xp(100000)
	eq(int(m.level), RunRules.max_level(), "tope de nivel")
	eq(int(m.xp), 0, "en el tope la EXP no se acumula")

func test_caidos_no_reciben_exp() -> void:
	var m := _member()
	m["hp"] = 0
	GameState.add_xp(RunRules.xp_to_next(1))
	eq(int(m.level), 1, "un caído no sube")

func test_alma_extra_cada_dos_niveles() -> void:
	var m := _member()
	var base := GameState.member_soul_capacity(m)
	GameState.add_xp(RunRules.xp_to_next(1))
	eq(GameState.member_soul_capacity(m), base + 1, "nivel 2: +1 alma")
	GameState.add_xp(RunRules.xp_to_next(2))
	eq(GameState.member_soul_capacity(m), base + 1, "nivel 3: igual")
	GameState.add_xp(RunRules.xp_to_next(3))
	eq(GameState.member_soul_capacity(m), base + 2, "nivel 4: +2 almas")

func test_repartir_puntos() -> void:
	var m := _member()
	GameState.add_xp(RunRules.xp_to_next(1))
	var hp_before := GameState.member_max_hp(m)
	var atk_before := GameState.member_atk(m)
	check(not GameState.apply_points(m, {"vit": 5}), "no se gastan más puntos de los que hay")
	check(not GameState.apply_points(m, {"magia": 1}), "ni estadísticas que no existen")
	check(GameState.apply_points(m, {"vit": 2, "atq": 1}), "reparto válido")
	eq(int(m.points), 0, "se gastaron los 3")
	eq(GameState.member_max_hp(m), hp_before + RunRules.stat_hp(2), "VIT sube el HP máximo")
	eq(GameState.member_atk(m), atk_before + RunRules.stat_atk(1), "ATQ sube el ataque")

func test_exp_por_enemigo() -> void:
	check(RunRules.kill_xp(9, RunRules.NORMAL) < RunRules.kill_xp(5, RunRules.NORMAL), "más rango, más EXP")
	check(RunRules.kill_xp(7, RunRules.ELITE) > RunRules.kill_xp(7, RunRules.NORMAL), "la élite da más")
	check(RunRules.kill_xp(7, RunRules.BOSS) > RunRules.kill_xp(7, RunRules.ELITE), "el jefe da mucho más")
