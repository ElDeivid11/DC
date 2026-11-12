class_name InventoryScreen
extends UIScreen
## Inventario de la run (I / X): el morral como nichos de piedra a la
## izquierda (4 por fila), detalle del objeto enfocado a la derecha (retrato,
## tipo, descripción) y acciones Descartar / Usar. Enter / A sobre un nicho
## usa el objeto directamente. Los objetos se pierden al terminar la run. El
## uso real lo resuelve RunController.use_item_field().

const COLUMNS := 4

var run: Node
var grid: GridContainer
var count_label: Label
var detail_box: VBoxContainer
var detail_portrait: UIPortrait
var detail_name: Label
var detail_tag_box: HBoxContainer
var detail_text: Label
var detail_usage: Label
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

	# Morral: «Morral 4/8» y los nichos.
	var bag := PanelContainer.new()
	bag.theme_type_variation = "PanelAlt"
	row.add_child(bag)
	var bag_box := VBoxContainer.new()
	bag_box.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	bag.add_child(bag_box)
	var bag_head := HBoxContainer.new()
	bag_head.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	bag_head.add_child(UIIcon.make("inventario", "bronce"))
	var bag_title := UILabel.make(DataRegistry.t("inventory.bag"), "HeadLabel")
	bag_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bag_head.add_child(bag_title)
	count_label = UILabel.make("", "NumLabel")
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bag_head.add_child(count_label)
	bag_box.add_child(bag_head)
	bag_box.add_child(UIDivider.new(COLUMNS * int(UIItemSlot.NICHE_SIZE.x) + (COLUMNS - 1) * UIStyle.SPACE * 2))
	grid = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", UIStyle.SPACE * 2)
	grid.add_theme_constant_override("v_separation", UIStyle.SPACE * 2)
	bag_box.add_child(grid)

	# Detalle del objeto.
	var detail := PanelContainer.new()
	detail.theme_type_variation = "PanelAlt"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	detail.add_child(detail_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	detail_box.add_child(head)
	detail_portrait = UIPortrait.new(null, 128)
	head.add_child(detail_portrait)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	head.add_child(info)
	detail_name = UILabel.make("", "HeadLabel")
	info.add_child(detail_name)
	var rule := UIDivider.new(240)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_child(rule)
	detail_tag_box = HBoxContainer.new()
	info.add_child(detail_tag_box)
	detail_text = UILabel.make("", "", true)
	detail_box.add_child(detail_text)
	detail_usage = UILabel.make("", "DetailLabel", true)
	detail_box.add_child(detail_usage)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_box.add_child(spacer)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	detail_box.add_child(actions)
	drop_btn = UIButton.make(DataRegistry.t("inventory.drop"), _drop, "DangerButton")
	drop_btn.custom_minimum_size.x = 160
	actions.add_child(drop_btn)
	use_btn = UIButton.make(DataRegistry.t("inventory.use"), _use)
	use_btn.custom_minimum_size.x = 160
	actions.add_child(use_btn)

	add_footer_hint(DataRegistry.t("inventory.press_hint"))
	add_footer_button(DataRegistry.t("ui.close"), close)
	_rebuild()

func _rebuild() -> void:
	for c in grid.get_children():
		c.queue_free()
	var first: Control = null
	for i in GameState.inventory_capacity():
		var id := GameState.inventory[i] if i < GameState.inventory.size() else ""
		var slot := UIItemSlot.new(id, false, true)
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
	count_label.text = "%d/%d" % [GameState.inventory.size(), GameState.inventory_capacity()]
	if first:
		first.call_deferred("grab_focus")
		_select(0)
	else:
		_select(-1)
		footer.get_child(footer.get_child_count() - 1).call_deferred("grab_focus")

func _select(index: int) -> void:
	selected = index
	for c in detail_tag_box.get_children():
		c.queue_free()
	if index < 0 or index >= GameState.inventory.size():
		detail_name.text = DataRegistry.t("inventory.empty_title")
		detail_portrait.set_texture(null)
		detail_text.text = DataRegistry.t("inventory.empty")
		detail_usage.text = ""
		use_btn.disabled = true
		drop_btn.disabled = true
		return
	var it := DataRegistry.get_item(GameState.inventory[index])
	detail_name.text = String(it.nombre)
	detail_portrait.set_texture(UIPortrait.item_texture(GameState.inventory[index]))
	detail_tag_box.add_child(UIItemSlot.type_plate(String(it.tipo)))
	var where: Array[String] = []
	if it.efecto.fuera_combate:
		where.append(DataRegistry.t("inventory.where_field"))
	if it.efecto.en_combate:
		where.append(DataRegistry.t("inventory.where_combat"))
	detail_usage.text = DataRegistry.t("inventory.passive_note") if it.tipo == "pasivo" else DataRegistry.t("inventory.usable_in", [" / ".join(where)])
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
		SceneRouter.play_ui("item")
		_rebuild()
