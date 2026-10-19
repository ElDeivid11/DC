extends Node3D
## Controlador de movimiento en grilla estilo blobber (Vampire Crawlers / Wizardry / Might and Magic).
## Pasos y giros discretos de 90°, con interpolación suave entre celdas (sin física libre).

const CELL_SIZE := 2.0
const MOVE_TIME := 0.15
const TURN_TIME := 0.12

var grid_pos := Vector2i(0, 0)
var facing := 0 # 0 = norte (-Z), 1 = este (+X), 2 = sur (+Z), 3 = oeste (-X)
var is_moving := false
var input_locked := false # se activa durante el combate, para que no puedas moverte
var dungeon: Node = null # referencia al generador, para chequear paredes/enemigos

# Vectores de dirección en el mismo orden que "facing" (0..3)
# Tipado explícito como Array[Vector2i]: sin esto, Godot no puede inferir
# el tipo al usar DIRS[facing] más abajo (error "Cannot infer the type").
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

func setup(start_pos: Vector2i, dungeon_ref: Node, start_facing: int = 0) -> void:
	grid_pos = start_pos
	dungeon = dungeon_ref
	facing = start_facing
	rotation_degrees.y = -facing * 90.0
	position = Vector3(grid_pos.x * CELL_SIZE, 1.0, grid_pos.y * CELL_SIZE)

func set_input_locked(locked: bool) -> void:
	input_locked = locked

func _unhandled_input(event: InputEvent) -> void:
	if is_moving or input_locked:
		return
	# Controles: flechas del teclado (acciones ui_* built-in de Godot)
	if event.is_action_pressed("ui_up"):
		_try_move(1)
	elif event.is_action_pressed("ui_down"):
		_try_move(-1)
	elif event.is_action_pressed("ui_left"):
		_turn(-1)
	elif event.is_action_pressed("ui_right"):
		_turn(1)

func _try_move(dir_mult: int) -> void:
	var target := grid_pos + DIRS[facing] * dir_mult
	if dungeon and dungeon.is_wall(target):
		return # bloqueado por pared — aquí después se puede sumar feedback (sonido/shake)
	if dungeon and dungeon.has_method("get_enemy_at") and dungeon.get_enemy_at(target):
		dungeon.start_combat(target, self) # "chocar" con el enemigo dispara el combate
		return
	grid_pos = target
	var target_world := Vector3(grid_pos.x * CELL_SIZE, position.y, grid_pos.y * CELL_SIZE)
	is_moving = true
	var tween := create_tween()
	tween.tween_property(self, "position", target_world, MOVE_TIME)
	tween.finished.connect(func(): is_moving = false)

func _turn(step: int) -> void:
	facing = posmod(facing + step, 4)
	is_moving = true
	var tween := create_tween()
	# Godot rota positivo en sentido antihorario visto desde arriba, al revés
	# del orden N→E→S→O usado en DIRS — por eso el signo va invertido (-step)
	# para que "derecha" gire visualmente hacia donde el jugador espera.
	tween.tween_property(self, "rotation_degrees:y", rotation_degrees.y - step * 90.0, TURN_TIME)
	tween.finished.connect(func(): is_moving = false)
