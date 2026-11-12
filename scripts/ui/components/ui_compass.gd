class_name UICompass
extends PanelContainer
## Brújula del HUD en una cinta: [O]  N  [E]. El rumbo actual va al centro
## (en vela; el Norte en rojo), los vecinos a los costados.

var left: Label
var center: Label
var right: Label

func _init() -> void:
	theme_type_variation = "RibbonSmall"
	custom_minimum_size = Vector2(156, 26)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	left = UILabel.make("", "NumSmallLabel")
	center = UILabel.make("", "NumSmallLabel")
	right = UILabel.make("", "NumSmallLabel")
	for l: Label in [left, center, right]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)

## facing: 0 N, 1 E, 2 S, 3 O (como GridPlayer).
func set_facing(facing: int) -> void:
	var keys: Array[String] = ["compass.n", "compass.e", "compass.s", "compass.o"]
	left.text = DataRegistry.t(keys[posmod(facing - 1, 4)])
	center.text = DataRegistry.t(keys[posmod(facing, 4)])
	right.text = DataRegistry.t(keys[posmod(facing + 1, 4)])
	center.add_theme_color_override("font_color", UIStyle.DANGER if posmod(facing, 4) == 0 else UIStyle.ACCENT)
