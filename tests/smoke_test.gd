extends Node
## Smoke test de punta a punta (headless):
##   godot --headless --path . res://tests/SmokeTest.tscn
## Boot → Hub → iniciar run (semilla fija) → combate ganado con alma →
## jefe → bajar al piso 2 → muerte → resumen → Hub; después una run con
## retiro tras el jefe (conserva el 100%), y abre TODAS las pantallas de UI.
## Usa un guardado aparte (user://smoke_save.json). Sale con 0 si todo pasó.

const SEED := 4242
const TIMEOUT_FRAMES := 600

var failures: Array[String] = []

func _ready() -> void:
	# El runner tiene que sobrevivir a los cambios de escena: se cuelga de root.
	var runner := Node.new()
	runner.name = "SmokeRunner"
	runner.set_script(get_script())
	runner.set_meta("is_runner", true)
	if has_meta("is_runner"):
		runner.free()
		get_tree().create_timer(240.0).timeout.connect(func() -> void:
			printerr("TEST FAIL: smoke test colgado (timeout)")
			get_tree().quit(1)
		)
		_run.call_deferred()
	else:
		get_tree().root.add_child.call_deferred(runner)

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		printerr("TEST FAIL: smoke: ", msg)

func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## Espera hasta que la escena actual sea `path` (y SceneRouter terminó).
func _wait_scene(path: String) -> bool:
	for i in TIMEOUT_FRAMES:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs != null and cs.scene_file_path == path and not SceneRouter.busy:
			return true
	check(false, "nunca se llegó a " + path)
	return false

func _run() -> void:
	SaveSystem.save_path = "user://smoke_save.json"
	SaveSystem.reset_save()
	DebugTools.fixed_seed = SEED

	get_tree().change_scene_to_file(SceneRouter.BOOT)
	if not await _wait_scene(SceneRouter.HUB):
		_finish()
		return

	# --- Run 1: combate ganado con alma, jefe, piso 2, muerte ---
	(get_tree().current_scene as HubScreen).call("_start_run")
	if not await _wait_scene(SceneRouter.RUN):
		_finish()
		return
	var run := get_tree().current_scene as RunController
	check(GameState.active and GameState.floor_n == 1, "la run empieza en el piso 1")
	check(GameState.run_seed == SEED, "usa la semilla fija")
	check(run.fd.enemies.size() > 1, "hay enemigos en el piso")
	check(run.fd.exit_cell.x >= 0, "hay salida")
	var first_cells := run.fd.floor_cells().size()

	DebugTools.force_soul_drop = true
	run.debug_fight_nearest()
	await _wait_frames(3)
	check(run.combat != null, "empieza un combate")
	if run.combat == null:
		_finish()
		return
	var combat := run.combat
	combat.call("debug_win")
	await _wait_frames(2)
	var soul: Dictionary = combat.get("soul_drop")
	check(not soul.is_empty(), "con force_soul_drop el enemigo suelta alma")
	var result: Dictionary = combat.call("_result", {"member_id": "bjorn", "soul": soul, "replace_index": -1})
	combat.emit_signal("combat_ended", "victory", result)
	await _wait_frames(2)
	DebugTools.force_soul_drop = false
	check(run.combat == null, "el combate se cierra")
	check(GameState.kills_total == 1, "se cuenta la kill")
	check((GameState.get_member("bjorn").souls as Array).size() == 1, "Bjorn recibe el alma")
	check(GameState.run_coins() > 0, "la kill da monedas")

	run.debug_kill_boss()
	check(run.exit_open, "matar al jefe abre la salida")
	run.advance_floor()
	if not await _wait_scene(SceneRouter.RUN):
		_finish()
		return
	run = get_tree().current_scene as RunController
	check(GameState.floor_n == 2, "bajar lleva al piso 2")
	check(run.fd.floor_cells().size() > first_cells, "el piso 2 es más grande")
	check((GameState.get_member("bjorn").souls as Array).size() == 1, "el alma sigue durante la run")

	run.debug_fight_nearest()
	await _wait_frames(3)
	check(run.combat != null, "segundo combate")
	if run.combat == null:
		_finish()
		return
	combat = run.combat
	combat.call("debug_lose")
	await _wait_frames(2)
	combat.emit_signal("combat_ended", "defeat", combat.call("_result"))
	if not await _wait_scene(SceneRouter.SUMMARY):
		_finish()
		return
	await _wait_frames(3)
	check(not GameState.active, "la run terminó")
	check(GameState.result_applied, "el resultado se aplicó")
	check(int(MetaState.stats.runs) == 1 and int(MetaState.stats.deaths) == 1, "estadísticas: 1 run, 1 muerte")
	check(MetaState.coins > 0, "al morir se conserva parte de las monedas")
	var res: Dictionary = GameState.last_result
	check(int(res.coins.total) == floori(float(res.coins.gross) * 0.5), "al morir se conserva el 50%")
	check(FileAccess.file_exists(SaveSystem.save_path), "se autoguardó")
	var coins_after := MetaState.coins
	var summary := get_tree().current_scene
	var btn: UIButton = summary.get("continue_btn")
	btn.emit_signal("pressed")
	if not bool(summary.get("revealed")):
		btn.emit_signal("pressed")
	await _wait_frames(1)
	if btn and is_instance_valid(btn):
		btn.emit_signal("pressed")
	if not await _wait_scene(SceneRouter.HUB):
		_finish()
		return
	MetaState.reset()
	SaveSystem.load_meta()
	check(MetaState.coins == coins_after, "las monedas persisten al recargar el guardado")
	check(MetaState.has_killed(String(GameState.kills_by_species.keys()[0])) if not GameState.kills_by_species.is_empty() else false, "el bestiario recuerda la kill")

	# --- Run 2: retiro tras el jefe del piso 1 conserva el 100% ---
	(get_tree().current_scene as HubScreen).call("_start_run")
	if not await _wait_scene(SceneRouter.RUN):
		_finish()
		return
	run = get_tree().current_scene as RunController
	run.debug_kill_boss()
	var gross_before := GameState.run_coins()
	run.end_run("retiro")
	if not await _wait_scene(SceneRouter.SUMMARY):
		_finish()
		return
	await _wait_frames(2)
	res = GameState.last_result
	check(String(res.outcome) == "retiro", "resultado: retiro")
	check(float(res.coins.keep_fraction) == 1.0 and int(res.coins.lost) == 0, "el retiro conserva el 100%")
	check(int(res.coins.kills) + int(res.coins.boss) + int(res.coins.chests) == gross_before, "monedas de la run desglosadas")

	# --- Todas las pantallas de UI se abren sin errores ---
	await _open_all_screens()
	_finish()

func _open_all_screens() -> void:
	var screens: Array = [
		UpgradesScreen.new(), UnlocksScreen.new(), BestiaryScreen.new(), StatsScreen.new(),
		OptionsScreen.new(true), OptionsScreen.new(false), StatusScreen.new(),
		InventoryScreen.new(null), PauseMenu.new(null),
	]
	for s: Node in screens:
		get_tree().root.add_child(s)
		await _wait_frames(2)
		s.queue_free()
	for path: String in [SceneRouter.HUB, SceneRouter.UI_GALLERY]:
		var inst := (load(path) as PackedScene).instantiate()
		get_tree().root.add_child(inst)
		await _wait_frames(2)
		inst.queue_free()
	await _wait_frames(2)

func _finish() -> void:
	SaveSystem.reset_save()
	SaveSystem.save_path = SaveSystem.DEFAULT_PATH
	if failures.is_empty():
		print("smoke: OK")
	else:
		print("smoke: %d fallos" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
