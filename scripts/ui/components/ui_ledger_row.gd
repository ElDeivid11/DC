class_name UILedgerRow
extends HBoxContainer
## Fila de libro de cuentas: [ícono] Etiqueta ·········· +48
## Los puntos guía se dibujan en bloques de 2 px sobre la línea base.

var label: Label
var value_label: Label

func _init(text := "", value := "", value_variation := "NumLabel", icon_id := "", ramp := "bronce") -> void:
	add_theme_constant_override("separation", 8)
	if icon_id != "":
		add_child(UIIcon.make(icon_id, ramp))
	label = UILabel.make(text)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(label)
	var dots := _Dots.new()
	dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(dots)
	value_label = UILabel.make(value, value_variation)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(value_label)

func set_value(value: String) -> void:
	value_label.text = value

class _Dots extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(24, 20)

	func _draw() -> void:
		var y := roundf(size.y * 0.7 / 2.0) * 2.0
		var x := 4.0
		while x < size.x - 4.0:
			draw_rect(Rect2(x, y, 2, 2), UIStyle.TEXT_OFF)
			x += 6.0
