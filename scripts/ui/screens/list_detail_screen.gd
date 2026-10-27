class_name ListDetailScreen
extends UIScreen
## Base para pantallas "lista a la izquierda + detalle a la derecha" (Mejoras,
## Objetos y desbloqueos, Bestiario). La lista son filas UIListRow (cursor de
## llama, ícono o retrato, columnas); al enfocar una se muestra su detalle.
## Las subclases implementan _fill_list() y _show_detail().

const LIST_WIDTH := 560

var list_box: VBoxContainer
var list_scroll: ScrollContainer
var detail: UIPanel
var detail_box: VBoxContainer
## Retrato del encabezado del detalle (si la subclase pidió uno).
var detail_portrait: UIPortrait
var list_items: Array = []
var selected := 0

func _ready() -> void:
	super._ready()
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	body.add_child(row)
	var list_panel := PanelContainer.new()
	list_panel.theme_type_variation = "PanelAlt"
	list_panel.custom_minimum_size.x = LIST_WIDTH
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_stretch_ratio = 1.15
	row.add_child(list_panel)
	list_scroll = ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	list_panel.add_child(list_scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", UIStyle.SPACE)
	list_scroll.add_child(list_box)
	detail = UIPanel.new("", "PanelAlt")
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.custom_minimum_size.x = 360
	row.add_child(detail)
	detail_box = detail.body
	detail_box.add_theme_constant_override("separation", UIStyle.SPACE * 2)
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

## Agrega una fila: [llama] [ícono o retrato] Nombre ..... [columnas].
func add_row(text: String, columns: Array = [], locked := false, icon_id := "", picture: Texture2D = null) -> UIListRow:
	var b := UIListRow.new(text, icon_id, picture)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c: Variant in columns:
		if c is Control:
			b.add_column(c as Control)
	if locked:
		b.set_locked(true)
	var idx := list_items.size()
	b.focus_entered.connect(func() -> void: _select(idx))
	b.pressed.connect(func() -> void: _activate(idx))
	list_box.add_child(b)
	list_items.append(b)
	return b

## Etiqueta para una columna de fila (ancho fijo, alineada a la derecha).
static func col(text: String, variation := "", width := 0) -> Label:
	var l := UILabel.make(text, variation)
	l.custom_minimum_size.x = width
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l

## Costo en monedas: [ícono] 80 (en rojo si no alcanza).
static func coin_cost(amount: int, affordable := true) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(UIIcon.make("monedas", "moneda"))
	var l := col(UIFormat.number(amount), "CoinLabel" if affordable else "CoinDangerLabel", 56)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(l)
	return box

func _select(index: int) -> void:
	selected = index
	detail_portrait = null
	for c in detail_box.get_children():
		c.queue_free()
	_show_detail(index)

## Encabezado del detalle: [retrato grande o ícono] Título / filete. Devuelve
## la columna de la derecha para agregarle más cosas (placa de tipo, rango...).
func detail_header(title: String, picture: Texture2D = null, icon_id := "", icon_ramp := "vela") -> VBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	detail_box.add_child(row)
	if picture != null:
		detail_portrait = UIPortrait.new(picture, 128)
		row.add_child(detail_portrait)
	elif icon_id != "":
		var holder := PanelContainer.new()
		holder.theme_type_variation = "PortraitFrame"
		holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		holder.add_child(UIIcon.make(icon_id, icon_ramp, 64))
		row.add_child(holder)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	row.add_child(info)
	var head := UILabel.make(title, "HeadLabel")
	info.add_child(head)
	var rule := UIDivider.new(240)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_child(rule)
	return info

func detail_line(text: String, variation := "") -> Label:
	var l := UILabel.make(text, variation, true)
	detail_box.add_child(l)
	return l

## Empuja lo que siga al fondo del panel de detalle (p. ej. el botón).
func detail_spacer() -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_box.add_child(spacer)

# Para las subclases:
func _fill_list() -> void:
	pass

func _show_detail(_index: int) -> void:
	pass

func _activate(_index: int) -> void:
	pass
