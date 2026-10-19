extends CanvasLayer
## Herramientas de prueba (solo en builds de debug): panel F1 con trucos para
## que David pruebe rápido, flags que leen la run y el combate, y un log de
## todos los eventos del EventBus en user://debug.log.

var force_soul_drop := false
var force_surprise := false
var god_mode := false
var one_hit := false
## Semilla fija para la próxima run (-1 = aleatoria).
var fixed_seed := -1

var _panel: PanelContainer
var _info: Label
var _seed_edit: LineEdit
var _floor_pick: OptionButton
var _log_file: FileAccess

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.is_debug_build():
		return
	_open_log()
	_build_panel()

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or _panel == null:
		return
	if event.is_action_pressed("debug_panel"):
		get_viewport().set_input_as_handled()
		_panel.visible = not _panel.visible
		if _panel.visible:
			_refresh_info()

func _process(_delta: float) -> void:
	if _panel and _panel.visible and Engine.get_process_frames() % 15 == 0:
		_refresh_info()

# --- Panel -----------------------------------------------------------------------------

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.position = Vector2(UIStyle.MARGIN_SCREEN, UIStyle.MARGIN_SCREEN * 4)
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", UIStyle.SPACE)
	scroll.add_child(box)

	var title := Label.new()
	title.theme_type_variation = "SubtitleLabel"
	title.text = DataRegistry.t("debug.title")
	box.add_child(title)
	_info = Label.new()
	_info.theme_type_variation = "DetailLabel"
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	box.add_child(HSeparator.new())

	_row(box, [
		[DataRegistry.t("debug.coins_100"), func() -> void: _coins(100)],
		[DataRegistry.t("debug.coins_1000"), func() -> void: _coins(1000)],
	])
	_row(box, [
		[DataRegistry.t("debug.upgrades_up"), func() -> void: _upgrades(1)],
		[DataRegistry.t("debug.upgrades_down"), func() -> void: _upgrades(-1)],
	])
	_row(box, [
		[DataRegistry.t("debug.unlock_all"), func() -> void: _unlocks(true)],
		[DataRegistry.t("debug.lock_all"), func() -> void: _unlocks(false)],
	])
	box.add_child(HSeparator.new())

	var floor_row := HBoxContainer.new()
	box.add_child(floor_row)
	_floor_pick = OptionButton.new()
	for n in range(1, DataRegistry.bal_i("floors_per_run", 5) + 1):
		_floor_pick.add_item(DataRegistry.t("hud.floor_short", [n]), n)
	floor_row.add_child(_floor_pick)
	floor_row.add_child(UIButton.make(DataRegistry.t("debug.goto_floor"), func() -> void: _run_call("debug_goto_floor", [_floor_pick.get_selected_id()])))
	_row(box, [
		[DataRegistry.t("debug.kill_front"), func() -> void: _run_call("debug_kill_front", [])],
		[DataRegistry.t("debug.kill_boss"), func() -> void: _run_call("debug_kill_boss", [])],
	])
	_row(box, [
		[DataRegistry.t("debug.fight_nearest"), func() -> void: _run_call("debug_fight_nearest", [false])],
		[DataRegistry.t("debug.fight_boss"), func() -> void: _run_call("debug_fight_nearest", [true])],
	])
	_row(box, [
		[DataRegistry.t("debug.heal"), func() -> void: _run_call("debug_heal_party", [])],
		[DataRegistry.t("debug.win_combat"), _win_combat],
	])
	box.add_child(HSeparator.new())

	_check(box, DataRegistry.t("debug.force_soul"), func(on: bool) -> void: force_soul_drop = on)
	_check(box, DataRegistry.t("debug.force_surprise"), func(on: bool) -> void: force_surprise = on)
	_check(box, DataRegistry.t("debug.god_mode"), func(on: bool) -> void: god_mode = on)
	_check(box, DataRegistry.t("debug.one_hit"), func(on: bool) -> void: one_hit = on)
	box.add_child(HSeparator.new())

	var seed_row := HBoxContainer.new()
	box.add_child(seed_row)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = DataRegistry.t("debug.seed_placeholder")
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_edit)
	seed_row.add_child(UIButton.make(DataRegistry.t("debug.set_seed"), _set_seed))
	box.add_child(HSeparator.new())
	_row(box, [
		[DataRegistry.t("options.test_room"), _test_room],
		[DataRegistry.t("gallery.title"), func() -> void: SceneRouter.goto(SceneRouter.UI_GALLERY)],
	])
	box.add_child(UIButton.make(DataRegistry.t("options.reset_save"), _reset_save, "DangerButton"))

func _row(parent: Container, buttons: Array) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	for b: Array in buttons:
		var btn := UIButton.make(String(b[0]), b[1])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(btn)

