class_name StatusScreen
extends UIScreen
## Estado del equipo (Tab): pestañas Equipo / Atributos / Almas / Objetos. Se
## reconstruye al abrir a partir de GameState, así siempre refleja lo actual
## (almas recién recogidas, HP, objetos). Q/E o LB/RB cambian de pestaña. Si
## alguien tiene puntos sin repartir, abre directo en Atributos.

var tabs: UITabs
var attributes: AttributesPage
var party_page: Control
var _closing := false

func _init() -> void:
	super(DataRegistry.t("status.title"))

func _ready() -> void:
	super._ready()
	toggle_action = "open_status"
	show_coins(GameState.run_coins())
	tabs = UITabs.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	party_page = _party_page()
	tabs.add_tab(DataRegistry.t("status.tab_party"), party_page, "estado")
	attributes = AttributesPage.new()
	attributes.applied.connect(_rebuild_party_page)
	tabs.add_tab(DataRegistry.t("status.tab_attributes"), attributes, "estadisticas")
	tabs.add_tab(DataRegistry.t("status.tab_souls"), _souls_page(), "almas")
	tabs.add_tab(DataRegistry.t("status.tab_items"), _items_page(), "inventario")
	add_footer_hint(DataRegistry.t("status.tabs_hint"))
	add_footer_button(DataRegistry.t("ui.close"), close)
	if GameState.points_pending():
		tabs.select(1)
		attributes.first_member_button().call_deferred("grab_focus")
	else:
		tabs.tab_bar.call_deferred("grab_focus")

## Con puntos repartidos sin confirmar, pregunta antes de cerrar.
func close() -> void:
	if _closing:
		return
	if attributes != null and attributes.has_pending():
		_closing = true
		var d := UIConfirmDialog.ask(self, DataRegistry.t("attr.pending_title"), DataRegistry.t("attr.pending_text"), DataRegistry.t("attr.apply"), DataRegistry.t("attr.discard"))
		if await d.answered:
			attributes.apply_all()
	super.close()

func _rebuild_party_page() -> void:
	for c in party_page.get_children():
		c.queue_free()
	_fill_party(party_page as HBoxContainer)

func _party_page() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	_fill_party(row)
	return row

