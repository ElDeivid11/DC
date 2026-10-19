class_name FloorData
extends RefCounted
## Todo lo que define un piso, ANTES de construir nada en 3D: la grilla
## (0 = piso, 1 = pared — el mismo formato que el test_map del prototipo),
## inicio, enemigos, cofres, objetos sueltos, salida y decoración.
## FloorGenerator lo produce (con semilla) y FloorBuilder lo vuelve 3D.

const FLOOR := 0
const WALL := 1

var floor_n := 1
var width := 0
var height := 0
var cells: Array = []              # cells[y][x] -> FLOOR | WALL
var start_cell := Vector2i.ZERO
var start_facing := 1              # 0 N, 1 E, 2 S, 3 O (igual que GridPlayer)
var rooms: Array[Rect2i] = []
var boss_room := Rect2i()
var exit_cell := Vector2i(-1, -1)
## {cell, species_id, rank, kind ("normal"|"elite"|"boss"), display_name,
##  soul_id, scale_mult, tint (Color)}
var enemies: Array = []
var chests: Array[Vector2i] = []
## {cell, item_id}
var items: Array = []
## Decoración (no bloquea): {prop, pos (Vector3 en mundo), rot}
var props: Array = []
## Columnas decorativas: posición en mundo (Vector3) del centro de la base.
var pillars: Array[Vector3] = []
var is_test_room := false

func is_wall(cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= height or cell.x < 0 or cell.x >= width:
		return true
	return int(cells[cell.y][cell.x]) == WALL

func set_cell(cell: Vector2i, value: int) -> void:
	cells[cell.y][cell.x] = value

func fill(w: int, h: int, value: int) -> void:
	width = w
	height = h
	cells = []
	for y in h:
		var row: Array[int] = []
		row.resize(w)
		row.fill(value)
		cells.append(row)

func floor_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in height:
		for x in width:
			if int(cells[y][x]) == FLOOR:
				out.append(Vector2i(x, y))
	return out

## Distancias BFS (en pasos) desde `from` por celdas de piso, sin pasar por
## las de `blocked`. Celdas inalcanzables no aparecen en el resultado.
func distances_from(from: Vector2i, blocked: Dictionary = {}) -> Dictionary:
	var dist := {from: 0}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n := c + d
			if is_wall(n) or dist.has(n) or blocked.has(n):
				continue
			dist[n] = int(dist[c]) + 1
			queue.append(n)
	return dist

func enemy_at(cell: Vector2i) -> Dictionary:
	for e: Dictionary in enemies:
		if e.cell == cell:
			return e
	return {}
