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
	tabs.add_tab(DataRegistry.t("status.tab_party"), party_page)
	attributes = AttributesPage.new()
	attributes.applied.connect(_rebuild_party_page)
	tabs.add_tab(DataRegistry.t("status.tab_attributes"), attributes)
	tabs.add_tab(DataRegistry.t("status.tab_souls"), _souls_page())
	tabs.add_tab(DataRegistry.t("status.tab_items"), _items_page())
	var hint := Label.new()
	hint.theme_type_variation = "DetailLabel"
	hint.text = DataRegistry.t("status.tabs_hint")
	footer.add_child(hint)
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

func _fill_party(row: HBoxContainer) -> void:
	for m: Dictionary in GameState.party:
		var card := UIPanel.new(String(m.name), "PanelAlt")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", UIStyle.SPACE * 3)
		card.body.add_child(head)
		var pic := UIPortrait.for_hero(String(m.id), 72)
		pic.set_dimmed(int(m.hp) <= 0)
		head.add_child(pic)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(info)
		var lvl := Label.new()
		lvl.theme_type_variation = "AccentLabel"
		var need := RunRules.xp_to_next(int(m.level))
		lvl.text = DataRegistry.t("status.level_line_max", [int(m.level)]) if need == 0 else DataRegistry.t("status.level_line", [int(m.level), int(m.xp), need])
		info.add_child(lvl)
		var bar := UIStatBar.new(DataRegistry.t("stat.hp"))
		bar.set_values(int(m.hp), GameState.member_max_hp(m))
		info.add_child(bar)
		var atk := Label.new()
		atk.text = DataRegistry.t("status.atk_line", [GameState.member_atk(m), int(m.base_atk)])
		card.body.add_child(atk)
		var hp := Label.new()
		hp.theme_type_variation = "DimLabel"
		hp.text = DataRegistry.t("status.hp_line", [GameState.member_max_hp(m), int(m.base_hp)])
		card.body.add_child(hp)
		if GameState.member_def(m) > 0:
			var def := Label.new()
			def.theme_type_variation = "DimLabel"
			def.text = DataRegistry.t("status.def_line", [GameState.member_def(m)])
			card.body.add_child(def)
		var cap := Label.new()
		cap.theme_type_variation = "SoulLabel"
		cap.text = DataRegistry.t("status.capacity", [(m.souls as Array).size(), GameState.member_soul_capacity(m)])
		card.body.add_child(cap)
		if int(m.points) > 0:
			var pts := Label.new()
			pts.theme_type_variation = "GoodLabel"
			pts.text = DataRegistry.t("attr.points", [int(m.points)])
			card.body.add_child(pts)
		if int(m.hp) <= 0:
			var fallen := Label.new()
			fallen.theme_type_variation = "DangerLabel"
			fallen.text = DataRegistry.t("combat.fallen")
			card.body.add_child(fallen)

func _souls_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	scroll.add_child(row)
	for m: Dictionary in GameState.party:
		var col := UIPanel.new(String(m.name), "PanelAlt")
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var souls: Array = m.souls
		if souls.is_empty():
			var empty := Label.new()
			empty.theme_type_variation = "DimLabel"
			empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			empty.text = DataRegistry.t("status.no_souls")
			col.body.add_child(empty)
		for soul: Dictionary in souls:
			col.body.add_child(UISoulCard.new(soul))
	return scroll

func _items_page() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	var bonus := GameState.run_atk_bonus()
	if bonus > 0:
		var b := Label.new()
		b.theme_type_variation = "GoodLabel"
		b.text = DataRegistry.t("status.run_bonus", [bonus])
		box.add_child(b)
	if GameState.inventory.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = "DimLabel"
		empty.text = DataRegistry.t("inventory.empty")
		box.add_child(empty)
	for id in GameState.inventory:
		var it := DataRegistry.get_item(id)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", UIStyle.SPACE * 3)
		box.add_child(line)
		line.add_child(UIPortrait.for_item(id, 40))
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.text = "%s — %s" % [it.nombre, it.descripcion]
		line.add_child(l)
	var cap := Label.new()
	cap.theme_type_variation = "DetailLabel"
	cap.text = DataRegistry.t("inventory.capacity", [GameState.inventory.size(), GameState.inventory_capacity()])
	box.add_child(cap)
	if not GameState.inventory.is_empty():
		var use := Label.new()
		use.theme_type_variation = "DetailLabel"
		use.text = DataRegistry.t("status.use_hint")
		box.add_child(use)
	return box
