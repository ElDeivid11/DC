class_name AttributesPage
extends HBoxContainer
## Pestaña "Atributos" de Estado, en tres columnas:
##  - el héroe: filas de personajes (retrato, nivel y pips de vela con los
##    puntos sin repartir), retrato grande, nivel, EXP, espacios de alma;
##  - el hexágono de estadísticas (UIStatRadar);
##  - las 6 filas de estadística ([ícono] SIGLA Nombre valor [−][+] efecto)
##    y abajo Deshacer / Confirmar.
## Lo repartido queda pendiente (contorno de vela en el hexágono) hasta
## Confirmar, que lo aplica con GameState.apply_points(). Cada personaje
## guarda su reparto pendiente aunque se cambie de personaje. Con poco ancho
## (escala de UI Grande) el hexágono baja a la columna del héroe.

signal applied

const LEFT_WIDTH := 280
const NARROW := 1150.0

var member_buttons: Array[UIListRow] = []
var member_levels: Array[Label] = []
var member_pips: Array[UIPips] = []
var portrait: UIPortrait
var name_label: Label
var level_label: Label
var xp_bar: UIStatBar
var soul_slots: UISoulSlots
var souls_label: Label
var points_label: Label
var radar: UIStatRadar
var left: VBoxContainer
var value_labels: Dictionary = {} # stat → Label
var effect_labels: Dictionary = {} # stat → Label
var stat_icons: Dictionary = {} # stat → UIIcon
var minus_buttons: Dictionary = {} # stat → UIButton
var plus_buttons: Dictionary = {} # stat → UIButton
var confirm_btn: UIButton
var undo_btn: UIButton
var current := 0
## Reparto sin confirmar: {member_id: {stat: puntos}}.
var pending: Dictionary = {}

func _init() -> void:
	add_theme_constant_override("separation", UIStyle.SPACE * 4)
	_build_left()
	radar = UIStatRadar.new(240)
	radar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(radar)
	_build_stats()
	_select(_first_with_points())

