class_name HubScreen
extends Control
## Hub mínimo entre runs, como portada del grimorio: logo gótico, lema, menú
## con cursor de llama sobre un fondo PSX (una sala con niebla y la cámara
## girando lento) con viñeta de trama. Sin exploración.
##   Iniciar expedición · Mejoras · Objetos y desbloqueos · Bestiario ·
##   Estadísticas · Opciones · Salir
## A la derecha, el resumen de la última run; arriba, las monedas.

var builder: FloorBuilder
var cam_pivot: Node3D
var container: RetroView
var coins_plate: UICoinPlate
var logo: TextureRect
var last_run_panel: PanelContainer
var last_run_box: VBoxContainer
var menu_items: Array = []
var overlay_layer: CanvasLayer

## Ícono y rampa de cada desenlace en el panel "Última expedición".
const OUTCOME_ICONS := {
	"muerte": ["muerte", "sangre"], "retiro": ["retiro", "bronce"],
	"victoria": ["victoria", "moneda"], "abandono": ["retiro", "sangre"],
}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_ui()
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
	container = RetroView.new()
	add_child(container)
	var world := container.world
	builder = FloorBuilder.new(world)
	var fd := FloorGenerator.test_room()
	builder.build_blocks(fd)
	builder.build_pillars(fd)
	builder.build_props(fd)
	builder.build_lighting()
	builder.build_torches(fd)
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

# --- UI ---------------------------------------------------------------------------------

## Íconos del menú (game-icons.net, ver tools/ui/src/icons.json).
const MENU := [
	["hub.start", "iniciar"], ["hub.heroes", "estado"], ["hub.upgrades", "mejoras"], ["hub.unlocks", "desbloqueos"],
	["hub.bestiary", "bestiario"], ["hub.stats", "estadisticas"], ["hub.options", "opciones"],
	["hub.quit", "salir"],
]

func _build_ui() -> void:
	# Velo general + viñeta con trama (más tapado a la izquierda y abajo, detrás del menú).
	var shade := PanelContainer.new()
	shade.theme_type_variation = "DimOverlay"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.modulate.a = 0.35
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(SceneRouter.DITHER_SHADER)
	mat.set_shader_parameter("color", UIStyle.BG_DEEP)
	mat.set_shader_parameter("mode", 1)
	mat.set_shader_parameter("progress", 1.0)
	mat.set_shader_parameter("cell_px", float(UIStyle.PIXEL_SCALE))
	vignette.material = mat
	add_child(vignette)

	# Desplazable (siguiendo al foco) por si la escala de UI no deja entrar todo.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 20)
	scroll.add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 32)
	margin.add_child(cols)

	# Izquierda: logo, lema, filete, menú y pistas.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	logo = TextureRect.new()
	logo.texture = UIIcon.kit_texture("logo")
	logo.stretch_mode = TextureRect.STRETCH_KEEP
	logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(logo)
	var motto := UIGothicLabel.new(DataRegistry.t("app.subtitle"), "GothicQuote", UIStyle.TEXT_DIM, UIStyle.TEXT_DIM)
	motto.custom_minimum_size.x = 400
	left.add_child(motto)
	var rule := UIDivider.new(400)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(rule)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 4)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(menu)
	var actions: Array[Callable] = [
		_start_run,
		func() -> void: _open(HeroesScreen.new()),
		func() -> void: _open(UpgradesScreen.new()),
		func() -> void: _open(UnlocksScreen.new()),
		func() -> void: _open(BestiaryScreen.new()),
		func() -> void: _open(StatsScreen.new()),
		func() -> void: _open(OptionsScreen.new(true)),
		func() -> void: get_tree().quit(),
	]
	menu_items.clear()
	for i in MENU.size():
		var entry: Array = MENU[i]
		var item := UIMenuItem.make_item(DataRegistry.t(String(entry[0])), actions[i], String(entry[1]))
		menu.add_child(item)
		menu_items.append(item)
	UIFocus.chain_vertical(menu_items)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	var hint := PanelContainer.new()
	hint.theme_type_variation = "RibbonSmall"
	hint.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hint.add_child(UILabel.make(DataRegistry.t("hub.hint"), "DetailLabel"))
	left.add_child(hint)

	# Derecha: monedas y la última expedición.
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 440
	right.add_theme_constant_override("separation", 16)
	cols.add_child(right)
	coins_plate = UICoinPlate.new(true)
	right.add_child(coins_plate)
	last_run_panel = PanelContainer.new()
	right.add_child(last_run_panel)
	last_run_box = VBoxContainer.new()
	last_run_box.add_theme_constant_override("separation", 8)
	last_run_panel.add_child(last_run_box)

	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 20
	add_child(overlay_layer)
	_animate_entry()

