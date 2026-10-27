extends Node
## Smoke test de punta a punta (headless):
##   godot --headless --path . res://tests/SmokeTest.tscn
## Boot → Hub → iniciar run (semilla fija) → combate ganado con alma →
## EXP, objeto usado desde el inventario, puntos repartidos en Atributos →
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

	await _check_heroes()

	# --- Run 1: combate ganado con alma, jefe, piso 2, muerte ---
	(get_tree().current_scene as HubScreen).call("_start_run")
	if not await _wait_scene(SceneRouter.RUN):
		_finish()
		return
	var run := get_tree().current_scene as RunController
	check(GameState.active and GameState.floor_n == 1, "la run empieza en el piso 1")
	check(String(GameState.get_member("bjorn").name) == "Bjornar", "la run usa el nombre elegido en Héroes")
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

	# Un combate jugado de verdad: atacar turno a turno hasta que termine.
	DebugTools.god_mode = true
	run.debug_fight_nearest()
	await _wait_frames(3)
	check(run.combat != null, "combate jugado")
	if run.combat != null:
		combat = run.combat
		var kills_before := GameState.kills_total
		var used_ability := false
		for turn in 400:
			if bool(combat.get("finished")):
				break
			if not bool(combat.get("busy")):
				# La activa del alma recién tomada (con su recarga); si no, atacar.
				var core: CombatCore = combat.get("core")
				if not used_ability and core.soul_count() > 0 and core.ability_ready(0):
					combat.call("_show_abilities")
					combat.call("_on_ability", 0)
					used_ability = true
					check(not core.ability_ready(0), "usar la activa la deja recargando")
				else:
					combat.call("_on_attack")
			await _wait_frames(2)
		check(used_ability, "en combate se usa la activa del alma")
		check(bool(combat.get("finished")), "el combate termina atacando")
		check((combat.get("core") as CombatCore).enemy_dead(), "el enemigo cae")
		combat.call("_after_victory_summary")
		await _wait_frames(2)
		if run.combat != null:
			# soltó alma: dejarla
			run.combat.emit_signal("combat_ended", "victory", run.combat.call("_result"))
			await _wait_frames(2)
		check(GameState.kills_total == kills_before + 1, "kill del combate jugado")
	DebugTools.god_mode = false
	check(int(GameState.get_member("bjorn").xp) > 0 or int(GameState.get_member("bjorn").level) > 1, "las kills dan EXP")

	await _check_field_items(run)
	await _check_attributes()

	# Caminar: los enemigos reaccionan y nada se rompe.
	for step in 6:
		var p: Node3D = run.player
		if not bool(p.get("input_locked")) and run.combat == null:
			p.call("_try_move", 1)
			p.call("_turn", 1)
		await _wait_frames(25)
	if run.combat != null:
		run.combat.call("debug_win")
		await _wait_frames(2)
		run.combat.emit_signal("combat_ended", "victory", run.combat.call("_result"))
		await _wait_frames(2)

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
	await _check_boss_intro(run)
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

## Héroes (Hub): cambiar el nombre y una parte se guarda al instante y
## cambia el retrato.
func _check_heroes() -> void:
	var before := HeroPortrait.for_member("bjorn", 48).get_image().get_data()
	var screen := HeroesScreen.new()
	get_tree().root.add_child(screen)
	await _wait_frames(2)
	var ed: Dictionary = screen.call("_editor_of", "bjorn")
	var name_edit: LineEdit = ed.name
	name_edit.text = "Bjornar"
	name_edit.text_changed.emit(name_edit.text)
	var sel: UISelector = (ed.selectors as Dictionary)["color_pelo"]
	sel.set_index(sel.index + 1)
	await _wait_frames(2)
	check(MetaState.hero_name("bjorn") == "Bjornar", "Héroes guarda el nombre")
	check(int(MetaState.hero_look("bjorn").color_pelo) == sel.index, "Héroes guarda la apariencia")
	check(HeroPortrait.for_member("bjorn", 48).get_image().get_data() != before, "el retrato cambia con la apariencia")
	screen.close()
	await _wait_frames(2)

