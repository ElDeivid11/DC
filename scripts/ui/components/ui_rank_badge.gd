class_name UIRankBadge
extends PanelContainer
## Insignia de rango "R9": 10 (débil, apagado) → 1 (fuerte, rojo). El color
## sale de UIStyle.rank_color(), no de valores sueltos.

var rank := 10
var _label: Label

func _init(p_rank := 10) -> void:
	_label = Label.new()
	_label.theme_type_variation = "DetailLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	set_rank(p_rank)

func set_rank(p_rank: int) -> void:
	rank = p_rank
	var c := UIStyle.rank_color(rank)
	var box := StyleBoxFlat.new()
	box.bg_color = UIStyle.BG_DEEP
	box.border_color = c
	box.set_border_width_all(UIStyle.BORDER_W)
	box.anti_aliasing = false
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	add_theme_stylebox_override("panel", box)
	_label.text = DataRegistry.t("ui.rank_short", [rank])
	_label.add_theme_color_override("font_color", c)
	tooltip_text = DataRegistry.t("ui.rank_tooltip", [rank])