func _build_left() -> void:
	left = VBoxContainer.new()
	left.custom_minimum_size.x = LEFT_WIDTH
	left.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	add_child(left)
	for i in GameState.party.size():
		var m: Dictionary = GameState.party[i]
		var b := UIListRow.new(String(m.name), "", UIPortrait.hero_texture(String(m.id)))
		var pips := UIPips.new(0, 0, "vela")
		b.add_column(pips)
		var lvl := UILabel.make("", "NumSmallLabel")
		b.add_column(lvl)
		var idx := i
		b.focus_entered.connect(func() -> void: _select(idx))
		b.pressed.connect(func() -> void: _focus_stats())
		left.add_child(b)
		member_buttons.append(b)
		member_levels.append(lvl)
		member_pips.append(pips)
	UIFocus.chain_vertical(member_buttons, false)
	left.add_child(UIDivider.new(LEFT_WIDTH - 40))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	left.add_child(head)
	portrait = UIPortrait.new(null, 96)
	head.add_child(portrait)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", UIStyle.SPACE)
	head.add_child(info)
	name_label = UILabel.make("", "HeadLabel")
	info.add_child(name_label)
	level_label = UILabel.make("", "XpLabel")
	info.add_child(level_label)
	var souls_row := HBoxContainer.new()
	souls_row.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	soul_slots = UISoulSlots.new()
	souls_row.add_child(soul_slots)
	souls_label = UILabel.make("", "NumSmallLabel")
	souls_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	souls_row.add_child(souls_label)
	info.add_child(souls_row)
	xp_bar = UIStatBar.new(DataRegistry.t("attr.xp"), "xp", 160)
	left.add_child(xp_bar)
	left.add_child(UILabel.make(DataRegistry.t("attr.soul_rule", [DataRegistry.bal_i("leveling.soul_slot_every", 2)]), "DetailLabel", true))
	points_label = UILabel.make("", "", true)
	left.add_child(points_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	left.add_child(UILabel.make(DataRegistry.t("attr.party_note"), "DetailLabel", true))

func _build_stats() -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	add_child(col)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", UIStyle.SPACE * 2)
	grid.add_theme_constant_override("v_separation", UIStyle.SPACE)
	col.add_child(grid)
	for id in RunRules.STATS:
		var stat := id
		var icon := UIIcon.make("stat_" + id)
		grid.add_child(icon)
		var short := UILabel.make(DataRegistry.t("stats.%s.short" % id), "NumSmallLabel")
		short.custom_minimum_size.x = 36
		short.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(short)
		var name_l := UILabel.make(DataRegistry.t("stats.%s.name" % id))
		name_l.custom_minimum_size.x = 104
		name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(name_l)
		var value_l := UILabel.make("", "NumLabel")
		value_l.custom_minimum_size.x = 40
		value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(value_l)
		var minus := UIButton.make(DataRegistry.t("attr.minus"), func() -> void: _change(stat, -1))
		minus.custom_minimum_size = Vector2(36, 36)
		UITooltip.attach(minus, _desc(id))
		grid.add_child(minus)
		var plus := UIButton.make(DataRegistry.t("attr.plus"), func() -> void: _change(stat, 1))
		plus.custom_minimum_size = Vector2(36, 36)
		UITooltip.attach(plus, _desc(id))
		grid.add_child(plus)
		var effect_l := UILabel.make("", "DetailLabel")
		effect_l.custom_minimum_size.x = 168
		effect_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(effect_l)
		stat_icons[id] = icon
		value_labels[id] = value_l
		effect_labels[id] = effect_l
		minus_buttons[id] = minus
		plus_buttons[id] = plus
		# Con foco en − o +, el ícono de la fila se enciende.
		for b: UIButton in [minus, plus]:
			b.focus_entered.connect(func() -> void: icon.set_ramp("vela"))
			b.focus_exited.connect(func() -> void: icon.set_ramp("bronce"))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	col.add_child(actions)
	undo_btn = UIButton.make(DataRegistry.t("attr.undo"), _undo)
	undo_btn.custom_minimum_size.x = 160
	actions.add_child(undo_btn)
	confirm_btn = UIButton.make(DataRegistry.t("attr.confirm"), _confirm)
	confirm_btn.custom_minimum_size.x = 160
	actions.add_child(confirm_btn)
	# Con teclado/mando, ↓ desde la última fila llega a Confirmar y ↑ vuelve a
	# la grilla (pasar por la lista cambiaría de personaje al enfocarlo).
	var last_stat := RunRules.STATS[RunRules.STATS.size() - 1]
	for b: UIButton in [minus_buttons[last_stat], plus_buttons[last_stat]]:
		b.focus_neighbor_bottom = b.get_path_to(confirm_btn)
	confirm_btn.focus_neighbor_top = confirm_btn.get_path_to(plus_buttons[last_stat])
	undo_btn.focus_neighbor_top = undo_btn.get_path_to(minus_buttons[last_stat])

func _ready() -> void:
	# Las tres columnas necesitan ~1100 px: con la escala Grande el hexágono
	# baja a la columna del héroe.
	if get_viewport_rect().size.x < NARROW:
		radar.reparent(left)
		left.move_child(radar, left.get_child_count() - 2)
		radar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

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
	name_label.text = String(m.name)
	portrait.set_texture(UIPortrait.hero_texture(String(m.id)))
	portrait.set_fallen(int(m.hp) <= 0)
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
	var used := (m.souls as Array).size()
	var capacity := GameState.member_soul_capacity(m)
	soul_slots.setup(used, capacity)
	souls_label.text = DataRegistry.t("attr.soul_count", [used, capacity])
	if int(m.points) > 0:
		points_label.text = DataRegistry.t("attr.points", [free])
		points_label.theme_type_variation = "GoodLabel" if free > 0 else "DimLabel"
	else:
		points_label.text = DataRegistry.t("attr.no_points", [DataRegistry.bal_i("leveling.points_per_level", 3)])
		points_label.theme_type_variation = "DetailLabel"
	radar.set_values(m.stats, alloc)
	for id in RunRules.STATS:
		var add := int(alloc.get(id, 0))
		var total := GameState.member_stat(m, id) + add
		var value_l: Label = value_labels[id]
		value_l.text = "%d" % total
		if add > 0:
			value_l.add_theme_color_override("font_color", UIStyle.ACCENT)
		else:
			value_l.remove_theme_color_override("font_color")
		var effect_l: Label = effect_labels[id]
		effect_l.text = _effect(id, total)
		effect_l.theme_type_variation = "GoodLabel" if add > 0 else "DetailLabel"
		(minus_buttons[id] as UIButton).disabled = add <= 0
		(plus_buttons[id] as UIButton).disabled = free <= 0
	confirm_btn.disabled = spent <= 0
	undo_btn.disabled = spent <= 0
	for i in member_buttons.size():
		var mm: Dictionary = GameState.party[i]
		var left_pts := int(mm.points) - _spent(_alloc(mm))
		member_levels[i].text = DataRegistry.t("attr.level_short", [int(mm.level)])
		member_pips[i].setup(left_pts, left_pts, "vela")
		member_pips[i].visible = left_pts > 0
		member_buttons[i].set_locked(int(mm.hp) <= 0)

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
	SceneRouter.play_ui("click" if delta > 0 else "cancel")
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
		SceneRouter.play_ui("level_up")
		UIToast.show(get_tree(), DataRegistry.t("attr.applied", [m.name]), "level")
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
