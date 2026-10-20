class_name InventoryScreen
extends UIScreen
## Inventario de la run (I / X): casillas a la izquierda, detalle del objeto
## enfocado a la derecha (con su retrato), y acciones Usar / Descartar.
## Enter / A sobre una casilla usa el objeto directamente. Los objetos se
## pierden al terminar la run. El uso real lo resuelve
## RunController.use_item_field().

var run: Node
var grid: GridContainer
var slots_panel: UIPanel
var detail: UIPanel
var detail_portrait: UIPortrait
var detail_tag: Label
var detail_text: Label
var use_btn: UIButton
var drop_btn: UIButton
var selected := -1
var _busy := false

func _init(p_run: Node = null) -> void:
	super(DataRegistry.t("inventory.title"))
	run = p_run

func _ready() -> void:
	super._ready()
	toggle_action = "open_inventory"
	show_coins(GameState.run_coins())
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	body.add_child(row)
	slots_panel = UIPanel.new("", "PanelAlt")
	slots_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slots_panel)
	grid = GridContainer.new()
	grid.columns = 2
	slots_panel.body.add_child(grid)
	detail = UIPanel.new("", "PanelAlt")
	detail.custom_minimum_size.x = 420
	row.add_child(detail)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	detail.body.add_child(head)
	detail_portrait = UIPortrait.new(null, 96)
	head.add_child(detail_portrait)
	detail_tag = Label.new()
	detail_tag.theme_type_variation = "DetailLabel"
	detail_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(detail_tag)
	detail_text = Label.new()
	detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.body.add_child(detail_text)
	var actions := HBoxContainer.new()
	detail.body.add_child(actions)
	use_btn = UIButton.make(DataRegistry.t("inventory.use"), _use)
	drop_btn = UIButton.make(DataRegistry.t("inventory.drop"), _drop, "DangerButton")
	actions.add_child(use_btn)
	actions.add_child(drop_btn)
	var hint := Label.new()
	hint.theme_type_variation = "DetailLabel"
	hint.text = DataRegistry.t("inventory.press_hint")
	footer.add_child(hint)
	add_footer_button(DataRegistry.t("ui.close"), close)
	_rebuild()

func _rebuild() -> void:
	for c in grid.get_children():
		c.queue_free()
	var first: Control = null
	for i in GameState.inventory_capacity():
		var id := GameState.inventory[i] if i < GameState.inventory.size() else ""
		var slot := UIItemSlot.new(id, false)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.custom_minimum_size.x = 260
		var idx := i
		slot.focus_entered.connect(func() -> void: _select(idx))
		slot.pressed.connect(func() -> void:
			_select(idx)
			if not use_btn.disabled:
				_use()
		)
		grid.add_child(slot)
		if first == null and id != "":
			first = slot
	slots_panel.set_title(DataRegistry.t("inventory.capacity", [GameState.inventory.size(), GameState.inventory_capacity()]))
	if first:
		first.call_deferred("grab_focus")
		_select(0)
	else:
		_select(-1)
		footer.get_child(footer.get_child_count() - 1).call_deferred("grab_focus")

func _select(index: int) -> void:
	selected = index
	if index < 0 or index >= GameState.inventory.size():
		detail.set_title(DataRegistry.t("inventory.empty_title"))
		detail_portrait.set_texture(null)
		detail_tag.text = ""
		detail_text.text = DataRegistry.t("inventory.empty")
		use_btn.disabled = true
		drop_btn.disabled = true
		return
	var it := DataRegistry.get_item(GameState.inventory[index])
	detail.set_title(String(it.nombre))
	detail_portrait.set_texture(UIPortrait.item_texture(GameState.inventory[index]))
	var where: Array[String] = []
	if it.efecto.fuera_combate:
		where.append(DataRegistry.t("inventory.where_field"))
	if it.efecto.en_combate:
		where.append(DataRegistry.t("inventory.where_combat"))
	var usage := DataRegistry.t("inventory.passive_note") if it.tipo == "pasivo" else DataRegistry.t("inventory.usable_in", [" / ".join(where)])
	detail_tag.text = "%s\n%s" % [DataRegistry.t("item.type." + String(it.tipo)), usage]
	detail_text.text = String(it.descripcion)
	use_btn.disabled = not bool(it.efecto.fuera_combate) or run == null
	drop_btn.disabled = false

func _use() -> void:
	if selected < 0 or run == null or _busy:
		return
	_busy = true
	var used: bool = await (run as RunController).use_item_field(selected, self)
	_busy = false
	if used and is_inside_tree():
		_rebuild()

func _drop() -> void:
	if selected < 0 or selected >= GameState.inventory.size():
		return
	var it := DataRegistry.get_item(GameState.inventory[selected])
	var d := UIConfirmDialog.ask(self, DataRegistry.t("inventory.drop_title"), DataRegistry.t("inventory.drop_text", [it.nombre]), DataRegistry.t("inventory.drop"), DataRegistry.t("ui.cancel"), true)
	if await d.answered:
		GameState.inventory.remove_at(selected)
		_rebuild()
