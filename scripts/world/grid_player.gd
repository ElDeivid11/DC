extends Node3D
## Controlador de movimiento en grilla estilo blobber (Vampire Crawlers / Wizardry / Might and Magic).
## Pasos y giros discretos de 90°, con interpolación suave entre celdas (sin física libre).
##
## Controles: acciones de Controls (flechas o WASD, cruceta o stick del mando).
## El "dungeon" (RunController) decide qué bloquea: paredes, cofres, enemigos.

const CELL_SIZE := 2.0
## Pausado y "pesado", como King's Field / Lunacid.
const MOVE_TIME := 0.22
const TURN_TIME := 0.16
const EYE_HEIGHT := 1.0

## Terminó un paso: la run reacciona (recoger objetos, salida, turno enemigo).
signal moved(cell: Vector2i)
signal turned(facing: int)
## Intentó avanzar contra algo que bloquea (pared/cofre): feedback.
signal bumped(cell: Vector2i)

var grid_pos := Vector2i(0, 0)
var facing := 0 # 0 = norte (-Z), 1 = este (+X), 2 = sur (+Z), 3 = oeste (-X)
var is_moving := false
var input_locked := false # se activa durante el combate y los menús, para que no puedas moverte
var dungeon: Node = null # referencia a la run, para chequear paredes/enemigos
## Cuánto baja la cámara a mitad de cada paso (0 = sin balanceo). Lo fija la run.
var bob_amount := 0.0

# Vectores de dirección en el mismo orden que "facing" (0..3)
# Tipado explícito como Array[Vector2i]: sin esto, Godot no puede inferir
# el tipo al usar DIRS[facing] más abajo (error "Cannot infer the type").
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Centro de la celda en el mundo (los cubos de LevelBlock van de x*2 a x*2+2).
static func cell_to_world(cell: Vector2i, y: float) -> Vector3:
	return FloorBuilder.cell_to_world(cell, y)

func setup(start_pos: Vector2i, dungeon_ref: Node, start_facing: int = 0) -> void:
	grid_pos = start_pos
	dungeon = dungeon_ref
	facing = start_facing
	rotation_degrees.y = -facing * 90.0
	position = cell_to_world(grid_pos, EYE_HEIGHT)

func set_input_locked(locked: bool) -> void:
	input_locked = locked

func facing_cell() -> Vector2i:
	return grid_pos + DIRS[facing]

func _unhandled_input(event: InputEvent) -> void:
	if is_moving or input_locked:
		return
	if event.is_action_pressed("move_forward"):
		_try_move(1)
	elif event.is_action_pressed("move_back"):
		_try_move(-1)
	elif event.is_action_pressed("turn_left"):
		_turn(-1)
	elif event.is_action_pressed("turn_right"):
		_turn(1)

func _try_move(dir_mult: int) -> void:
	var target := grid_pos + DIRS[facing] * dir_mult
	if dungeon and dungeon.has_method("get_enemy_at") and dungeon.get_enemy_at(target):
		dungeon.start_combat(target, self) # "chocar" con el enemigo dispara el combate
		return
	if dungeon and dungeon.has_method("try_interact") and dungeon.try_interact(target, self):
		return # cofre, salida sellada... (la run decide)
	if dungeon and dungeon.is_wall(target):
		bumped.emit(target)
		return
	grid_pos = target
	var target_world := cell_to_world(grid_pos, position.y)
	is_moving = true
	var tween := create_tween()
	tween.tween_property(self, "position", target_world, MOVE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if bob_amount > 0.0:
		# Una sola bajada por paso, sin balanceo lateral (no marea).
		tween.parallel().tween_method(_set_bob, 0.0, 1.0, MOVE_TIME)
	tween.finished.connect(func() -> void:
		is_moving = false
		moved.emit(grid_pos)
	)

func _set_bob(t: float) -> void:
	var cam := get_child(0) as Camera3D
	if cam:
		cam.position.y = -bob_amount * sin(PI * t)

func _turn(step: int) -> void:
	facing = posmod(facing + step, 4)
	is_moving = true
	var tween := create_tween()
	# Godot rota positivo en sentido antihorario visto desde arriba, al revés
	# del orden N→E→S→O usado en DIRS — por eso el signo va invertido (-step)
	# para que "derecha" gire visualmente hacia donde el jugador espera.
	tween.tween_property(self, "rotation_degrees:y", rotation_degrees.y - step * 90.0, TURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(func() -> void:
		is_moving = false
		turned.emit(facing)
	)

## Gira (con el mismo tween) hasta mirar hacia una celda vecina: cuando un
## enemigo te alcanza por un costado o la espalda, te das vuelta para pelear.
func face_towards(cell: Vector2i) -> void:
	var d := cell - grid_pos
	var want := DIRS.find(d)
	if want == -1 or want == facing:
		return
	var step := posmod(want - facing, 4)
	if step == 3:
		step = -1
	facing = want
	var tween := create_tween()
	tween.tween_property(self, "rotation_degrees:y", rotation_degrees.y - step * 90.0, TURN_TIME)

## Gira hacia cualquier celda (no solo una vecina): hacia el eje en el que
## está más lejos. Devuelve la duración del giro (0 si ya miraba hacia ahí).
func face_cell(cell: Vector2i) -> float:
	var d := cell - grid_pos
	if d == Vector2i.ZERO:
		return 0.0
	var step := Vector2i(signi(d.x), 0) if absi(d.x) > absi(d.y) else Vector2i(0, signi(d.y))
	if DIRS.find(step) == facing:
		return 0.0
	face_towards(grid_pos + step)
	return TURN_TIME

## Mueve sin animación (saltar de piso, debug).
func teleport(cell: Vector2i, new_facing: int) -> void:
	grid_pos = cell
	facing = new_facing
	rotation_degrees.y = -facing * 90.0
	position = cell_to_world(grid_pos, EYE_HEIGHT)