## Sala del jefe: la puerta está cerrada y bloquea; chocarla la abre;
## entrar dispara la presentación (portazo, braseros, el jefe que se levanta
## y se acerca por la alfombra) y termina en un combate con entrada de jefe;
## al ganarlo se abre la puerta y la salida.
func _check_boss_intro(run: RunController) -> void:
	var boss: Dictionary = run.call("_boss")
	check(bool(boss.get("dormant", false)), "el jefe duerme hasta su presentación")
	var door := run.fd.boss_door
	var inward: Vector2i = FloorGenerator.DIRS[run.fd.boss_door_dir]
	check(run.is_wall(door), "la puerta del jefe empieza cerrada")
	run.player.call("teleport", door - inward, run.fd.boss_door_dir)
	run.player.call("_try_move", 1)
	await _wait_frames(2)
	check(not run.is_wall(door), "chocar la puerta la abre")
	var cell := door + inward
	run.player.call("teleport", cell, run.fd.boss_door_dir)
	Engine.time_scale = 8.0
	run.call("_on_player_moved", cell)
	check(bool(run.get("_intro_running")), "entrar a la sala dispara la presentación")
	for i in TIMEOUT_FRAMES:
		if run.combat != null:
			break
		await get_tree().process_frame
	Engine.time_scale = 1.0
	check(run.combat != null, "la presentación termina en combate")
	if run.combat == null:
		run.debug_kill_boss()
		return
	check(String(run.combat.get("start_mode")) == "boss", "combate con entrada de jefe")
	check(not bool(boss.get("dormant", true)), "el jefe se levantó")
	var bc: Vector2i = boss.cell
	var pc: Vector2i = run.player.get("grid_pos")
	eq_cell(bc, pc + inward, "el jefe llegó por la alfombra hasta quedar enfrente")
	for f: BrazierFire in run.boss_room.braziers:
		check(f.is_lit(), "los braseros quedan encendidos")
	check(run.is_wall(door), "la puerta se cerró detrás del equipo")
	await _wait_frames(30)
	var combat := run.combat
	var options: Array = combat.get("soul_options")
	check(options.size() == DataRegistry.bal_i("almas.opciones_jefe", 3), "el jefe deja elegir entre %d almas" % options.size())
	var souls_before := (GameState.hero().souls as Array).size()
	combat.call("debug_win")
	await _wait_frames(2)
	# Resumen → Continuar → elección: la primera «Elegir» se la lleva.
	combat.call("_after_victory_summary")
	await _wait_frames(2)
	var pick: UIButton = null
	for b: Node in combat.find_children("*", "UIButton", true, false):
		if (b as UIButton).text == DataRegistry.t("combat.soul_pick"):
			pick = b
			break
	check(pick != null, "la elección del jefe muestra «Elegir»")
	if pick != null:
		pick.emit_signal("pressed")
	else:
		combat.emit_signal("combat_ended", "victory", combat.call("_result"))
	await _wait_frames(2)
	var after := GameState.hero().souls as Array
	check(after.size() == souls_before + 1 and options.any(func(o: Dictionary) -> bool: return String(o.id) == String((after.back() as Dictionary).id)), "se lleva el alma elegida")
	check(not run.is_wall(door), "vencer al jefe abre la puerta")
	check(run.exit_open, "vencer al jefe abre la salida")

func eq_cell(a: Vector2i, b: Vector2i, msg: String) -> void:
	check(a == b, "%s (%s, esperado %s)" % [msg, a, b])

## Inventario fuera de combate: Enter sobre la casilla usa el objeto en el
## héroe, cura y se gasta. Con el HP completo no se gasta.
func _check_field_items(run: RunController) -> void:
	var hero := GameState.hero()
	GameState.inventory.clear()
	GameState.inventory.append("pocion_menor")
	hero["hp"] = 1
	var inv := InventoryScreen.new(run)
	run.add_child(inv)
	await _wait_frames(2)
	var slot := inv.grid.get_child(0) as UIItemSlot
	slot.emit_signal("pressed")
	await _wait_frames(2)
	check(int(hero.hp) > 1, "la poción cura fuera de combate")
	check(GameState.inventory.is_empty(), "la poción se gasta")
	hero["hp"] = GameState.member_max_hp(hero)
	GameState.inventory.append("venda")
	var used: bool = await run.use_item_field(0, inv)
	check(not used and GameState.inventory.size() == 1, "sano, la venda no se gasta")
	GameState.inventory.clear()
	inv.queue_free()
	await _wait_frames(1)

## Estado → Atributos: repartir un punto, confirmar, y al cerrar con algo
## pendiente se pregunta y se aplica.
func _check_attributes() -> void:
	var bjorn := GameState.get_member("bjorn")
	GameState.add_xp(RunRules.xp_to_next(int(bjorn.level)))
	var points := int(bjorn.points)
	var vit := GameState.member_stat(bjorn, "vit")
	check(points >= 3, "subir de nivel da puntos")
	var status := StatusScreen.new()
	get_tree().root.add_child(status)
	await _wait_frames(2)
	var attr := status.attributes
	attr.call("_select", 0)
	attr.call("_change", "vit", 1)
	attr.call("_confirm")
	check(GameState.member_stat(bjorn, "vit") == vit + 1 and int(bjorn.points) == points - 1, "confirmar aplica el punto")
	attr.call("_change", "agi", 1)
	check(attr.has_pending(), "queda un punto pendiente")
	status.close()
	await _wait_frames(2)
	var dialog: UIConfirmDialog = null
	for c in status.get_children():
		if c is UIConfirmDialog:
			dialog = c
	check(dialog != null, "cerrar con puntos pendientes pregunta")
	if dialog != null:
		dialog.call("_answer", true)
		await _wait_frames(2)
		check(GameState.member_stat(bjorn, "agi") == 1, "al cerrar se aplica lo pendiente")
	if is_instance_valid(status):
		status.queue_free()
	await _wait_frames(1)

func _open_all_screens() -> void:
	var screens: Array = [
		HeroesScreen.new(), UpgradesScreen.new(), UnlocksScreen.new(), BestiaryScreen.new(), StatsScreen.new(),
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
	Engine.time_scale = 1.0
	SaveSystem.reset_save()
	SaveSystem.save_path = SaveSystem.DEFAULT_PATH
	if failures.is_empty():
		print("smoke: OK")
	else:
		print("smoke: %d fallos" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
