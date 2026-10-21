class_name UIStatRadar
extends Control
## Gráfica hexagonal de las 6 estadísticas de un personaje (VIT arriba y en
## sentido horario, el orden de RunRules.STATS). `values` son los puntos ya
## asignados; `preview`, los que se están repartiendo y todavía no se
## confirmaron: se dibujan encima con un contorno de vela. La escala crece
## con el valor más alto (mínimo SCALE_MIN: con pocos puntos la forma ya se
## ve), y un valor 0 igual deja un hexágono chico en el centro, para que la
## forma siempre se lea.

const RINGS := 4
const SCALE_MIN := 6
const CORE := 0.08 # fracción del radio que ocupa un valor 0

var values: Dictionary = {}
var preview: Dictionary = {}

func _init(side := 220) -> void:
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_values(p_values: Dictionary, p_preview: Dictionary = {}) -> void:
	values = p_values
	preview = p_preview
	queue_redraw()

func _scale_max() -> int:
	var top := SCALE_MIN
	for id in RunRules.STATS:
		top = maxi(top, int(values.get(id, 0)) + int(preview.get(id, 0)))
	return top

func _point(center: Vector2, radius: float, i: int, fraction: float) -> Vector2:
	var angle := -PI / 2.0 + TAU * i / RunRules.STATS.size()
	return center + Vector2(cos(angle), sin(angle)) * radius * fraction

func _shape(center: Vector2, radius: float, stat_values: Dictionary, extra: Dictionary) -> PackedVector2Array:
	var top := float(_scale_max())
	var pts := PackedVector2Array()
	for i in RunRules.STATS.size():
		var id := RunRules.STATS[i]
		var v := float(int(stat_values.get(id, 0)) + int(extra.get(id, 0)))
		pts.append(_point(center, radius, i, CORE + (1.0 - CORE) * v / top))
	return pts

func _draw() -> void:
	var font := get_theme_font("font", "NumSmallLabel")
	var font_size := get_theme_font_size("font_size", "NumSmallLabel")
	var center := (size / 2.0 / 2.0).round() * 2.0
	var radius := minf(size.x, size.y) / 2.0 - font_size * 1.6
	var n := RunRules.STATS.size()
	# Anillos guía discontinuos y ejes, en bronce oscuro.
	for ring in range(1, RINGS + 1):
		for i in n:
			var a := _point(center, radius, i, float(ring) / RINGS)
			var b := _point(center, radius, (i + 1) % n, float(ring) / RINGS)
			draw_dashed_line(a, b, UIStyle.BRONZE_DARK, 2.0, 4.0)
	for i in n:
		draw_line(center, _point(center, radius, i, 1.0), UIStyle.BRONZE_DARK, 2.0)
	# Valores confirmados (amatista, como la EXP).
	var current := _shape(center, radius, values, {})
	draw_colored_polygon(current, Color(UIStyle.XP, 0.35))
	var outline := current.duplicate()
	outline.append(current[0])
	draw_polyline(outline, UIStyle.XP, 2.0)
	# Reparto pendiente: contorno de vela discontinuo.
	var pending := false
	for id in RunRules.STATS:
		pending = pending or int(preview.get(id, 0)) > 0
	if pending:
		var next := _shape(center, radius, values, preview)
		for i in n:
			draw_dashed_line(next[i], next[(i + 1) % n], UIStyle.ACCENT, 2.0, 4.0)
	# Siglas: "VIT 3" (en vela las que están por subir).
	for i in n:
		var id := RunRules.STATS[i]
		var text := "%s %d" % [DataRegistry.t("stats.%s.short" % id), int(values.get(id, 0)) + int(preview.get(id, 0))]
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var at := _point(center, radius + font_size * 0.9, i, 1.0)
		var pos := (at - Vector2(text_size.x / 2.0, -font_size / 3.0)).round()
		var color := UIStyle.ACCENT if int(preview.get(id, 0)) > 0 else UIStyle.TEXT_DIM
		draw_string(font, pos + Vector2(2, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UIStyle.INK)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
