class_name UIStatBar
extends HBoxContainer
## Barra de HP/progreso con valor numérico: "Bjorn ▮▮▮▮▮▯ 14/18".
## kind = "hp" cambia de color según la fracción (verde → ámbar → rojo);
## "soul" / "coin" / "accent" usan un color fijo.

var kind := "hp"
var name_label: Label
var bar: ProgressBar
var value_label: Label

func _init(p_name := "", p_kind := "hp", bar_width := 120) -> void:
	kind = p_kind
	name_label = Label.new()
	name_label.text = p_name
	name_label.visible = p_name != ""
	name_label.custom_minimum_size.x = 64
	add_child(name_label)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(bar_width, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(bar)
	value_label = Label.new()
	value_label.theme_type_variation = "DetailLabel"
	value_label.custom_minimum_size.x = 52
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(value_label)
	_apply_kind(1.0)

func set_values(value: int, max_value: int) -> void:
	bar.max_value = maxi(max_value, 1)
	bar.value = clampi(value, 0, maxi(max_value, 1))
	value_label.text = "%d/%d" % [maxi(value, 0), max_value]
	_apply_kind(float(maxi(value, 0)) / float(maxi(max_value, 1)))

## Animación corta (≤ 200 ms) hacia el valor nuevo: se nota el golpe.
func animate_to(value: int, max_value: int) -> void:
	bar.max_value = maxi(max_value, 1)
	value_label.text = "%d/%d" % [maxi(value, 0), max_value]
	_apply_kind(float(maxi(value, 0)) / float(maxi(max_value, 1)))
	var tw := create_tween()
	tw.tween_property(bar, "value", float(clampi(value, 0, max_value)), UIStyle.TRANSITION)

func set_name_text(t: String) -> void:
	name_label.text = t
	name_label.visible = t != ""

func _apply_kind(fraction: float) -> void:
	match kind:
		"soul":
			bar.theme_type_variation = "SoulBar"
		"coin":
			bar.theme_type_variation = "CoinBar"
		"accent":
			bar.theme_type_variation = "AccentBar"
		_:
			if fraction > 0.5:
				bar.theme_type_variation = "HpGood"
			elif fraction > 0.25:
				bar.theme_type_variation = "HpWarn"
			else:
				bar.theme_type_variation = "HpLow"
