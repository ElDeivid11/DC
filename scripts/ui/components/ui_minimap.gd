class_name UIMinimap
extends Control
## Minimapa dibujado por código: solo celdas DESCUBIERTAS (visitadas o vistas
## al pasar). Modo ventana: 11×11 centrado en el jugador (HUD). Modo completo:
## todo el piso escalado (overlay "M"). Norte siempre arriba; el jugador es
## una flecha de vela que apunta hacia donde mira. Colores de UIStyle (MAP_*)
## y marcadores del kit (map_*).

var floor_data: FloorData
var visited: Dictionary = {}
var player_cell := Vector2i.ZERO
var facing := 1
## Marcadores conocidos: {Vector2i: "chest"|"item"|"enemy"|"boss"|"exit"|"exit_open"|"door"}
## ("door", la puerta cerrada del jefe, no lleva marcador: solo la usa el HUD).
var markers: Dictionary = {}
var full_view := false
var radius := 5
var cell_px := 12

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
	draw_rect(Rect2(Vector2.ZERO, size), UIStyle.MAP_BG)
	if floor_data == null:
		return
	var px := float(cell_px)
	var origin := Vector2.ZERO
	var from := Vector2i.ZERO
	var to := Vector2i(floor_data.width - 1, floor_data.height - 1)
	if full_view:
		px = floorf(minf(size.x / floor_data.width, size.y / floor_data.height) / 2.0) * 2.0
		origin = ((size - Vector2(floor_data.width, floor_data.height) * px) / 4.0).round() * 2.0
	else:
		from = player_cell - Vector2i(radius, radius)
		to = player_cell + Vector2i(radius, radius)
		origin = -Vector2(from) * px
	var gap := float(UIStyle.PIXEL_SCALE)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var c := Vector2i(x, y)
			var r := Rect2(origin + Vector2(c) * px, Vector2(px - gap, px - gap))
			if visited.has(c):
				draw_rect(r, UIStyle.MAP_FLOOR)
			elif _touches_visited(c) and floor_data.is_wall(c):
				draw_rect(r, UIStyle.MAP_WALL)
	for c: Vector2i in markers.keys():
		if not full_view and (absi(c.x - player_cell.x) > radius or absi(c.y - player_cell.y) > radius):
			continue
		var sprite := _marker_sprite(String(markers[c]))
		if sprite == "":
			continue
		_draw_marker(sprite, origin + Vector2(c) * px, px - gap, 0)
	_draw_marker("map_player", origin + Vector2(player_cell) * px, px - gap, facing)

## Marcadores del kit (5×5 píxeles de arte), centrados en la celda.
static func _marker_sprite(kind: String) -> String:
	match kind:
		"chest", "item":
			return "map_chest"
		"enemy", "boss":
			return "map_enemy"
		"exit":
			return "map_exit"
		"exit_open":
			return "map_stairs"
	return ""

func _draw_marker(sprite: String, cell_pos: Vector2, cell_size: float, turns: int) -> void:
	var tex := UIIcon.kit_texture(sprite)
	if tex == null:
		return
	var center := cell_pos + Vector2(cell_size, cell_size) / 2.0
	var half := (tex.get_size() / 2.0).round()
	# El jugador gira de a 90° (0 N, 1 E, 2 S, 3 O): sin pérdida de píxeles.
	draw_set_transform(center.round(), turns * PI / 2.0, Vector2.ONE)
	draw_texture(tex, -half)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _touches_visited(c: Vector2i) -> bool:
	for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		if visited.has(c + d):
			return true
	return false
