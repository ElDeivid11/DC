class_name UIStatRadar
extends Control
## Gráfica hexagonal de las 6 estadísticas de un personaje (VIT arriba y en
## sentido horario, el orden de RunRules.STATS). `values` son los puntos ya
## asignados; `preview`, los que se están repartiendo y todavía no se
## confirmaron: se dibujan encima con el color de "bueno". La escala crece
## con el valor más alto (mínimo SCALE_MIN), y un valor 0 igual deja un
## hexágono chico en el centro, para que la forma siempre se lea.

const RINGS := 4
const SCALE_MIN := 10
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
	var font := get_theme_font("font", "Label")
	var font_size := get_theme_font_size("font_size", "DetailLabel")
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - font_size * 2.0
	var n := RunRules.STATS.size()
	# Anillos y ejes.
	for ring in range(1, RINGS + 1):
		var poly := PackedVector2Array()
		for i in n + 1:
			poly.append(_point(center, radius, i % n, float(ring) / RINGS))
		draw_polyline(poly, UIStyle.BORDER, 1.0)
	for i in n:
		draw_line(center, _point(center, radius, i, 1.0), UIStyle.BORDER, 1.0)
	# Valores confirmados.
	var current := _shape(center, radius, values, {})
	draw_colored_polygon(current, Color(UIStyle.SOUL, 0.35))
	var outline := current.duplicate()
	outline.append(current[0])
	draw_polyline(outline, UIStyle.SOUL, 2.0)
	# Reparto pendiente (si hay).
	var pending := false
	for id in RunRules.STATS:
		pending = pending or int(preview.get(id, 0)) > 0
	if pending:
		var next := _shape(center, radius, values, preview)
		var next_outline := next.duplicate()
		next_outline.append(next[0])
		draw_polyline(next_outline, UIStyle.GOOD, 2.0)
	# Etiquetas: "VIT 3" (en ámbar las que están por subir).
	for i in n:
		var id := RunRules.STATS[i]
		var text := "%s %d" % [DataRegistry.t("stats.%s.short" % id), int(values.get(id, 0)) + int(preview.get(id, 0))]
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var at := _point(center, radius + font_size * 1.1, i, 1.0)
		var pos := at - Vector2(text_size.x / 2.0, -font_size / 2.5)
		var color := UIStyle.GOOD if int(preview.get(id, 0)) > 0 else UIStyle.TEXT
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
