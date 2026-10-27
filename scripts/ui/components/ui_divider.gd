class_name UIDivider
extends Control
## Filete con rombo central (como en un manuscrito): continuo en el 55% del
## centro, de a puntos hasta el 80% y cada vez más espaciado hacia los
## extremos. Todo en bloques de 2 px (1 píxel de arte).

const HEIGHT := 10

func _init(width := 360) -> void:
	custom_minimum_size = Vector2(width, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER

func _draw() -> void:
	var px := UIStyle.PIXEL_SCALE
	var cells := int(size.x / px)
	var mid := cells / 2.0
	var y := 2 * px
	for i in cells:
		var d := absf(i + 0.5 - mid) / maxf(mid, 1.0)
		var on := false
		if d < 0.55:
			on = true
		elif d < 0.8:
			on = i % 2 == 0
		else:
			on = i % 3 == 0
		if not on:
			continue
		draw_rect(Rect2(i * px, y, px, px), UIStyle.BRONZE)
		if d < 0.55:
			draw_rect(Rect2(i * px, y + px, px, px), UIStyle.BRONZE_DARK)
	var gem := UIIcon.kit_texture("divider_gem")
	if gem:
		var pos := Vector2(roundf((size.x - gem.get_width()) / 2.0 / px) * px, 0)
		draw_texture(gem, pos)
