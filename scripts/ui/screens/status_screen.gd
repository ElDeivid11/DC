class_name StatusScreen
extends UIScreen
## Estado del equipo (Tab): pestañas Equipo / Almas / Objetos. Se reconstruye
## al abrir a partir de GameState, así siempre refleja lo actual (almas recién
## recogidas, HP, objetos). Q/E o LB/RB cambian de pestaña.

func _init() -> void:
	super(DataRegistry.t("status.title"))

func _ready() -> void:
	super._ready()
	toggle_action = "open_status"
	show_coins(GameState.run_coins())
	var tabs := UITabs.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	tabs.add_tab(DataRegistry.t("status.tab_party"), _party_page())
	tabs.add_tab(DataRegistry.t("status.tab_souls"), _souls_page())
	tabs.add_tab(DataRegistry.t("status.tab_items"), _items_page())
	var hint := Label.new()
	hint.theme_type_variation = "DetailLabel"
	hint.text = DataRegistry.t("status.tabs_hint")
	footer.add_child(hint)
	add_footer_button(DataRegistry.t("ui.close"), close)
	tabs.tab_bar.call_deferred("grab_focus")

func _party_page() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	for m: Dictionary in GameState.party:
		var card := UIPanel.new(String(m.name), "PanelAlt")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		var bar := UIStatBar.new(DataRegistry.t("stat.hp"))
		bar.set_values(int(m.hp), GameState.member_max_hp(m))
		card.body.add_child(bar)
		var atk := Label.new()
		atk.text = DataRegistry.t("status.atk_line", [GameState.member_atk(m), int(m.base_atk)])
		card.body.add_child(atk)
		var hp := Label.new()
		hp.theme_type_variation = "DimLabel"
		hp.text = DataRegistry.t("status.hp_line", [GameState.member_max_hp(m), int(m.base_hp)])
		card.body.add_child(hp)
		var cap := Label.new()
		cap.theme_type_variation = "SoulLabel"
		cap.text = DataRegistry.t("status.capacity", [(m.souls as Array).size(), GameState.member_soul_capacity(m)])
		card.body.add_child(cap)
		if int(m.hp) <= 0:
			var fallen := Label.new()
			fallen.theme_type_variation = "DangerLabel"
			fallen.text = DataRegistry.t("combat.fallen")
			card.body.add_child(fallen)
	return row

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
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = "%s — %s" % [it.nombre, it.descripcion]
		box.add_child(l)
	var cap := Label.new()
	cap.theme_type_variation = "DetailLabel"
	cap.text = DataRegistry.t("inventory.capacity", [GameState.inventory.size(), GameState.inventory_capacity()])
	box.add_child(cap)
	return box