## Una tarjeta por héroe: retrato, nombre, nivel, HP, las 6 estadísticas y
## sus almas.
func _fill_party(row: HBoxContainer) -> void:
	for m: Dictionary in GameState.party:
		var fallen := int(m.hp) <= 0
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", UIStyle.SPACE * 2)
		card.add_child(box)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", UIStyle.SPACE * 4)
		box.add_child(head)
		var pic := UIPortrait.for_hero(String(m.id), 96)
		pic.set_fallen(fallen)
		head.add_child(pic)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", UIStyle.SPACE)
		head.add_child(info)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", UIStyle.SPACE * 2)
		info.add_child(name_row)
		name_row.add_child(UILabel.make(String(m.name), "HeadLabel"))
		if fallen:
			var f := UILabel.make(DataRegistry.t("combat.fallen"), "DangerLabel")
			f.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			name_row.add_child(f)
		var need := RunRules.xp_to_next(int(m.level))
		info.add_child(UILabel.make(DataRegistry.t("attr.level_max", [int(m.level)]) if need == 0 else DataRegistry.t("attr.level", [int(m.level)]), "XpLabel"))
		var hp := UIStatBar.new(DataRegistry.t("stat.hp"), "hp", 160)
		hp.set_values(int(m.hp), GameState.member_max_hp(m))
		info.add_child(hp)
		if need > 0:
			var xp := UIStatBar.new(DataRegistry.t("attr.xp"), "xp_thin", 160)
			xp.set_values(int(m.xp), need)
			info.add_child(xp)
		box.add_child(UIDivider.new(320))
		# Estadísticas: [ícono] SIGLA valor, en dos filas de tres.
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", UIStyle.SPACE * 4)
		grid.add_theme_constant_override("v_separation", UIStyle.SPACE)
		box.add_child(grid)
		for id in RunRules.STATS:
			var cell := HBoxContainer.new()
			cell.add_theme_constant_override("separation", UIStyle.SPACE * 2)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_child(UIIcon.make("stat_" + id))
			var short := UILabel.make(DataRegistry.t("stats.%s.short" % id), "NumSmallLabel")
			short.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cell.add_child(short)
			var v := UILabel.make("%d" % GameState.member_stat(m, id), "NumLabel")
			v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cell.add_child(v)
			grid.add_child(cell)
		var combat_line := UILabel.make(DataRegistry.t("status.combat_line", [GameState.member_atk(m), GameState.member_def(m)]), "DetailLabel")
		box.add_child(combat_line)
		# Almas: espacios + nombre de cada una.
		var souls: Array = m.souls
		var souls_row := HBoxContainer.new()
		souls_row.add_theme_constant_override("separation", UIStyle.SPACE * 2)
		box.add_child(souls_row)
		souls_row.add_child(UISoulSlots.new(souls.size(), GameState.member_soul_capacity(m)))
		var names: Array[String] = []
		for soul: Dictionary in souls:
			var active: Dictionary = soul.get("active", {})
			names.append(String(active.get("name", "")))
		var souls_text := UILabel.make(", ".join(names) if not names.is_empty() else DataRegistry.t("status.no_souls_short"), "SoulLabel" if not names.is_empty() else "DimLabel", true)
		souls_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		souls_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		souls_row.add_child(souls_text)
		if int(m.points) > 0:
			var pts := HBoxContainer.new()
			pts.add_theme_constant_override("separation", UIStyle.SPACE * 2)
			pts.add_child(UIPips.new(int(m.points), int(m.points), "vela"))
			var pl := UILabel.make(DataRegistry.t("attr.points", [int(m.points)]), "GoodLabel")
			pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pts.add_child(pl)
			box.add_child(pts)

func _souls_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	scroll.add_child(row)
	for m: Dictionary in GameState.party:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", UIStyle.SPACE * 2)
		row.add_child(col)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", UIStyle.SPACE * 2)
		col.add_child(head)
		var pic := UIPortrait.for_hero(String(m.id), 48)
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(pic)
		var hn := UILabel.make(String(m.name), "HeadLabel")
		hn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(hn)
		var souls: Array = m.souls
		var slots := UISoulSlots.new(souls.size(), GameState.member_soul_capacity(m))
		head.add_child(slots)
		col.add_child(UIDivider.new(240))
		if souls.is_empty():
			col.add_child(UILabel.make(DataRegistry.t("status.no_souls"), "DimLabel", true))
		for soul: Dictionary in souls:
			col.add_child(UISoulCard.new(soul))
	return scroll

## Morral de solo lectura (para usar algo, el Inventario).
func _items_page() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	box.add_child(head)
	head.add_child(UIIcon.make("inventario"))
	var title := UILabel.make(DataRegistry.t("inventory.bag"), "HeadLabel")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var count := UILabel.make("%d/%d" % [GameState.inventory.size(), GameState.inventory_capacity()], "NumLabel")
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(count)
	var bonus := GameState.run_atk_bonus()
	if bonus > 0:
		box.add_child(UILabel.make(DataRegistry.t("status.run_bonus", [bonus]), "GoodLabel"))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", UIStyle.SPACE * 2)
	grid.add_theme_constant_override("v_separation", UIStyle.SPACE * 2)
	box.add_child(grid)
	for i in GameState.inventory_capacity():
		var id := GameState.inventory[i] if i < GameState.inventory.size() else ""
		var slot := UIItemSlot.new(id, true, true)
		# Solo para mirar: el nombre y la descripción salen en el tooltip.
		slot.focus_mode = Control.FOCUS_ALL if id != "" else Control.FOCUS_NONE
		grid.add_child(slot)
	box.add_child(UILabel.make(DataRegistry.t("status.use_hint"), "DetailLabel"))
	return box
