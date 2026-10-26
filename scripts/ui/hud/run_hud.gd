class_name RunHud
extends CanvasLayer
## HUD de exploración «Grimorio de la Cripta» (fuera del SubViewport: nítido a
## resolución nativa). Spec 8.6:
##   sup. izq.: una placa de hierro por héroe (retrato, nombre, nivel, almas,
##              HP, EXP fina y pips de vela si tiene puntos sin repartir)
##   sup. der.: minimapa en su placa + brújula en cinta (N/E/S/O)
##   inf. der.: piso en romanos + bioma, y las monedas de la run
##   inf. izq.: cinta con atajos (se oculta tras 10 s sin tocar nada)
##   inf. centro: mensajes breves y la placa de interacción («[↑] abrir»)
## En debug, bajo la brújula: semilla, celda y FPS.

const HINTS_IDLE := 10.0
const MESSAGE_TIME := 2.4
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## Pips de vela que entran en la placa; el resto se cuenta con "+N".
const MAX_POINT_PIPS := 6
## Separación de las placas al borde de la pantalla.
const EDGE := 16
## Alto fijo de las cintas chicas (ribbon_small: 13 píxeles de arte).
const RIBBON_H := 26

var party_box: VBoxContainer
var plates: Array[HeroPlate] = []
var minimap: UIMinimap
var compass: UICompass
var floor_word: Label
var floor_num: Label
var biome_label: Label
var coins_label: Label
var hints: PanelContainer
var message_panel: PanelContainer
var message_label: Label
var interact_panel: PanelContainer
var interact_key: Control
var interact_label: Label
var debug_label: Label
var _message_tween: Tween
var _idle := 0.0

func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var m := EDGE

	# Equipo (sup. izq.): una placa por héroe.
	party_box = VBoxContainer.new()
	party_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	party_box.add_theme_constant_override("separation", 8)
	party_box.position = Vector2(m, m)
	root.add_child(party_box)
	for member: Dictionary in GameState.party:
		var plate := HeroPlate.new(member)
		party_box.add_child(plate)
		plates.append(plate)

	# Minimapa + brújula (sup. der.), del mismo ancho.
	var right_col := VBoxContainer.new()
	right_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_col.add_theme_constant_override("separation", 6)
	right_col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_col.offset_left = -m
	right_col.offset_right = -m
	right_col.offset_top = m
	root.add_child(right_col)
	var map_panel := PanelContainer.new()
	map_panel.theme_type_variation = "HudPanel"
	map_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_col.add_child(map_panel)
	minimap = UIMinimap.new()
	map_panel.add_child(minimap)
	compass = UICompass.new()
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.custom_minimum_size.x = 0
	right_col.add_child(compass)
	debug_label = UILabel.make("", "DetailLabel")
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_label.visible = OS.is_debug_build()
	right_col.add_child(debug_label)

	# Piso y monedas (inf. der.): «Piso III  CATACUMBAS DEL POZO   ◈ 37».
	var info := PanelContainer.new()
	info.theme_type_variation = "HudPanel"
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info.offset_left = -m
	info.offset_right = -m
	info.offset_top = -m
	info.offset_bottom = -m
	root.add_child(info)
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 8)
	info.add_child(info_row)
	floor_word = UILabel.make(DataRegistry.t("hud.floor_word"), "SubtitleLabel")
	floor_word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_row.add_child(floor_word)
	floor_num = UILabel.make("", "NumLabel")
	floor_num.add_theme_color_override("font_color", UIStyle.ACCENT)
	floor_num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_row.add_child(floor_num)
	biome_label = UILabel.make("", "NumSmallLabel")
	biome_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_row.add_child(biome_label)
	var gap := Control.new()
	gap.custom_minimum_size.x = 16
	info_row.add_child(gap)
	info_row.add_child(UIIcon.make("monedas", "moneda"))
	coins_label = UILabel.make("", "CoinLabel")
	coins_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_row.add_child(coins_label)

	# Atajos (inf. izq.), en una cinta.
	hints = PanelContainer.new()
	hints.theme_type_variation = "RibbonSmall"
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hints.offset_left = m
	hints.offset_top = -m
	hints.offset_bottom = -m
	hints.custom_minimum_size.y = RIBBON_H
	root.add_child(hints)
	var hint_label := UILabel.make(DataRegistry.t("hud.hints"), "DetailLabel")
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hints.add_child(hint_label)

	# Placa de interacción (inf. centro): «[↑] abrir» frente a un cofre, etc.
	interact_panel = PanelContainer.new()
	interact_panel.theme_type_variation = "RibbonSmall"
	interact_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interact_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	interact_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	interact_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	interact_panel.offset_top = -96
	interact_panel.offset_bottom = -96
	interact_panel.custom_minimum_size.y = RIBBON_H
	interact_panel.visible = false
	root.add_child(interact_panel)
	var irow := HBoxContainer.new()
	irow.add_theme_constant_override("separation", 8)
	interact_panel.add_child(irow)
	var cap := PanelContainer.new()
	cap.theme_type_variation = "KeyCap"
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	irow.add_child(cap)
	# «Avanzar» es ↑: se dibuja con la flecha del kit (la del minimapa), que a
	# este tamaño se lee mejor que el glifo de la fuente.
	var key_name := _forward_key()
	if key_name == "↑" and UIIcon.kit_texture("map_player") != null:
		interact_key = UISprite.new("map_player")
	else:
		var key_label := UILabel.make(key_name, "DetailLabel")
		key_label.add_theme_color_override("font_color", UIStyle.TEXT)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		interact_key = key_label
	cap.add_child(interact_key)
	interact_label = UILabel.make("", "DetailLabel")
	interact_label.add_theme_color_override("font_color", UIStyle.TEXT)
	interact_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	irow.add_child(interact_label)

	# Mensajes (inf. centro, sobre la placa de interacción).
	message_panel = PanelContainer.new()
	message_panel.theme_type_variation = "HudPanel"
	message_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	message_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	message_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	message_panel.offset_top = -136
	message_panel.offset_bottom = -136
	message_panel.visible = false
	root.add_child(message_panel)
	message_label = UILabel.make("")
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_panel.add_child(message_label)

	EventBus.hud_message.connect(show_message)
	EventBus.coins_changed.connect(func(_c: int) -> void: refresh())
	get_viewport().size_changed.connect(_fit_message)