func _check(parent: Container, text: String, on_toggle: Callable) -> void:
	var c := CheckBox.new()
	c.text = text
	c.toggled.connect(on_toggle)
	parent.add_child(c)

func _refresh_info() -> void:
	var lines: Array[String] = [DataRegistry.t("debug.info_fps", [Engine.get_frames_per_second(), MetaState.coins])]
	if GameState.active:
		var run := get_tree().current_scene
		var cell := Vector2i(-1, -1)
		if run is RunController:
			cell = (run as RunController).player.get("grid_pos")
		lines.append(DataRegistry.t("debug.info_run", [GameState.run_seed, GameState.floor_n, cell.x, cell.y, GameState.run_coins(), GameState.kills_total, GameState.inventory.size()]))
		for m: Dictionary in GameState.party:
			lines.append("%s %d/%d ATK %d ✦%d" % [m.name, m.hp, GameState.member_max_hp(m), GameState.member_atk(m), (m.souls as Array).size()])
	else:
		lines.append(DataRegistry.t("debug.info_no_run"))
	if SaveSystem.last_error != "":
		lines.append(SaveSystem.last_error)
	_info.text = "\n".join(lines)

# --- Acciones ----------------------------------------------------------------------------

func _coins(n: int) -> void:
	MetaState.debug_add_coins(n)
	SaveSystem.save_meta()
	_refresh_info()

func _upgrades(delta: int) -> void:
	MetaState.debug_shift_upgrades(delta)
	SaveSystem.save_meta()

func _unlocks(value: bool) -> void:
	MetaState.debug_set_all_unlocked(value)
	SaveSystem.save_meta()

func _run_call(method: String, args: Array) -> void:
	var run := get_tree().current_scene
	if run is RunController and run.has_method(method):
		run.callv(method, args)
	else:
		UIToast.show(get_tree(), DataRegistry.t("debug.not_in_run"), "danger")

func _win_combat() -> void:
	var run := get_tree().current_scene
	if run is RunController and (run as RunController).combat != null:
		(run as RunController).combat.call("debug_win")

func _set_seed() -> void:
	var txt := _seed_edit.text.strip_edges()
	fixed_seed = int(txt) if txt.is_valid_int() else -1
	UIToast.show(get_tree(), DataRegistry.t("debug.seed_set", [txt if fixed_seed >= 0 else DataRegistry.t("debug.seed_random")]), "info")

func _test_room() -> void:
	_panel.visible = false
	GameState.new_run(randi(), true)
	SceneRouter.goto(SceneRouter.RUN)

func _reset_save() -> void:
	var d := UIConfirmDialog.ask(self, DataRegistry.t("options.reset_title"), DataRegistry.t("options.reset_text"), DataRegistry.t("options.reset_yes"), DataRegistry.t("ui.cancel"), true)
	if await d.answered:
		SaveSystem.reset_save()
		_refresh_info()

# --- Log de eventos -----------------------------------------------------------------------

func _open_log() -> void:
	_log_file = FileAccess.open("user://debug.log", FileAccess.WRITE)
	_log("inicio")
	EventBus.run_started.connect(func(s: int) -> void: _log("run_started seed=%d" % s))
	EventBus.run_ended.connect(func(snap: Dictionary) -> void: _log("run_ended %s piso=%s kills=%s" % [snap.outcome, snap.max_floor, snap.kills_total]))
	EventBus.floor_reached.connect(func(n: int) -> void: _log("floor_reached %d" % n))
	EventBus.combat_started.connect(func(sid: String, boss: bool) -> void: _log("combat_started %s jefe=%s" % [sid, boss]))
	EventBus.enemy_killed.connect(func(sid: String, first: bool) -> void: _log("enemy_killed %s primera=%s" % [sid, first]))
	EventBus.boss_defeated.connect(func(f: int, sid: String) -> void: _log("boss_defeated piso=%d %s" % [f, sid]))
	EventBus.fled_combat.connect(func(ok: bool) -> void: _log("fled_combat %s" % ok))
	EventBus.soul_acquired.connect(func(mid: String, soul: Dictionary) -> void: _log("soul_acquired %s %s" % [mid, soul.get("id", "")]))
	EventBus.item_picked.connect(func(id: String) -> void: _log("item_picked %s" % id))
	EventBus.item_used.connect(func(id: String) -> void: _log("item_used %s" % id))
	EventBus.unlock_earned.connect(func(id: String) -> void: _log("unlock_earned %s" % id))

func _log(text: String) -> void:
	if _log_file:
		_log_file.store_line("[%s] %s" % [Time.get_time_string_from_system(), text])
		_log_file.flush()
