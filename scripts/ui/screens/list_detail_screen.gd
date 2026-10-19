class_name ListDetailScreen
extends UIScreen
## Base para pantallas "lista a la izquierda + detalle a la derecha" (Mejoras,
## Objetos y desbloqueos, Bestiario). Al enfocar un ítem de la lista se
## muestra su detalle; las subclases implementan _fill_list() y _show_detail().

var list_box: VBoxContainer
var list_scroll: ScrollContainer
var detail: UIPanel
var detail_box: VBoxContainer
var list_items: Array = []
var selected := 0

func _ready() -> void:
	super._ready()
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	body.add_child(row)
	list_scroll = ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_stretch_ratio = 1.3
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	row.add_child(list_scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", UIStyle.SPACE)
	list_scroll.add_child(list_box)
	detail = UIPanel.new("", "PanelAlt")
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.custom_minimum_size.x = 300
	row.add_child(detail)
	detail_box = detail.body
	rebuild()

func rebuild() -> void:
	for c in list_box.get_children():
		c.queue_free()
	list_items.clear()
	_fill_list()
	UIFocus.chain_vertical(list_items)
	if not list_items.is_empty():
		selected = clampi(selected, 0, list_items.size() - 1)
		(list_items[selected] as Control).call_deferred("grab_focus")
		_select(selected)

## Agrega un ítem a la lista: botón (con el foco) + etiquetas a la derecha.
func add_row(text: String, right_texts: Array, disabled_look := false) -> UIButton:
	var row := HBoxContainer.new()
	list_box.add_child(row)
	var b := UIButton.new(text, "ItemSlot")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if disabled_look:
		b.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	row.add_child(b)
	for rt: Array in right_texts:
		var l := Label.new()
		l.text = String(rt[0])
		l.theme_type_variation = String(rt[1])
		l.custom_minimum_size.x = float(rt[2]) if rt.size() > 2 else 0.0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(l)
	var idx := list_items.size()
	b.focus_entered.connect(func() -> void: _select(idx))
	b.pressed.connect(func() -> void: _activate(idx))
	list_items.append(b)
	return b

func _select(index: int) -> void:
	selected = index
	for c in detail_box.get_children():
		c.queue_free()
	_show_detail(index)

func detail_line(text: String, variation := "") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != "":
		l.theme_type_variation = variation
	detail_box.add_child(l)
	return l

# Para las subclases:
func _fill_list() -> void:
	pass

func _show_detail(_index: int) -> void:
	pass

func _activate(_index: int) -> void:
	pass
