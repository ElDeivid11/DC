class_name RunHud
extends CanvasLayer
## HUD de exploración (fuera del SubViewport: nítido a resolución nativa).
##   sup. izq.: equipo (retrato, HP, nivel, almas y ▲ puntos sin repartir)
##   sup. der.: minimapa 7×7 + brújula N/E/S/O
##   inf. centro: mensajes breves
##   inf. der.: monedas de la run y piso
##   inf. izq.: atajos (Tab/I/M/Esc)
## En debug, arriba al centro: semilla y celda actual.

var party_box: VBoxContainer
var bars: Array[UIStatBar] = []
var soul_labels: Array[Label] = []
var level_labels: Array[Label] = []
var point_labels: Array[Label] = []
var portraits: Array[UIPortrait] = []
var minimap: UIMinimap
var compass_label: Label
var floor_label: Label
var coins_label: Label
var message_label: Label
var debug_label: Label
var _message_tween: Tween

func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Equipo (sup. izq.)
	var party_panel := PanelContainer.new()
	party_panel.theme_type_variation = "HudPanel"
	party_panel.position = Vector2(UIStyle.MARGIN_SCREEN, UIStyle.MARGIN_SCREEN)
	root.add_child(party_panel)
	party_box = VBoxContainer.new()
	party_box.add_theme_constant_override("separation", UIStyle.SPACE)
	party_panel.add_child(party_box)
	for m: Dictionary in GameState.party:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UIStyle.SPACE * 2)
		party_box.add_child(row)
		var pic := UIPortrait.for_hero(String(m.id), 28)
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pic)
		var bar := UIStatBar.new(String(m.name), "hp", 110)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var ll := Label.new()
		ll.theme_type_variation = "DetailLabel"
		ll.custom_minimum_size.x = 34
		row.add_child(ll)
		var sl := Label.new()
		sl.theme_type_variation = "SoulLabel"
		sl.custom_minimum_size.x = 30
		row.add_child(sl)
		var pl := Label.new()
		pl.theme_type_variation = "GoodLabel"
		pl.custom_minimum_size.x = 30
		row.add_child(pl)
		portraits.append(pic)
		bars.append(bar)
		level_labels.append(ll)
		soul_labels.append(sl)
		point_labels.append(pl)

	# Minimapa + brújula (sup. der.)
	var map_panel := PanelContainer.new()
	map_panel.theme_type_variation = "HudPanel"
	map_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	map_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_panel.offset_right = -UIStyle.MARGIN_SCREEN
	map_panel.offset_top = UIStyle.MARGIN_SCREEN
	root.add_child(map_panel)
	var map_box := VBoxContainer.new()
	map_box.add_theme_constant_override("separation", UIStyle.SPACE)
	map_panel.add_child(map_box)
	minimap = UIMinimap.new()
	map_box.add_child(minimap)
	compass_label = Label.new()
	compass_label.theme_type_variation = "AccentLabel"
	compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_box.add_child(compass_label)

	# Monedas y piso (inf. der.)
	var info := PanelContainer.new()
	info.theme_type_variation = "HudPanel"
	info.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info.offset_right = -UIStyle.MARGIN_SCREEN
	info.offset_bottom = -UIStyle.MARGIN_SCREEN
	root.add_child(info)
	var info_box := VBoxContainer.new()
	info.add_child(info_box)
	floor_label = Label.new()
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_box.add_child(floor_label)
	coins_label = Label.new()
	coins_label.theme_type_variation = "CoinLabel"
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_box.add_child(coins_label)

	# Atajos (inf. izq.)
	var hints := Label.new()
	hints.theme_type_variation = "DetailLabel"
	hints.text = DataRegistry.t("hud.hints")
	hints.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hints.offset_left = UIStyle.MARGIN_SCREEN
	hints.offset_bottom = -UIStyle.MARGIN_SCREEN
	root.add_child(hints)

	# Mensajes (inf. centro)
	var msg_panel := PanelContainer.new()
	msg_panel.theme_type_variation = "HudPanel"
	msg_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	msg_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	msg_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	msg_panel.offset_bottom = -UIStyle.MARGIN_SCREEN * 3
	msg_panel.modulate.a = 0.0
	root.add_child(msg_panel)
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_panel.add_child(message_label)

	# Debug (sup. centro)
	debug_label = Label.new()
	debug_label.theme_type_variation = "DetailLabel"
	debug_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	debug_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	debug_label.offset_top = UIStyle.SPACE * 2
	debug_label.visible = OS.is_debug_build()
	root.add_child(debug_label)

	EventBus.hud_message.connect(show_message)
	EventBus.coins_changed.connect(func(_c: int) -> void: refresh())

func refresh() -> void:
	for i in mini(bars.size(), GameState.party.size()):
		var m: Dictionary = GameState.party[i]
		bars[i].set_values(int(m.hp), GameState.member_max_hp(m))
		var n := (m.souls as Array).size()
		soul_labels[i].text = ("%s%d" % [UIStyle.SOUL_SYMBOL, n]) if n > 0 else ""
		level_labels[i].text = DataRegistry.t("hud.level", [int(m.level)])
		# ▲N = puntos sin repartir (Tab → Atributos).
		point_labels[i].text = DataRegistry.t("hud.points", [int(m.points)]) if int(m.points) > 0 else ""
		portraits[i].set_dimmed(int(m.hp) <= 0)
	if GameState.test_room:
		floor_label.text = DataRegistry.t("hud.test_room")
	else:
		floor_label.text = DataRegistry.t("hud.floor", [GameState.floor_n, DataRegistry.bal_i("floors_per_run", 5)])
	coins_label.text = UIFormat.coins(GameState.run_coins())

func update_map(fd: FloorData, cell: Vector2i, facing: int, markers: Dictionary) -> void:
	minimap.update_view(fd, GameState.visited, cell, facing, markers)
	compass_label.text = DataRegistry.t("hud.compass", [DataRegistry.t("dir.%d" % facing)])
	if debug_label.visible:
		debug_label.text = DataRegistry.t("hud.debug", [GameState.run_seed, cell.x, cell.y, Engine.get_frames_per_second()])

func show_message(text: String) -> void:
	message_label.text = text
	var panel := message_label.get_parent() as Control
	if _message_tween:
		_message_tween.kill()
	_message_tween = panel.create_tween()
	_message_tween.tween_property(panel, "modulate:a", 1.0, UIStyle.TRANSITION)
	_message_tween.tween_interval(2.4)
	_message_tween.tween_property(panel, "modulate:a", 0.0, 0.4)