func refresh() -> void:
	for i in mini(plates.size(), GameState.party.size()):
		plates[i].refresh(GameState.party[i])
	if GameState.test_room:
		floor_word.text = DataRegistry.t("hud.test_room")
		floor_num.visible = false
		biome_label.visible = false
	else:
		floor_word.text = DataRegistry.t("hud.floor_word")
		floor_num.visible = true
		floor_num.text = UIFormat.roman(GameState.floor_n)
		biome_label.visible = true
		biome_label.text = String(DataRegistry.get_theme(GameState.floor_n).get("nombre", "")).to_upper()
	coins_label.text = UIFormat.number(GameState.run_coins())

func update_map(fd: FloorData, cell: Vector2i, facing: int, markers: Dictionary) -> void:
	minimap.update_view(fd, GameState.visited, cell, facing, markers)
	compass.set_facing(facing)
	_update_interaction(fd, cell, facing, markers)
	if debug_label.visible:
		debug_label.text = DataRegistry.t("hud.debug", [GameState.run_seed, cell.x, cell.y, Engine.get_frames_per_second()])

## Qué pasa si se avanza: abrir el cofre, recoger, atacar, salir, la salida
## sellada o abrir la puerta del jefe.
func _update_interaction(fd: FloorData, cell: Vector2i, facing: int, markers: Dictionary) -> void:
	var front: Vector2i = cell + DIRS[posmod(facing, 4)]
	var key := ""
	match String(markers.get(front, "")):
		"chest":
			key = "hud.act_open"
		"item":
			key = "hud.act_pick"
		"enemy", "boss":
			key = "hud.act_fight"
		"exit_open":
			key = "hud.act_descend"
		"exit":
			key = "hud.act_sealed"
		"door":
			key = "hud.act_door"
	if key == "" and not fd.enemy_at(front).is_empty():
		key = "hud.act_fight"
	interact_panel.visible = key != ""
	if key != "":
		interact_label.text = DataRegistry.t(key)

## Primera tecla de «avanzar» (lo que hay que pulsar para interactuar).
static func _forward_key() -> String:
	var keys: Array = Controls.ACTIONS["move_forward"].keys
	if keys.is_empty():
		return ""
	return String(Controls.KEY_NAMES.get(int(keys[0]), OS.get_keycode_string(int(keys[0]))))

func show_message(text: String) -> void:
	message_label.text = text
	_fit_message()
	if _message_tween:
		_message_tween.kill()
	# Aparece y se disuelve por pasos (como los toasts), sin fundido suave.
	message_panel.visible = true
	message_panel.modulate.a = 1.0
	_message_tween = message_panel.create_tween()
	_message_tween.tween_interval(MESSAGE_TIME)
	for a: float in [0.66, 0.33]:
		var alpha := a
		_message_tween.tween_callback(func() -> void: message_panel.modulate.a = alpha)
		_message_tween.tween_interval(0.066)
	_message_tween.tween_callback(func() -> void: message_panel.visible = false)