## Entrada por pasos: el logo aparece en tres tiempos y después los ítems,
## uno cada 40 ms (sin fundidos suaves).
func _animate_entry() -> void:
	logo.modulate.a = 0.0
	for it: Control in menu_items:
		it.modulate.a = 0.0
	var tw := create_tween()
	for a: float in [0.33, 0.66, 1.0]:
		var alpha := a
		tw.tween_callback(func() -> void: logo.modulate.a = alpha)
		tw.tween_interval(0.066)
	for it: Control in menu_items:
		var item := it
		tw.tween_callback(func() -> void: item.modulate.a = 1.0)
		tw.tween_interval(0.04)

func _refresh() -> void:
	coins_plate.set_amount(MetaState.coins)
	for c in last_run_box.get_children():
		c.queue_free()
	var head := UILabel.make(DataRegistry.t("hub.last_run"), "HeadLabel")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	last_run_box.add_child(head)
	var rule := UIDivider.new(300)
	last_run_box.add_child(rule)
	var last: Dictionary = MetaState.stats.get("last_run", {})
	if last.is_empty():
		last_run_box.add_child(UILabel.make(DataRegistry.t("hub.no_runs"), "DimLabel", true))
		return
	var outcome := String(last.get("outcome", "muerte"))
	var cause_row := HBoxContainer.new()
	last_run_box.add_child(cause_row)
	var icon_ramp: Array = OUTCOME_ICONS.get(outcome, ["retiro", "bronce"])
	cause_row.add_child(UIIcon.make(String(icon_ramp[0]), String(icon_ramp[1])))
	var verdict := UILabel.make(DataRegistry.t("outcome." + outcome), "DangerLabel" if outcome == "muerte" else ("AccentLabel" if outcome == "victoria" else "DimLabel"))
	verdict.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cause_row.add_child(verdict)
	last_run_box.add_child(UILabel.make(DataRegistry.t("hub.last_floor_kills", [int(last.get("floor", 1)), int(last.get("kills", 0))])))
	if String(last.get("cause", "")) != "":
		last_run_box.add_child(UILabel.make(DataRegistry.t("hub.last_cause", [last.cause]), "DimLabel", true))
	var money := HBoxContainer.new()
	money.add_theme_constant_override("separation", 8)
	last_run_box.add_child(money)
	money.add_child(UIIcon.make("monedas", "moneda"))
	var coins := UILabel.make("+" + UIFormat.number(int(last.get("coins", 0))), "CoinLabel")
	coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coins.custom_minimum_size.x = 96
	money.add_child(coins)
	money.add_child(UIIcon.make("tiempo", "bronce"))
	var time := UILabel.make(UIFormat.time(float(last.get("time_sec", 0))), "NumSmallLabel")
	time.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	money.add_child(time)
	var floors := DataRegistry.bal_i("floors_per_run", 5)
	var reached := clampi(int(last.get("floor", 1)), 1, floors)
	var depth := HBoxContainer.new()
	depth.add_theme_constant_override("separation", 12)
	last_run_box.add_child(depth)
	depth.add_child(UIPips.new(reached, floors))
	var depth_label := UILabel.make(DataRegistry.t("hub.last_floor_of", [UIFormat.roman(reached), UIFormat.roman(floors)]).to_upper(), "NumSmallLabel")
	depth_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	depth.add_child(depth_label)

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
