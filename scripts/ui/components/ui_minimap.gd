class_name UIMinimap
extends Control
## Minimapa dibujado por código: solo celdas DESCUBIERTAS (visitadas o vistas
## al pasar). Modo ventana: 7×7 centrado en el jugador (HUD). Modo completo:
## todo el piso escalado (overlay "M"). Norte siempre arriba; el jugador es
## un triángulo ámbar que apunta hacia donde mira.

var floor_data: FloorData
var visited: Dictionary = {}
var player_cell := Vector2i.ZERO
var facing := 1
## Marcadores conocidos: {Vector2i: "chest"|"item"|"enemy"|"boss"|"exit"|"exit_open"}
var markers: Dictionary = {}
var full_view := false
var radius := 3
var cell_px := 14

func _init(p_full := false) -> void:
	full_view = p_full
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not full_view:
		custom_minimum_size = Vector2((radius * 2 + 1) * cell_px, (radius * 2 + 1) * cell_px)

func update_view(fd: FloorData, p_visited: Dictionary, cell: Vector2i, p_facing: int, p_markers: Dictionary) -> void:
	floor_data = fd
	visited = p_visited
	player_cell = cell
	facing = p_facing
	markers = p_markers
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UIStyle.BG_DEEP)
	if floor_data == null:
		return
	var px := float(cell_px)
	var origin := Vector2.ZERO
	var from := Vector2i.ZERO
	var to := Vector2i(floor_data.width - 1, floor_data.height - 1)
	if full_view:
		px = floorf(minf(size.x / floor_data.width, size.y / floor_data.height))
		origin = (size - Vector2(floor_data.width, floor_data.height) * px) / 2.0
	else:
		from = player_cell - Vector2i(radius, radius)
		to = player_cell + Vector2i(radius, radius)
		origin = -Vector2(from) * px
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var c := Vector2i(x, y)
			var r := Rect2(origin + Vector2(c) * px, Vector2(px, px))
			if visited.has(c):
				draw_rect(r.grow(-1), UIStyle.TEXT_DIM.darkened(0.25))
			elif _touches_visited(c) and floor_data.is_wall(c):
				draw_rect(r.grow(-1), UIStyle.BORDER.darkened(0.25))
	for c: Vector2i in markers.keys():
		if not full_view and (absi(c.x - player_cell.x) > radius or absi(c.y - player_cell.y) > radius):
			continue
		var center := origin + (Vector2(c) + Vector2(0.5, 0.5)) * px
		var kind := String(markers[c])
		match kind:
			"chest":
				draw_rect(Rect2(center - Vector2(px, px) * 0.3, Vector2(px, px) * 0.6), UIStyle.COIN)
			"item":
				draw_circle(center, px * 0.22, UIStyle.ACCENT)
			"enemy":
				draw_circle(center, px * 0.3, UIStyle.DANGER)
			"boss":
				draw_circle(center, px * 0.42, UIStyle.DANGER)
				draw_circle(center, px * 0.2, UIStyle.BG_DEEP)
			"exit":
				draw_rect(Rect2(center - Vector2(px, px) * 0.35, Vector2(px, px) * 0.7), UIStyle.DANGER, false, 2.0)
			"exit_open":
				draw_rect(Rect2(center - Vector2(px, px) * 0.35, Vector2(px, px) * 0.7), UIStyle.SOUL)
	# Jugador: triángulo hacia donde mira (0 N, 1 E, 2 S, 3 O).
	var pc := origin + (Vector2(player_cell) + Vector2(0.5, 0.5)) * px
	var dirs: Array[Vector2] = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	var f := dirs[facing]
	var side := Vector2(-f.y, f.x)
	var tip := pc + f * px * 0.42
	var base_a := pc - f * px * 0.3 + side * px * 0.32
	var base_b := pc - f * px * 0.3 - side * px * 0.32
	draw_colored_polygon(PackedVector2Array([tip, base_a, base_b]), UIStyle.ACCENT)
	draw_rect(Rect2(Vector2.ZERO, size), UIStyle.BORDER, false, 2.0)

func _touches_visited(c: Vector2i) -> bool:
	for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		if visited.has(c + d):
			return true
	return false
