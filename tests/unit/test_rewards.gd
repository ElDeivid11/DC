extends TestCase
## RunRewards: recompensas de fin de run y su aplicación a MetaState.

func _kill_snap(outcome: String) -> Dictionary:
	return snap({
		"outcome": outcome,
		"coin_breakdown": {"kills": 20, "boss": 0, "chests": 10},
		"kills_by_species": {"esqueleto_esbirro": 2},
		"kills_total": 2,
		"seen_species": {"esqueleto_esbirro": true, "esqueleto_picaro": true},
		"max_floor": 2,
	})

func test_muerte_conserva_la_mitad() -> void:
	MetaState.reset()
	var r := RunRewards.compute(_kill_snap("muerte"), MetaState)
	eq(int(r.coins.first_kill), 20, "primera kill de esbirro (rango 9) = 20")
	eq(int(r.coins.gross), 50, "20 kills + 10 cofres + 20 primera kill")
	eq(int(r.coins.total), 25, "se conserva el 50% al morir")
	eq(int(r.coins.lost), 25, "lo perdido")
	eq((r.new_species as Array).size(), 1, "una especie nueva")

func test_retiro_conserva_todo() -> void:
	MetaState.reset()
	var r := RunRewards.compute(_kill_snap("retiro"), MetaState)
	eq(int(r.coins.total), 50, "100% al retirarse")

func test_botin_suma_porcentaje() -> void:
	MetaState.reset()
	MetaState.upgrades["botin"] = 2
	var r := RunRewards.compute(_kill_snap("retiro"), MetaState)
	eq(int(r.coins.botin_bonus), 5, "10% de 50")
	eq(int(r.coins.total), 55, "total con Botín")

func test_primera_kill_solo_una_vez() -> void:
	MetaState.reset()
	MetaState.bestiary = {"esqueleto_esbirro": {"seen": true, "kills": 3, "first_kill_run": 1, "souls_taken": 0}}
	var r := RunRewards.compute(_kill_snap("retiro"), MetaState)
	eq(int(r.coins.first_kill), 0, "ya estaba en el bestiario")
	eq((r.new_species as Array).size(), 0, "nada nuevo")

func test_sala_de_pruebas_no_deja_nada() -> void:
	MetaState.reset()
	var s := _kill_snap("retiro")
	s["test_room"] = true
	s["max_floor"] = 5
	var r := RunRewards.compute(s, MetaState)
	eq(int(r.coins.total), 0, "sin monedas")
	eq((r.new_unlocks as Array).size(), 0, "sin desbloqueos")

func test_aplicar_resultado() -> void:
	MetaState.reset()
	MetaState.coins = 7
	var r := RunRewards.compute(_kill_snap("muerte"), MetaState)
	MetaState.apply_run_result(r)
	eq(MetaState.coins, 32, "7 + 25")
	eq(int(MetaState.stats.runs), 1, "una run")
	eq(int(MetaState.stats.deaths), 1, "una muerte")
	eq(int(MetaState.bestiary_entry("esqueleto_esbirro").kills), 2, "kills en el bestiario")
	eq(int(MetaState.bestiary_entry("esqueleto_esbirro").first_kill_run), 1, "primera kill en la run 1")
	check(bool(MetaState.bestiary_entry("esqueleto_picaro").seen), "vista aunque no se mató")
	eq(int(MetaState.bestiary_entry("esqueleto_picaro").kills), 0, "sin kills")
	eq(int(MetaState.progress.best_floor), 2, "mejor piso")
