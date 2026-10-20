class_name AttributesPage
extends HBoxContainer
## Pestaña "Atributos" de Estado: personajes a la izquierda y, del elegido,
## retrato, nivel, EXP, el hexágono de estadísticas y el reparto de puntos
## (− / + por estadística). Lo repartido queda pendiente (contorno verde en el
## hexágono) hasta Confirmar, que lo aplica con GameState.apply_points().
## Cada personaje guarda su reparto pendiente aunque se cambie de personaje.
## Confirmar / Deshacer quedan bajo la lista de personajes. Con poco ancho
## (escala de UI alta) el hexágono va arriba de las filas en vez de al lado.

signal applied

var member_buttons: Array[UIButton] = []
var detail: UIPanel
var portrait: UIPortrait
var level_label: Label
var xp_bar: UIStatBar
var souls_label: Label
var points_label: Label
var radar: UIStatRadar
var value_labels: Dictionary = {} # stat → Label
var effect_labels: Dictionary = {} # stat → Label
var minus_buttons: Dictionary = {} # stat → UIButton
var plus_buttons: Dictionary = {} # stat → UIButton
var confirm_btn: UIButton
var undo_btn: UIButton
var mid: BoxContainer
var current := 0
## Reparto sin confirmar: {member_id: {stat: puntos}}.
var pending: Dictionary = {}

