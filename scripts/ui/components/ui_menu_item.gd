class_name UIMenuItem
extends UIButton
## Ítem de menú del grimorio (Hub, pausa): sin caja. Adentro: cursor de llama
## (solo con foco), ícono del kit y el texto en gótica. El foco suma una banda
## de brasa que se desvanece (estilo "focus" de la variación MenuItem).
##   UIMenuItem.make_item("Mejoras", _abrir, "mejoras")
##   UIMenuItem.make_item("Abandonar", _abandonar, "retiro", true)   # peligro

const MIN_SIZE := Vector2(440, 48)

var label_text := ""
var icon_id := ""
var danger := false
var cursor: UIFlameCursor
var icon_rect: UIIcon
var label: UIGothicLabel
var _last_state := -1

func _init(p_text := "", p_icon_id := "", p_danger := false) -> void:
	super("", "MenuItem")
	label_text = p_text
	icon_id = p_icon_id
	danger = p_danger
	custom_minimum_size = MIN_SIZE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 4
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	cursor = UIFlameCursor.new()
	row.add_child(cursor)
	icon_rect = UIIcon.make(icon_id)
	icon_rect.visible = icon_id != ""
	row.add_child(icon_rect)
	label = UIGothicLabel.new(label_text)
	row.add_child(label)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	pressed.connect(func() -> void: cursor.flash())
	_refresh()

static func make_item(p_text: String, on_pressed: Callable, p_icon_id := "", p_danger := false) -> UIMenuItem:
	var b := UIMenuItem.new(p_text, p_icon_id, p_danger)
	b.pressed.connect(on_pressed)
	return b

func set_label(t: String) -> void:
	label_text = t
	label.set_text(t)

## Button se redibuja al cambiar `disabled`: ahí se actualiza el aspecto.
func _draw() -> void:
	var state := _state()
	if state != _last_state:
		_refresh()

func _state() -> int:
	return (1 if has_focus() else 0) + (2 if disabled else 0)

func _refresh() -> void:
	_last_state = _state()
	var focused := has_focus()
	cursor.modulate.a = 1.0 if focused else 0.0
	if disabled:
		icon_rect.set_ramp("apagado")
		label.set_colors(UIStyle.TEXT_OFF, UIStyle.TEXT_OFF)
	elif focused:
		icon_rect.set_ramp("vela")
		label.set_colors(UIStyle.ACCENT, UIStyle.VELA_BLANCA)
	elif danger:
		icon_rect.set_ramp("sangre" if UIIcon.texture_for(icon_id, "sangre") else "bronce")
		label.set_colors(UIStyle.DANGER, UIStyle.DANGER)
	else:
		icon_rect.set_ramp("bronce")
		label.set_colors(UIStyle.TEXT, UIStyle.CAPITAL)