## Mensajes largos: se parten en líneas sin pasar de 720 px (ni del ancho
## de la ventana con la escala de UI grande).
func _fit_message() -> void:
	if message_label == null:
		return
	var vp := message_panel.get_viewport_rect().size
	var max_w := minf(720.0, vp.x - 2.0 * UIStyle.MARGIN_SCREEN - 40.0)
	var font := message_label.get_theme_font("font")
	var font_size := message_label.get_theme_font_size("font_size")
	var w := font.get_string_size(message_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if w > max_w:
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message_label.custom_minimum_size.x = max_w
	else:
		message_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		message_label.custom_minimum_size.x = 0
	# Rectángulo nulo: toma su tamaño mínimo centrado y crece hacia arriba.
	message_panel.offset_left = 0
	message_panel.offset_right = 0
	message_panel.offset_top = -136
	message_panel.offset_bottom = -136

## Atajos: visibles mientras se juega; tras 10 s sin tocar nada se ocultan.
func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
		_idle = 0.0
		if hints and not hints.visible:
			hints.visible = true

func _process(delta: float) -> void:
	_idle += delta
	if hints and hints.visible and _idle >= HINTS_IDLE:
		hints.visible = false


## Placa de un héroe: [retrato] Nombre NV 3 🔥🔥▯ ········ 20/20
##                              ▮▮▮▮▮▮▮▮▮▮ HP ▮▮▮▮▮▮▮▮▮▮▮▮
##                              ▮▮▮ EXP ▮▮▮▮▮      ▲ pips de vela
class HeroPlate extends PanelContainer:
	var member_id := ""
	var portrait: UIPortrait
	var name_label: Label
	var level_label: Label
	var souls: UISoulSlots
	var hp_label: Label
	var hp_bar: UIStatBar
	var xp_bar: UIStatBar
	var points_box: HBoxContainer
	var points: UIPips
	var points_more: Label
	var _souls_key := ""
	var _points_key := -1

	func _init(m: Dictionary) -> void:
		theme_type_variation = "HudPanel"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size.x = 264
		member_id = String(m.get("id", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		add_child(row)
		portrait = UIPortrait.for_hero(member_id, 28)
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(portrait)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)

		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		col.add_child(top)
		name_label = UILabel.make(String(m.get("name", "")), "SubtitleLabel")
		top.add_child(name_label)
		level_label = UILabel.make("", "XpLabel")
		level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(level_label)
		souls = UISoulSlots.new(0, 1)
		top.add_child(souls)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(spacer)
		hp_label = UILabel.make("", "NumSmallLabel")
		hp_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(hp_label)

		hp_bar = UIStatBar.new("", "hp", 140)
		hp_bar.value_label.visible = false
		col.add_child(hp_bar)

		var bottom := HBoxContainer.new()
		bottom.add_theme_constant_override("separation", 6)
		bottom.custom_minimum_size.y = 14
		col.add_child(bottom)
		xp_bar = UIStatBar.new("", "xp_thin", 60)
		xp_bar.value_label.visible = false
		xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bottom.add_child(xp_bar)
		# ▲ + pips de vela que laten: puntos sin repartir (Tab → Atributos).
		points_box = HBoxContainer.new()
		points_box.add_theme_constant_override("separation", 4)
		points_box.visible = false
		bottom.add_child(points_box)
		var mark := UILabel.make(DataRegistry.t("hud.points_mark"), "DetailLabel")
		mark.add_theme_color_override("font_color", UIStyle.ACCENT)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		points_box.add_child(mark)
		points = UIPips.new(0, 0, "vela")
		points_box.add_child(points)
		points_more = UILabel.make("", "NumSmallLabel")
		points_more.add_theme_color_override("font_color", UIStyle.ACCENT)
		points_more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		points_more.visible = false
		points_box.add_child(points_more)

	func refresh(m: Dictionary) -> void:
		var hp := int(m.hp)
		var max_hp := GameState.member_max_hp(m)
		var fallen := hp <= 0
		hp_bar.set_values(hp, max_hp)
		hp_label.text = "%d/%d" % [maxi(hp, 0), max_hp]
		level_label.text = DataRegistry.t("hud.level", [int(m.level)]).to_upper()
		var need := RunRules.xp_to_next(int(m.level))
		xp_bar.set_values(int(m.xp) if need > 0 else 1, need if need > 0 else 1)
		var used := (m.souls as Array).size()
		var cap := GameState.member_soul_capacity(m)
		var souls_key := "%d/%d" % [used, cap]
		if souls_key != _souls_key:
			_souls_key = souls_key
			souls.setup(used, cap)
		var pts := int(m.points)
		if pts != _points_key:
			_points_key = pts
			points_box.visible = pts > 0
			if pts > 0:
				var shown := mini(pts, MAX_POINT_PIPS)
				points.setup(shown, shown, "vela")
			points_more.visible = pts > MAX_POINT_PIPS
			points_more.text = "+%d" % (pts - MAX_POINT_PIPS)
		portrait.set_fallen(fallen)
		var name_color := UIStyle.TEXT_OFF if fallen else UIStyle.TEXT
		name_label.add_theme_color_override("font_color", name_color)
		hp_label.add_theme_color_override("font_color", UIStyle.TEXT_OFF if fallen else UIStyle.TEXT_DIM)
		level_label.add_theme_color_override("font_color", UIStyle.TEXT_OFF if fallen else UIStyle.XP)
