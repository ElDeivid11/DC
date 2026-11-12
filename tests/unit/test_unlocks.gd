extends TestCase
## UnlockEvaluator: progreso acumulado y condiciones de data/unlocks.json.

func test_esqueletos_acumulados_entre_runs() -> void:
	var u := DataRegistry.get_unlock("u_esqueletos")
	var meta_progress := {"kills_by_species": {"esqueleto_esbirro": 8, "esqueleto_picaro": 4, "nigromante": 5}}
	eq(UnlockEvaluator.progress_of(u, meta_progress), Vector2i(12, 15), "progreso 12/15 (el jefe no cuenta)")
	check(not UnlockEvaluator.is_met(u, meta_progress), "todavía no")
	var after := UnlockEvaluator.merged_progress(meta_progress, snap({"kills_by_species": {"esqueleto_guardian": 3}}), 0)
	check(UnlockEvaluator.is_met(u, after), "12 + 3 = 15")

func test_llegar_al_piso_3() -> void:
	var after := UnlockEvaluator.merged_progress(MetaState.default_progress(), snap({"max_floor": 3}), 0)
	var got := UnlockEvaluator.evaluate(DataRegistry.unlocks, after, snap({"max_floor": 3}), {})
	check(got.has("u_piso_3"), "desbloquea el Sello de Retiro: %s" % [got])

func test_sin_usar_pociones() -> void:
	var u := DataRegistry.get_unlock("u_sin_pociones")
	var p := MetaState.default_progress()
	check(UnlockEvaluator.is_met(u, p, snap({"outcome": "retiro"})), "retiro sin pociones")
	check(not UnlockEvaluator.is_met(u, p, snap({"outcome": "retiro", "items_used": {"pocion_menor": 1}})), "usó una")
	check(not UnlockEvaluator.is_met(u, p, snap({"outcome": "muerte"})), "morir no cuenta")

func test_huidas_acumuladas() -> void:
	var u := DataRegistry.get_unlock("u_huir_3")
	var p := UnlockEvaluator.merged_progress({"flee_total": 2}, snap({"flee_count": 1}), 0)
	check(UnlockEvaluator.is_met(u, p), "2 + 1 huidas")

func test_no_repite_desbloqueos() -> void:
	var after := UnlockEvaluator.merged_progress(MetaState.default_progress(), snap({"max_floor": 4}), 0)
	var got := UnlockEvaluator.evaluate(DataRegistry.unlocks, after, snap(), {"u_piso_3": true})
	check(not got.has("u_piso_3"), "ya estaba desbloqueado")

func test_otros_tipos_de_condicion() -> void:
	var fake := {
		"boss": {"condicion": {"tipo": "defeat_boss", "parametros": {"floor": 2}}},
		"boss_sp": {"condicion": {"tipo": "defeat_boss", "parametros": {"species": "nigromante"}}},
		"win": {"condicion": {"tipo": "win_run", "parametros": {}}},
		"coins": {"condicion": {"tipo": "coins_total", "parametros": {"n": 100}}},
	}
	var s := snap({"outcome": "victoria", "bosses_defeated": [1, 2], "boss_species": ["nigromante"], "max_floor": 5})
	var p := UnlockEvaluator.merged_progress(MetaState.default_progress(), s, 120)
	var got := UnlockEvaluator.evaluate(fake, p, s, {})
	eq(got, ["boss", "boss_sp", "coins", "win"] as Array[String], "todas se cumplen")
	var none := UnlockEvaluator.evaluate(fake, MetaState.default_progress(), snap(), {})
	eq(none.size(), 0, "sin progreso no se cumple ninguna")
