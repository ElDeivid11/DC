class_name UIRankBadge
extends PanelContainer
## Placa de piedra con el rango en números romanos: X (débil) → I (fuerte). El
## color sale de las variaciones RankLabel1…RankLabel10 del Theme
## (UIStyle.rank_color), nunca de valores sueltos.

var rank := 10
var _label: Label

func _init(p_rank := 10) -> void:
	theme_type_variation = "RankPlaque"
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Ancho parejo para I…X: las filas de las listas quedan alineadas.
	custom_minimum_size.x = 40
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	set_rank(p_rank)

func set_rank(p_rank: int) -> void:
	rank = clampi(p_rank, 1, 10)
	_label.theme_type_variation = "RankLabel%d" % rank
	_label.text = DataRegistry.t("ui.rank_short", [UIFormat.roman(rank)])
	tooltip_text = DataRegistry.t("ui.rank_tooltip", [rank])
