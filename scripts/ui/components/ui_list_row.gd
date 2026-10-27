class_name UIListRow
extends UIButton
## Fila de lista del grimorio (Mejoras, Objetos, Bestiario, personajes):
## [llama si tiene foco] [ícono o retrato 32] Nombre ....... [columnas]
## Con foco, el nombre pasa a vela y el ícono a su rampa encendida. Bloqueada:
## texto apagado (variación ItemSlotLocked).

const HEIGHT := 44

var row: HBoxContainer
var cursor: UIFlameCursor
var icon_rect: UIIcon
var picture: TextureRect
var name_label: Label
var locked := false

func _init(p_text := "", icon_id := "", picture_texture: Texture2D = null) -> void:
	super("", "ItemSlot")
	custom_minimum_size.y = HEIGHT
	row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -12
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	cursor = UIFlameCursor.new()
	row.add_child(cursor)
	if icon_id != "":
		icon_rect = UIIcon.make(icon_id)
		row.add_child(icon_rect)
	elif picture_texture != null:
		picture = TextureRect.new()
		picture.texture = picture_texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size = Vector2(UIStyle.ICON_SIZE, UIStyle.ICON_SIZE)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(picture)
	name_label = UILabel.make(p_text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.clip_text = true
	row.add_child(name_label)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	pressed.connect(func() -> void: cursor.flash())
	_refresh()

## Columna a la derecha del nombre (pips, costo, conteo...). No captura el mouse.
func add_column(c: Control) -> Control:
	_ignore_mouse(c)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(c)
	return c

static func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

func set_text_label(t: String) -> void:
	name_label.text = t

func set_locked(on: bool) -> void:
	locked = on
	theme_type_variation = "ItemSlotLocked" if on else "ItemSlot"
	if picture:
		picture.modulate = UIStyle.FALLEN_TINT if on else Color.WHITE
	_refresh()

func _refresh() -> void:
	var focused := has_focus()
	cursor.modulate.a = 1.0 if focused else 0.0
	if focused:
		name_label.add_theme_color_override("font_color", UIStyle.ACCENT)
	elif locked:
		name_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	else:
		name_label.remove_theme_color_override("font_color")
	if icon_rect:
		icon_rect.set_ramp("vela" if focused else ("apagado" if locked else "bronce"))
