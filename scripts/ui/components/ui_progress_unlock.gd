class_name UIProgressUnlock
extends VBoxContainer
## Progreso de un desbloqueo: texto de la condición + barra + "7/10".

var label: Label
var bar: ProgressBar
var count_label: Label

func _init(text := "", current := 0, target := 1) -> void:
	add_theme_constant_override("separation", UIStyle.SPACE)
	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = "DimLabel"
	add_child(label)
	var row := HBoxContainer.new()
	add_child(row)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.theme_type_variation = "CoinBar"
	bar.custom_minimum_size = Vector2(160, 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	count_label = Label.new()
	count_label.theme_type_variation = "NumSmallLabel"
	count_label.custom_minimum_size.x = 48
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(count_label)
	set_progress(text, current, target)

func set_progress(text: String, current: int, target: int) -> void:
	label.text = text
	label.visible = text != ""
	bar.max_value = maxi(target, 1)
	bar.value = clampi(current, 0, maxi(target, 1))
	count_label.text = "%d/%d" % [mini(current, target), target]
	bar.theme_type_variation = "SoulBar" if current >= target else "CoinBar"
