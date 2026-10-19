class_name HubScreen
extends Control
## Hub mínimo entre runs: una sola pantalla de menú sobre un fondo PSX (una
## sala con niebla y la cámara girando lento). Sin exploración.
##   Iniciar expedición · Mejoras · Objetos y desbloqueos · Bestiario ·
##   Estadísticas · Opciones · Salir
## A la derecha, el resumen de la última run; arriba, las monedas.

var builder: FloorBuilder
var cam_pivot: Node3D
var container: SubViewportContainer
var coins_label: Label
var last_run_panel: UIPanel
var menu_items: Array = []
var overlay_layer: CanvasLayer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_ui()
	EventBus.settings_changed.connect(_apply_pixelation)
	MetaState.changed.connect(_refresh)
	_refresh()
	UIFocus.grab_first(self)

func _exit_tree() -> void:
	if builder:
		builder.dispose()

func _process(delta: float) -> void:
	if cam_pivot:
		cam_pivot.rotation.y += delta * 0.12

# --- Fondo 3D -----------------------------------------------------------------------

func _build_background() -> void:
	container = SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var vp := SubViewport.new()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	builder = FloorBuilder.new(world)
	var fd := FloorGenerator.test_room()
	builder.build_blocks(fd)
	builder.build_pillars(fd)
	builder.build_props(fd)
	builder.build_lighting(6.0, 18.0)
	# Un par de "trofeos" quietos: lo que espera abajo.
	for e: Dictionary in fd.enemies.slice(0, 3):
		builder.spawn_enemy(e)
	cam_pivot = Node3D.new()
	cam_pivot.position = FloorBuilder.cell_to_world(Vector2i(7, 4), 1.1)
	world.add_child(cam_pivot)
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 70.0
	cam.position = Vector3(0, 0.3, 3.5)
	cam.rotation_degrees.x = -6.0
	cam_pivot.add_child(cam)
	container.resized.connect(_apply_pixelation)
	_apply_pixelation()

func _apply_pixelation() -> void:
	var shrink := 1
	if bool(MetaState.settings.get("pixelated", true)) and container.size.y > 0:
		shrink = maxi(1, roundi(container.size.y / float(DataRegistry.bal_i("render.low_res_height", 180))))
	container.stretch_shrink = shrink

# --- UI ---------------------------------------------------------------------------------

func _build_ui() -> void:
	var shade := PanelContainer.new()
	shade.theme_type_variation = "DimOverlay"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.modulate.a = 0.55
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	# Desplazable (siguiendo al foco) por si la escala de UI no deja entrar todo.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UIStyle.MARGIN_SCREEN * 2)
	scroll.add_child(margin)
	var cols := HBoxContainer.new()
	margin.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	cols.add_child(left)
	var title := Label.new()
	title.theme_type_variation = "HeroLabel"
	title.text = DataRegistry.t("app.title")
	left.add_child(title)
	var subtitle := Label.new()
	subtitle.theme_type_variation = "DimLabel"
	subtitle.text = DataRegistry.t("app.subtitle")
	left.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size.y = UIStyle.SPACE * 8
	left.add_child(gap)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 0)
	menu.custom_minimum_size.x = 380
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(menu)
	menu_items = [
		UIMenuItem.make_item(DataRegistry.t("hub.start"), _start_run),
		UIMenuItem.make_item(DataRegistry.t("hub.upgrades"), func() -> void: _open(UpgradesScreen.new())),
		UIMenuItem.make_item(DataRegistry.t("hub.unlocks"), func() -> void: _open(UnlocksScreen.new())),
		UIMenuItem.make_item(DataRegistry.t("hub.bestiary"), func() -> void: _open(BestiaryScreen.new())),
		UIMenuItem.make_item(DataRegistry.t("hub.stats"), func() -> void: _open(StatsScreen.new())),
		UIMenuItem.make_item(DataRegistry.t("hub.options"), func() -> void: _open(OptionsScreen.new(true))),
		UIMenuItem.make_item(DataRegistry.t("hub.quit"), func() -> void: get_tree().quit()),
	]
	for it: Control in menu_items:
		menu.add_child(it)
	UIFocus.chain_vertical(menu_items)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	var hint := Label.new()
	hint.theme_type_variation = "DetailLabel"
	hint.text = DataRegistry.t("hub.hint")
	left.add_child(hint)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 340
	right.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	cols.add_child(right)
	coins_label = Label.new()
	coins_label.theme_type_variation = "CoinLabel"
	coins_label.add_theme_font_size_override("font_size", UIStyle.FONT_TITLE)
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(coins_label)
	last_run_panel = UIPanel.new(DataRegistry.t("hub.last_run"), "HudPanel")
	right.add_child(last_run_panel)

	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 20
	add_child(overlay_layer)

func _refresh() -> void:
	coins_label.text = UIFormat.coins(MetaState.coins)
	for c in last_run_panel.body.get_children():
		c.queue_free()
	var last: Dictionary = MetaState.stats.get("last_run", {})
	if last.is_empty():
		_line(last_run_panel.body, DataRegistry.t("hub.no_runs"), "DimLabel")
		return
	_line(last_run_panel.body, DataRegistry.t("outcome." + String(last.get("outcome", "muerte"))), "AccentLabel" if last.get("outcome") != "muerte" else "DangerLabel")
	_line(last_run_panel.body, DataRegistry.t("hub.last_floor_kills", [int(last.get("floor", 1)), int(last.get("kills", 0))]), "")
	if String(last.get("cause", "")) != "":
		_line(last_run_panel.body, DataRegistry.t("hub.last_cause", [last.cause]), "DimLabel")
	_line(last_run_panel.body, "+" + UIFormat.coins(int(last.get("coins", 0))), "CoinLabel")
	_line(last_run_panel.body, DataRegistry.t("hub.last_time", [UIFormat.time(float(last.get("time_sec", 0)))]), "DetailLabel")

func _line(parent: Container, text: String, variation: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != "":
		l.theme_type_variation = variation
	parent.add_child(l)

func _open(screen: UIScreen) -> void:
	var previous := get_viewport().gui_get_focus_owner()
	overlay_layer.add_child(screen)
	screen.closed.connect(func() -> void:
		_refresh()
		if is_instance_valid(previous):
			previous.grab_focus()
		else:
			UIFocus.grab_first(self)
	)

func _start_run() -> void:
	GameState.new_run(DebugTools.fixed_seed if DebugTools.fixed_seed >= 0 else randi(), false)
	SceneRouter.goto(SceneRouter.RUN)