func _init() -> void:
	add_theme_constant_override("separation", UIStyle.SPACE * 4)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 250
	list.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	add_child(list)
	for i in GameState.party.size():
		var m: Dictionary = GameState.party[i]
		var b := UIButton.new("", "ItemSlot")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = UIPortrait.hero_texture(String(m.id))
		b.add_theme_constant_override("icon_max_width", 40)
		var idx := i
		b.focus_entered.connect(func() -> void: _select(idx))
		b.pressed.connect(func() -> void: _focus_stats())
		list.add_child(b)
		member_buttons.append(b)
	UIFocus.chain_vertical(member_buttons, false)

	detail = UIPanel.new("", "PanelAlt")
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(detail)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	detail.body.add_child(head)
	portrait = UIPortrait.new(null, 88)
	head.add_child(portrait)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	level_label = Label.new()
	level_label.theme_type_variation = "AccentLabel"
	info.add_child(level_label)
	xp_bar = UIStatBar.new(DataRegistry.t("attr.xp"), "accent", 200)
	info.add_child(xp_bar)
	souls_label = Label.new()
	souls_label.theme_type_variation = "SoulLabel"
	info.add_child(souls_label)
	points_label = Label.new()
	points_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(points_label)

	mid = BoxContainer.new()
	mid.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	detail.body.add_child(mid)
	radar = UIStatRadar.new(236)
	mid.add_child(radar)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", UIStyle.SPACE * 2)
	grid.add_theme_constant_override("v_separation", UIStyle.SPACE)
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(grid)
	for id in RunRules.STATS:
		var stat := id
		var name_l := Label.new()
		name_l.text = DataRegistry.t("stats.%s.name" % id)
		name_l.custom_minimum_size.x = 96
		name_l.tooltip_text = _desc(id)
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(name_l)
		var value_l := Label.new()
		value_l.custom_minimum_size.x = 28
		value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value_l)
		var minus := UIButton.make("−", func() -> void: _change(stat, -1))
		minus.custom_minimum_size.x = UIStyle.BUTTON_MIN_H
		UITooltip.attach(minus, _desc(id))
		grid.add_child(minus)
		var plus := UIButton.make("+", func() -> void: _change(stat, 1))
		plus.custom_minimum_size.x = UIStyle.BUTTON_MIN_H
		UITooltip.attach(plus, _desc(id))
		grid.add_child(plus)
		var effect_l := Label.new()
		effect_l.theme_type_variation = "DetailLabel"
		effect_l.custom_minimum_size.x = 210
		grid.add_child(effect_l)
		value_labels[id] = value_l
		effect_labels[id] = effect_l
		minus_buttons[id] = minus
		plus_buttons[id] = plus

	# Confirmar / Deshacer y la nota van abajo de la lista de personajes: ahí
	# sobra lugar y el detalle entra entero sin desplazarse.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_child(spacer)
	confirm_btn = UIButton.make(DataRegistry.t("attr.confirm"), _confirm)
	undo_btn = UIButton.make(DataRegistry.t("attr.undo"), _undo)
	list.add_child(confirm_btn)
	list.add_child(undo_btn)
	# Con teclado/mando, ↓ desde la última fila llega a Confirmar y ↑ vuelve a
	# la grilla (pasar por la lista cambiaría de personaje al enfocarlo).
	var last_stat := RunRules.STATS[RunRules.STATS.size() - 1]
	for b: UIButton in [minus_buttons[last_stat], plus_buttons[last_stat]]:
		b.focus_neighbor_bottom = b.get_path_to(confirm_btn)
	confirm_btn.focus_neighbor_top = confirm_btn.get_path_to(plus_buttons[last_stat])
	var note := Label.new()
	note.theme_type_variation = "DetailLabel"
	note.text = DataRegistry.t("attr.party_note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(note)
	_select(_first_with_points())

func _ready() -> void:
	# Las filas necesitan unos 1000 px al lado del hexágono: con la escala de UI
	# al 150% (853 px de ancho útil) se apilan.
	mid.vertical = get_viewport_rect().size.x < 1150.0

## Primer personaje con puntos sin repartir (o el primero).
func _first_with_points() -> int:
	for i in GameState.party.size():
		if int(GameState.party[i].points) > 0:
			return i
	return 0

func first_member_button() -> UIButton:
	return member_buttons[_first_with_points()] if not member_buttons.is_empty() else null

func has_pending() -> bool:
	for id: Variant in pending.keys():
		if _spent(pending[id]) > 0:
			return true
	return false

## Aplica todo lo pendiente (al salir de la pantalla y responder "Aplicar").
func apply_all() -> void:
	for m: Dictionary in GameState.party:
		var alloc := _alloc(m)
		if _spent(alloc) > 0:
			GameState.apply_points(m, alloc)
	pending.clear()
	applied.emit()

func _member() -> Dictionary:
	return GameState.party[current]

func _alloc(m: Dictionary) -> Dictionary:
	var a: Dictionary = pending.get(String(m.id), {})
	return a

func _spent(alloc: Dictionary) -> int:
	var total := 0
	for stat: Variant in alloc.keys():
		total += int(alloc[stat])
	return total

func _select(index: int) -> void:
	current = clampi(index, 0, GameState.party.size() - 1)
	var m := _member()
	detail.set_title(String(m.name))
	portrait.set_texture(UIPortrait.hero_texture(String(m.id)))
	portrait.set_dimmed(int(m.hp) <= 0)
	# ← desde la grilla vuelve al personaje elegido (sin cambiar de personaje).
	for id in RunRules.STATS:
		var minus: UIButton = minus_buttons[id]
		minus.focus_neighbor_left = minus.get_path_to(member_buttons[current])
	_refresh()

func _refresh() -> void:
	var m := _member()
	var alloc := _alloc(m)
	var spent := _spent(alloc)
	var free := int(m.points) - spent
	var level := int(m.level)
	var need := RunRules.xp_to_next(level)
	if need == 0:
		level_label.text = DataRegistry.t("attr.level_max", [level])
		xp_bar.set_values(1, 1)
	else:
		level_label.text = DataRegistry.t("attr.level", [level])
		xp_bar.set_values(int(m.xp), need)
	souls_label.text = DataRegistry.t("attr.soul_slots", [(m.souls as Array).size(), GameState.member_soul_capacity(m), DataRegistry.bal_i("leveling.soul_slot_every", 2)])
	if int(m.points) > 0:
		points_label.text = DataRegistry.t("attr.points", [free])
		points_label.theme_type_variation = "GoodLabel" if free > 0 else ""
	else:
		points_label.text = DataRegistry.t("attr.no_points", [DataRegistry.bal_i("leveling.points_per_level", 3)])
		points_label.theme_type_variation = "DimLabel"
	radar.set_values(m.stats, alloc)
	for id in RunRules.STATS:
		var add := int(alloc.get(id, 0))
		var total := GameState.member_stat(m, id) + add
		var value_l: Label = value_labels[id]
		value_l.text = "%d" % total
		value_l.theme_type_variation = "GoodLabel" if add > 0 else ""
		var effect_l: Label = effect_labels[id]
		effect_l.text = _effect(id, total)
		effect_l.theme_type_variation = "GoodLabel" if add > 0 else "DetailLabel"
		(minus_buttons[id] as UIButton).disabled = add <= 0
		(plus_buttons[id] as UIButton).disabled = free <= 0
	confirm_btn.disabled = spent <= 0
	undo_btn.disabled = spent <= 0
	for i in member_buttons.size():
		var mm: Dictionary = GameState.party[i]
		var left := int(mm.points) - _spent(_alloc(mm))
		if left > 0:
			member_buttons[i].text = DataRegistry.t("attr.member_points", [mm.name, int(mm.level), left])
		else:
			member_buttons[i].text = DataRegistry.t("attr.member", [mm.name, int(mm.level)])

func _change(stat: String, delta: int) -> void:
	var m := _member()
	var alloc := _alloc(m).duplicate()
	var now := int(alloc.get(stat, 0)) + delta
	if now < 0 or (delta > 0 and _spent(alloc) >= int(m.points)):
		return
	if now == 0:
		alloc.erase(stat)
	else:
		alloc[stat] = now
	pending[String(m.id)] = alloc
	_refresh()
	# Si el botón enfocado quedó deshabilitado (se acabaron los puntos), el
	# foco pasa a Confirmar para no quedar "trabado".
	var focused := get_viewport().gui_get_focus_owner() as BaseButton
	if focused != null and focused.disabled:
		if not confirm_btn.disabled:
			confirm_btn.grab_focus()
		else:
			_focus_stats()

func _confirm() -> void:
	var m := _member()
	var alloc := _alloc(m)
	if _spent(alloc) <= 0:
		return
	if GameState.apply_points(m, alloc):
		pending.erase(String(m.id))
		UIToast.show(get_tree(), DataRegistry.t("attr.applied", [m.name]), "good")
		applied.emit()
	_refresh()
	member_buttons[current].grab_focus()

func _undo() -> void:
	pending.erase(String(_member().id))
	_refresh()
	_focus_stats()

## Foco al primer "+" usable (o al botón del personaje si no tiene puntos).
func _focus_stats() -> void:
	for id in RunRules.STATS:
		var b: UIButton = plus_buttons[id]
		if not b.disabled:
			b.grab_focus()
			return
	member_buttons[current].grab_focus()

func _desc(id: String) -> String:
	var per: float = DataRegistry.bal_f("stats." + _stat_key(id), 0.0)
	match id:
		"vit":
			return DataRegistry.t("stats.vit.desc", [_num(per)])
		"atq", "def", "esp":
			return DataRegistry.t("stats.%s.desc" % id, [roundi(1.0 / per) if per > 0.0 else 0])
		"agi":
			return DataRegistry.t("stats.agi.desc", [_num(per * 100.0)])
		"sue":
			return DataRegistry.t("stats.sue.desc", [_num(per * 100.0), _num(DataRegistry.bal_f("stats.sue_coins", 0.0) * 100.0)])
	return ""

## Clave de balance.json → stats del efecto principal de cada estadística.
func _stat_key(id: String) -> String:
	match id:
		"vit":
			return "vit_hp"
		"atq":
			return "atq_atk"
		"def":
			return "def_reduction"
		"esp":
			return "esp_ability"
		"agi":
			return "agi_crit"
		"sue":
			return "sue_soul"
	return ""

func _effect(id: String, v: int) -> String:
	match id:
		"vit":
			return DataRegistry.t("stats.vit.effect", [RunRules.stat_hp(v)])
		"atq":
			return DataRegistry.t("stats.atq.effect", [RunRules.stat_atk(v)])
		"def":
			return DataRegistry.t("stats.def.effect", [RunRules.stat_def(v)])
		"esp":
			return DataRegistry.t("stats.esp.effect", [RunRules.stat_esp(v)])
		"agi":
			return DataRegistry.t("stats.agi.effect", [_num(RunRules.stat_crit(v) * 100.0)])
		"sue":
			return DataRegistry.t("stats.sue.effect", [RunRules.stat_soul(v) * 100.0, roundi(RunRules.stat_coins(v) * 100.0)])
	return ""

## 1.0 → "1", 1.5 → "1.5".
static func _num(f: float) -> String:
	return "%d" % roundi(f) if is_equal_approx(f, roundf(f)) else "%.1f" % f
