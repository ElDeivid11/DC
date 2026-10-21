class_name UICoinPlate
extends PanelContainer
## Placa de monedas: [ícono de monedas] 1.240 en cifras doradas. Va arriba a
## la derecha en las pantallas (UIScreen.show_coins) y en el Hub.

var label: Label

func _init(big := false) -> void:
	theme_type_variation = "HudPanel"
	size_flags_horizontal = Control.SIZE_SHRINK_END
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	row.add_child(UIIcon.make("monedas", "moneda"))
	label = Label.new()
	label.theme_type_variation = "CoinBigLabel" if big else "CoinLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 96 if big else 72
	row.add_child(label)

func set_amount(amount: int) -> void:
	label.text = UIFormat.number(amount)
