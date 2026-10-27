class_name RunController
extends Node
## Escena de la expedición (Run.tscn). Construye el piso actual de GameState
## (generado con semilla, o la sala de pruebas), coloca al jugador y maneja la
## exploración: enemigos que patrullan y persiguen, cofres, objetos sueltos,
## salida custodiada por el jefe, combates, menús (pausa, estado,
## inventario) y el mapa de mano (M: FieldMap, el pergamino en 3D).
##
## Arquitectura de renderizado (igual que el prototipo): todo lo 3D vive en un
## SubViewport de baja resolución (el pixelado PS1); el HUD, el combate y los
## menús son CanvasLayer hijos de esta escena, a resolución nativa.
##
## Bajar de piso = GameState.advance_floor() + recargar Run.tscn (con fundido):
## esta escena siempre construye "el piso en el que está GameState".

const PLAYER_SCRIPT := preload("res://scripts/world/grid_player.gd")
const COMBAT_SCRIPT := preload("res://scripts/combat/combat_manager.gd")
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var fd: FloorData
var builder: FloorBuilder
var world: Node3D
var container: RetroView
var viewport: SubViewport
var player: Node3D
var hud: RunHud
var combat: Node = null
var menu: Control = null
## El pergamino del mapa (M), colgado de la cámara.
var field_map: FieldMap
var dialog_open := false
var exit_node: Node3D = null
var exit_open := false
var chest_nodes: Dictionary = {}     # Vector2i -> Node3D
var item_nodes: Dictionary = {}      # Vector2i -> {node, item_id}
## Sala del jefe (FloorBuilder.build_boss_room): {door, braziers, circle}.
var boss_room: Dictionary = {}
## La puerta de la sala del jefe está cerrada (bloquea el paso).
var _door_closed := false
## La presentación del jefe está en curso (sin control ni menús).
var _intro_running := false
var _time := 0.0

func _ready() -> void:
	if not GameState.active:
		# Escena abierta directamente (F6): arranca una run nueva.
		GameState.new_run(_pick_seed(), false)
	_setup_viewport()
	_build_floor()
	hud = RunHud.new()
	add_child(hud)
	_after_move()
	if GameState.floor_n == 1 and GameState.elapsed_sec < 0.5:
		var theme_name := String(DataRegistry.get_theme(GameState.floor_n).get("nombre", ""))
		EventBus.hud_message.emit(DataRegistry.t("run.start_msg", [theme_name]) if not GameState.test_room else DataRegistry.t("run.test_room_msg"))
	else:
		EventBus.hud_message.emit(DataRegistry.t("run.floor_msg", [GameState.floor_n, String(DataRegistry.get_theme(GameState.floor_n).get("nombre", ""))]))

func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if builder:
		builder.dispose()

## Semilla de la run: la fijada en el panel de debug, o una al azar.
static func _pick_seed() -> int:
	return DebugTools.fixed_seed if DebugTools.fixed_seed >= 0 else randi()

# --- Construcción -------------------------------------------------------------------

## Resolución baja, trama y globals PSX: ver RetroView.
func _setup_viewport() -> void:
	container = RetroView.new()
	add_child(container)
	viewport = container.viewport
	world = container.world

func _build_floor() -> void:
	builder = FloorBuilder.new(world, DataRegistry.get_theme(GameState.floor_n))
	if GameState.test_room:
		fd = FloorGenerator.test_room()
	else:
		fd = FloorGenerator.generate(GameState.floor_n, GameState.run_seed, MetaState.available_items())
	builder.build_blocks(fd)
	builder.build_pillars(fd)
	builder.build_props(fd)
	builder.build_lighting()
	builder.build_torches(fd)
	if GameState.floor_flags.get("torch", false):
		_light_torch()
	for e: Dictionary in fd.enemies:
		e["node"] = builder.spawn_enemy(e)
	var boss := _boss()
	if not boss.is_empty():
		boss_room = builder.build_boss_room(fd, boss.get("eye_color", Color.WHITE))
		_door_closed = fd.boss_door.x >= 0
		# Dormido sobre su círculo: el aura se enciende cuando se levanta.
		var v := _visual(boss)
		if v and v.light and bool(boss.get("dormant", false)):
			v.light.set_meta("energy", v.light.base_energy)
			v.light.base_energy = 0.0
	for c in fd.chests:
		chest_nodes[c] = builder.spawn_chest(c, fd)
	for it: Dictionary in fd.items:
		item_nodes[it.cell] = {"node": builder.spawn_item(it.cell), "item_id": it.item_id}
	if fd.exit_cell.x >= 0:
		exit_node = builder.spawn_exit(fd.exit_cell)

	player = Node3D.new()
	player.set_script(PLAYER_SCRIPT)
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = DataRegistry.bal_f("render.fov", 64.0)
	player.add_child(cam) # antes de entrar al árbol (ver gotcha de @onready en docs)
	field_map = FieldMap.new(cam)
	cam.add_child(field_map)
	field_map.toggled.connect(_on_field_map_toggled)
	# El charco de luz cálida que acompaña al equipo (la antorcha de mano):
	# con niebla y sin sol, es lo que deja ver lo que hay cerca.
	var lamp := FlickerLight.make(
		Color.html(String(DataRegistry.bal("render.player_light_color", "#ffc98a"))),
		DataRegistry.bal_f("render.player_light_energy", 1.3),
		DataRegistry.bal_f("render.player_light_range", 7.0),
		DataRegistry.bal_f("render.player_light_attenuation", 1.5),
		DataRegistry.bal_f("render.flicker_amount", 0.05),
		DataRegistry.bal_f("render.flicker_hz", 10.0))
	lamp.position = Vector3(0, 0.3, 0)
	player.add_child(lamp)
	world.add_child(player)
	player.call("setup", fd.start_cell, self, fd.start_facing)
	_apply_head_bob()
	EventBus.settings_changed.connect(_apply_head_bob)
	player.connect("moved", _on_player_moved)
	player.connect("turned", func(_f: int) -> void: _after_move())
	player.connect("bumped", func(_c: Vector2i) -> void: SceneRouter.play_ui("error"))

func _apply_head_bob() -> void:
	player.set("bob_amount", DataRegistry.bal_f("render.head_bob", 0.04) if bool(MetaState.settings.get("head_bob", true)) else 0.0)

func _process(delta: float) -> void:
	_time += delta
	# Objetos sueltos: flotan y giran (se ven desde lejos).
	for c: Variant in item_nodes.keys():
		var n: Node3D = item_nodes[c].node
		n.rotation.y = _time * 1.5
		n.position.y = 0.06 * sin(_time * 3.0 + float((c as Vector2i).x))

# --- Interfaz que usa GridPlayer -------------------------------------------------------

func is_wall(cell: Vector2i) -> bool:
	return fd.is_wall(cell) or fd.solid.has(cell) or chest_nodes.has(cell) or (_door_closed and cell == fd.boss_door)

func get_enemy_at(cell: Vector2i) -> bool:
	return not fd.enemy_at(cell).is_empty()

## Cofres (se abren chocándolos) y salida sellada. true = el paso se consume.
func try_interact(cell: Vector2i, _p: Node3D) -> bool:
	if chest_nodes.has(cell):
		_open_chest(cell)
		return true
	if cell == fd.boss_door and _door_closed:
		_open_boss_door()
		return true
	if cell == fd.exit_cell and not exit_open:
		EventBus.hud_message.emit(DataRegistry.t("run.exit_sealed"))
		SceneRouter.play_ui("error")
		return true
	return false

# --- Exploración ------------------------------------------------------------------------

func _on_player_moved(cell: Vector2i) -> void:
	_pickup_at(cell)
	_after_move()
	if _wants_boss_intro(cell):
		_boss_intro()
		return
	_enemies_act()
	if combat == null and cell == fd.exit_cell and exit_open:
		_exit_dialog()

## Descubre celdas (radio 1 + línea recta hacia adelante) para el mapa,
## marca especies vistas para el bestiario y refresca el HUD.
func _after_move() -> void:
	var cell: Vector2i = player.get("grid_pos")
	var facing := int(player.get("facing"))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := cell + Vector2i(dx, dy)
			if not fd.is_wall(c):
				GameState.visited[c] = true
	var ahead := cell
	for i in 4:
		ahead += DIRS[facing]
		if fd.is_wall(ahead):
			break
		GameState.visited[ahead] = true
	for e: Dictionary in fd.enemies:
		var ec: Vector2i = e.cell
		if GameState.visited.has(ec) and absi(ec.x - cell.x) + absi(ec.y - cell.y) <= 4:
			GameState.register_seen(String(e.species_id))
	if hud:
		hud.refresh()
		hud.update_map(fd, cell, facing, map_markers())

## Marcadores conocidos para el mapa y la placa de interacción (solo en
## celdas descubiertas).
func map_markers() -> Dictionary:
	var m := {}
	for c: Vector2i in chest_nodes.keys():
		if GameState.visited.has(c) or _touches_visited(c):
			m[c] = "chest"
	for c: Vector2i in item_nodes.keys():
		if GameState.visited.has(c):
			m[c] = "item"
	var pc: Vector2i = player.get("grid_pos")
	for e: Dictionary in fd.enemies:
		var ec: Vector2i = e.cell
		if GameState.visited.has(ec) and absi(ec.x - pc.x) + absi(ec.y - pc.y) <= 4:
			m[ec] = "boss" if e.kind == RunRules.BOSS else "enemy"
	if _door_closed and (GameState.visited.has(fd.boss_door) or _touches_visited(fd.boss_door)):
		m[fd.boss_door] = "door"
	if fd.exit_cell.x >= 0 and GameState.visited.has(fd.exit_cell):
		m[fd.exit_cell] = "exit_open" if exit_open else "exit"
	return m

func _touches_visited(c: Vector2i) -> bool:
	for d in DIRS:
		if GameState.visited.has(c + d):
			return true
	return false

func _pickup_at(cell: Vector2i) -> void:
	if not item_nodes.has(cell):
		return
	var id := String(item_nodes[cell].item_id)
	var it := DataRegistry.get_item(id)
	if GameState.add_item(id):
		(item_nodes[cell].node as Node3D).queue_free()
		item_nodes.erase(cell)
		fd.items = fd.items.filter(func(x: Dictionary) -> bool: return x.cell != cell)
		EventBus.hud_message.emit(DataRegistry.t("run.picked", [it.nombre]))
		SceneRouter.play_ui("item")
	else:
		EventBus.hud_message.emit(DataRegistry.t("run.inventory_full", [it.nombre]))
		SceneRouter.play_ui("error")

func _open_chest(cell: Vector2i) -> void:
	var node: Node3D = chest_nodes[cell]
	chest_nodes.erase(cell)
	var coins := RunRules.chest_coins(GameState.floor_n, GameState.rng)
	GameState.add_coins(coins, "chests")
	var id := FloorGenerator.roll_item(GameState.rng, MetaState.available_items())
	# Las monedas van en un toast dorado («◈ +12 monedas»); el mensaje de
	# abajo solo cuenta qué objeto había dentro.
	UIToast.show(get_tree(), DataRegistry.t("run.chest_toast", [coins]), "coin")
	if id != "":
		var it := DataRegistry.get_item(id)
		if GameState.add_item(id):
			EventBus.hud_message.emit(DataRegistry.t("run.chest_item", [it.nombre]))
		else:
			# Inventario lleno: el objeto queda en el piso, al lado del cofre abierto.
			item_nodes[cell] = {"node": builder.spawn_item(cell), "item_id": id}
			EventBus.hud_message.emit(DataRegistry.t("run.chest_item_left", [it.nombre]))
	# Se abre (sacudón, tapa, golpe de luz) y queda abierto con la luz baja.
	var chest := node as EnemyBody
	if chest != null and chest.play_role("open", "opened") > 0.0:
		if chest.light:
			chest.light.create_tween().tween_property(chest.light, "base_energy", chest.light.base_energy * 0.35, 0.8)
	else:
		node.queue_free()
	SceneRouter.play_ui("coin")
	_after_move()

# --- Enemigos ----------------------------------------------------------------------------

## Turno de los enemigos tras cada paso del jugador: los que están cerca (por
## camino, no en línea recta) se acercan; el resto deambula. Si uno llega a
## la celda del jugador empieza el combate: de frente es normal; por la
## espalda o un costado es una EMBOSCADA (el enemigo pega primero).
func _enemies_act() -> void:
	if combat != null:
		return
	var pc: Vector2i = player.get("grid_pos")
	var blocked := {}
	for c: Vector2i in chest_nodes.keys():
		blocked[c] = true
	if _door_closed:
		blocked[fd.boss_door] = true
	var dist := fd.distances_from(pc, blocked)
	var aggro := DataRegistry.bal_i("enemies.aggro_radius", 5)
	var wake := DataRegistry.bal_i("enemies.wake_radius", 2)
	var wander := DataRegistry.bal_f("enemies.wander_chance", 0.3)
	var occupied := {}
	for e: Dictionary in fd.enemies:
		occupied[e.cell] = true
	for e: Dictionary in fd.enemies.duplicate():
		if combat != null:
			return
		if e.kind == RunRules.BOSS:
			continue
		if int(e.get("stunned", 0)) > 0:
			e["stunned"] = int(e.stunned) - 1
			continue
		var ec: Vector2i = e.cell
		var d := int(dist.get(ec, 9999))
		# Levantándose del suelo: no hace nada hasta terminar la animación.
		if bool(e.get("rising", false)):
			continue
		# Dormido: no se mueve hasta que el equipo pasa cerca; ese turno solo
		# se levanta (después persigue).
		if bool(e.get("dormant", false)):
			if d <= wake:
				_wake_enemy(e, dist)
			continue
		var target := ec
		if d <= aggro:
			for dir in DIRS:
				var n := ec + dir
				if int(dist.get(n, 9999)) < d and not occupied.has(n) and not chest_nodes.has(n) and n != fd.exit_cell:
					target = n
					break
		elif GameState.rng.randf() < wander:
			var dir := DIRS[GameState.rng.randi_range(0, 3)]
			var n := ec + dir
			if not is_wall(n) and not occupied.has(n) and n != fd.exit_cell and n != pc:
				target = n
		if target == ec:
			continue
		if target == pc:
			_turn_enemy_towards(e, pc)
			var facing_cell: Vector2i = player.call("facing_cell")
			var mode := "normal" if facing_cell == ec else "ambush"
			if not DataRegistry.bal("combat.ambush_enabled", true):
				mode = "normal"
			start_combat(ec, player, mode)
			return
		occupied.erase(ec)
		occupied[target] = true
		# Girar ANTES de cambiar de celda (el giro se calcula desde la celda
		# actual; después daba dirección nula y caminaba de costado).
		_turn_enemy_towards(e, target, true)
		e["cell"] = target
		var node: Node3D = e.node
		_anim(e, "walk")
		var tw := node.create_tween()
		tw.tween_property(node, "position", FloorBuilder.cell_to_world(target), 0.2)
		# Entre pasos vuelve a quedarse quieto (si nadie le cambió el papel).
		tw.tween_interval(0.25)
		tw.tween_callback(func() -> void:
			var v := _visual(e)
			if v and v.current_role == "walk":
				v.play_role("idle")
		)
	_after_move()

## Gira al enemigo hacia una celda VECINA de la suya. `animate`: giro corto
## (0,12 s) por el lado más corto; si no, de golpe.
func _turn_enemy_towards(e: Dictionary, target: Vector2i, animate := false) -> void:
	var d: Vector2i = target - (e.cell as Vector2i)
	var idx := DIRS.find(d)
	if idx < 0:
		return
	e["facing"] = idx
	var node: Node3D = e.node
	var want := deg_to_rad(180.0 - idx * 90.0)
	if not animate:
		node.rotation.y = want
		return
	var to := node.rotation.y + wrapf(want - node.rotation.y, -PI, PI)
	node.create_tween().tween_property(node, "rotation:y", to, 0.12)

## Un esqueleto dormido se levanta: animación de salir del suelo y mira hacia
## el camino por el que viene el equipo.
func _wake_enemy(e: Dictionary, dist: Dictionary) -> void:
	e["dormant"] = false
	var ec: Vector2i = e.cell
	for dir in DIRS:
		if int(dist.get(ec + dir, 9999)) < int(dist.get(ec, 9999)):
			_turn_enemy_towards(e, ec + dir)
			break
	var v := _visual(e)
	if v and v.play_role("spawn", "idle") > 0.0:
		e["rising"] = true
		v.finished_role.connect(func(role: String) -> void:
			if role == "spawn":
				e.erase("rising")
		)
	else:
		_anim(e, "idle")
	EventBus.hud_message.emit(DataRegistry.t("run.enemy_wakes", [e.display_name]))

## El cuerpo animado de un enemigo, modelo o sprite (null si es de los viejos,
## sin animación, o si ya se liberó).
func _visual(e: Dictionary) -> EnemyBody:
	var n: Variant = e.get("node")
	if n == null or not is_instance_valid(n):
		return null
	return n as EnemyBody

## Reproduce un papel de animación del enemigo. Devuelve su duración (0 = no hay).
func _anim(e: Dictionary, role: String, then := "idle") -> float:
	var v := _visual(e)
	return v.play_role(role, then) if v else 0.0

## Cadáver: termina de caer y se hunde en el piso a pasos (no se deja: un
## montón de huesos en el suelo es un esqueleto DORMIDO).
func _dispose_corpse(e: Dictionary) -> void:
	var v := _visual(e)
	if v == null:
		var n: Variant = e.get("node")
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
		return
	if not v.is_dead():
		v.play_role("death", "")
	if v.light:
		v.light.create_tween().tween_property(v.light, "base_energy", 0.0, 0.6)
	var tw := v.create_tween()
	tw.tween_interval(0.5)
	for i in 6:
		tw.tween_property(v, "position:y", -0.12 * (i + 1), 0.0).set_delay(0.12)
	tw.tween_callback(v.queue_free)

# --- Combate ------------------------------------------------------------------------------

## Lo llama GridPlayer al chocar con un enemigo (modo "surprise": tú
## iniciaste el contacto) y _enemies_act cuando un enemigo te alcanza.
func start_combat(cell: Vector2i, _p: Node3D, mode := "surprise") -> void:
	if combat != null:
		return
	var e := fd.enemy_at(cell)
	if e.is_empty():
		return
	if DebugTools.force_surprise:
		mode = "surprise"
	player.call("set_input_locked", true)
	player.call("face_towards", cell)
	_turn_enemy_towards(e, player.get("grid_pos"))
	# Pose de combate: el dormido se levanta de golpe; el jefe se burla antes.
	var v := _visual(e)
	if bool(e.get("rising", false)) and v and v.current_role == "spawn":
		# Ya se está levantando: que termine y después quede en guardia.
		v.set_then("combat")
	else:
		var intro := ""
		if bool(e.get("dormant", false)):
			e["dormant"] = false
			intro = "spawn"
		elif e.kind == RunRules.BOSS and mode != "boss":
			# Con presentación ("boss") ya se burló: entra directo en guardia.
			intro = "taunt"
		if intro == "" or _anim(e, intro, "combat") <= 0.0:
			_anim(e, "combat")
	# En combate ya no importa: si un golpe corta el "levantarse", que no quede
	# trabado para siempre (después de huir tiene que volver a moverse).
	e.erase("rising")
	GameState.register_seen(String(e.species_id))
	EventBus.combat_started.emit(String(e.species_id), e.kind == RunRules.BOSS)

	var rank := int(e.rank)
	var kind := String(e.kind)
	var stats := RunRules.enemy_stats(rank, kind)
	var species := DataRegistry.get_species(String(e.species_id))

	var soul: Dictionary = {}
	var soul_options: Array = []
	if kind == RunRules.BOSS:
		# El jefe deja elegir entre varias almas (la suya, otra de jefe y una
		# de las especies del piso).
		var fl := DataRegistry.get_floor(GameState.floor_n)
		var boss_def: Dictionary = fl.get("boss", {"species": e.species_id, "soul_id": e.get("soul_id", "")})
		for sid in GameState.boss_soul_options(boss_def, fl, GameState.rng):
			var from_name := String(DataRegistry.get_species(String(DataRegistry.get_soul(sid).get("species", ""))).get("display_name", e.display_name))
			soul_options.append(DataRegistry.make_soul(sid, rank, String(e.display_name) if sid == String(e.get("soul_id", "")) else from_name))
	else:
		# Sabiduría, SUE, Buena estrella y la racha sin alma suman puntos.
		var sid := GameState.roll_soul(String(e.species_id), rank, kind, GameState.rng, DebugTools.force_soul_drop)
		if sid != "":
			soul = DataRegistry.make_soul(sid, rank, String(e.display_name))
	e["dropped_soul"] = not soul.is_empty() or not soul_options.is_empty()

	# El bonus de monedas (almas + SUE) se fija al empezar: lo que muestra el
	# resumen es lo que se cobra.
	var coin_bonus := GameState.party_coin_bonus()
	e["coin_bonus"] = coin_bonus
	var coin_preview := roundi(RunRules.kill_coins(rank, kind, GameState.floor_n) * (1.0 + coin_bonus))
	var xp := GameState.kill_xp(rank, kind)
	var first_kill := not MetaState.has_killed(String(e.species_id)) and not GameState.kills_by_species.has(e.species_id)

	var m := GameState.hero()
	var hero := GameState.combat_hero(m)
	hero["souls"] = (m.souls as Array).duplicate(true)
	hero["soul_capacity"] = GameState.member_soul_capacity(m)
	# Si gana, recibe la EXP de esta kill: nivel y almas con los que queda
	# (para no marcarlo "lleno" si la victoria le abre lugar).
	var level_win := RunRules.level_after_xp(int(m.level), int(m.xp), xp)
	hero["level"] = int(m.level)
	hero["xp"] = int(m.xp)
	hero["level_win"] = level_win
	hero["soul_capacity_win"] = int(m.soul_capacity) + RunRules.level_soul_slots(level_win)

	combat = COMBAT_SCRIPT.new()
	combat.set("enemy_data", {
		"name": e.display_name, "rank": rank, "hp": stats.hp, "atk": stats.atk,
		"kind": kind, "species_id": e.species_id,
		"ability_name": String(DataRegistry.get_soul(String(e.get("soul_id", ""))).get("active", {}).get("name", "")),
	})
	combat.set("hero_data", hero)
	combat.set("inventory", GameState.inventory.duplicate())
	combat.set("start_mode", mode)
	# AGI facilita huir (dentro de los topes de balance).
	var flee := RunRules.flee_chance(rank, GameState.floor_n) + RunRules.stat_flee(roundi(GameState.party_stat_average("agi")))
	combat.set("flee_chance", clampf(flee, DataRegistry.bal_f("flee.min", 0.1), DataRegistry.bal_f("flee.max", 0.9)))
	combat.set("soul_drop", soul)
	combat.set("soul_options", soul_options)
	combat.set("reward_preview", {"coins": coin_preview, "xp": xp, "first_kill": first_kill, "first_kill_bonus": RunRules.first_kill_bonus(int(species.get("rank", rank))), "species_name": String(species.get("display_name", e.display_name))})
	combat.set("rng", GameState.rng)
	combat.set("god_mode", DebugTools.god_mode)
	combat.set("one_hit", DebugTools.one_hit)
	# Señales conectadas ANTES de add_child: en una emboscada el enemigo actúa
	# dentro de _ready (si no, su primer ataque no se anima).
	combat.connect("enemy_hit", func(_d: int) -> void:
		_blink(e.node)
		_anim(e, "hit", "combat")
	)
	combat.connect("enemy_acting", func(action: String) -> void:
		if action != "ability" or _anim(e, "ability", "combat") <= 0.0:
			_anim(e, "attack", "combat")
	)
	combat.connect("enemy_defeated", func() -> void: _anim(e, "death", ""))
	combat.connect("impact", func(what: String, strength: float) -> void: _on_combat_impact(e, what, strength))
	combat.connect("combat_ended", func(outcome: String, result: Dictionary) -> void: _on_combat_ended(e, outcome, result))
	hud.visible = false
	_frame_combat_camera(true, e.kind == RunRules.BOSS)
	add_child(combat)

## En combate la cámara retrocede un poco (sin moverse de celda) para que el
## enemigo de la celda de enfrente entre entero en cuadro. Un jefe es más
## alto (y trae espectro y esbirros a los pies): la cámara abre el campo,
## así entran la corona bajo su barra de vida y los esbirros sobre las
## tarjetas del equipo.
func _frame_combat_camera(on: bool, boss := false) -> void:
	var cam := player.get_child(0) as Camera3D
	if cam == null:
		return
	var pos := Vector3.ZERO
	var fov := DataRegistry.bal_f("render.fov", 64.0)
	var pitch := 0.0
	if on and boss:
		pos = Vector3(0, DataRegistry.bal_f("render.combat_boss_lift", 0.15), 0.9)
		fov = DataRegistry.bal_f("render.combat_fov_boss", 72.0)
		pitch = DataRegistry.bal_f("render.combat_boss_pitch", -1.0)
	elif on:
		pos = Vector3(0, 0.15, 0.75)
		# FOV más cerrado en combate: el enemigo llena el cuadro.
		fov = DataRegistry.bal_f("render.combat_fov", 64.0)
	var tw := cam.create_tween()
	tw.tween_property(cam, "position", pos, 0.2)
	tw.parallel().tween_property(cam, "fov", fov, 0.2)
	tw.parallel().tween_property(cam, "rotation_degrees:x", pitch, 0.2)

## Golpes del combate en el mundo: sacudón de cámara (Opciones → Destellos
## y sacudones) y el enemigo que retrocede un paso corto y vuelve.
func _on_combat_impact(e: Dictionary, kind: String, strength: float) -> void:
	if bool(MetaState.settings.get("combat_fx", true)):
		match kind:
			"crit":
				_shake(0.3, 0.02 + 0.04 * strength)
			"kill":
				_shake(0.45, 0.07)
			"hurt":
				_shake(0.3, 0.015 + 0.03 * strength)
			"hit":
				_shake(0.15, 0.008 + 0.012 * strength)
	if kind == "hit" or kind == "crit" or kind == "kill":
		_knockback(e, 0.05 if kind == "hit" else 0.12)

func _knockback(e: Dictionary, amount: float) -> void:
	var body: Variant = e.get("node")
	if body == null or not is_instance_valid(body):
		return
	var node := body as Node3D
	# En reposo, el enemigo está en el centro de su celda.
	var home := FloorBuilder.cell_to_world(e.cell, node.position.y)
	var away := home - player.position
	away.y = 0.0
	if away.length() < 0.01:
		return
	var tw := node.create_tween()
	tw.tween_property(node, "position", home + away.normalized() * amount, 0.05)
	tw.tween_property(node, "position", home, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Parpadeo PS1 del modelo al recibir un golpe.
func _blink(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var tw := node.create_tween()
	for i in 3:
		tw.tween_callback(func() -> void: node.visible = false)
		tw.tween_interval(0.04)
		tw.tween_callback(func() -> void: node.visible = true)
		tw.tween_interval(0.04)

func _on_combat_ended(e: Dictionary, outcome: String, result: Dictionary) -> void:
	for mid: Variant in (result.hp as Dictionary).keys():
		var m := GameState.get_member(String(mid))
		if not m.is_empty():
			m["hp"] = int(result.hp[mid])
	for id: Variant in result.items_used:
		GameState.consume_item_at(GameState.inventory.find(String(id)))
	# Monedas de los críticos (Puntería codiciosa): se cobran pase lo que pase.
	if int(result.get("coins", 0)) > 0:
		GameState.add_coins(int(result.coins), "kills")
	combat.queue_free()
	combat = null
	hud.visible = true
	_frame_combat_camera(false)
	match outcome:
		"victory":
			GameState.register_kill(String(e.species_id), int(e.rank), String(e.kind), float(e.get("coin_bonus", -1.0)))
			GameState.register_soul_roll(String(e.kind), bool(e.get("dropped_soul", false)))
			_grant_xp(GameState.kill_xp(int(e.rank), String(e.kind)))
			var pick: Dictionary = result.soul_pick
			if not pick.is_empty():
				# Si después de la EXP le quedó lugar, el alma se suma en vez de
				# pisar otra (red de seguridad por si cayó y no subió lo previsto).
				var picked := GameState.get_member(String(pick.member_id))
				var ri := int(pick.replace_index)
				if ri >= 0 and (picked.souls as Array).size() < GameState.member_soul_capacity(picked):
					ri = -1
				GameState.add_soul(String(pick.member_id), pick.soul, ri)
				EventBus.hud_message.emit(DataRegistry.t("run.soul_taken", [GameState.get_member(String(pick.member_id)).name, pick.soul.active.name]))
			# Musgo de cripta: cura al ganar.
			var healed := GameState.heal_after_victory()
			if healed > 0:
				UIToast.show(get_tree(), DataRegistry.t("run.healed_after", [healed]), "good")
			_dispose_corpse(e)
			fd.enemies.erase(e)
			if e.kind == RunRules.BOSS:
				_on_boss_defeated()
		"fled":
			GameState.register_flee(true)
			e["stunned"] = DataRegistry.bal_i("combat.flee_stun_turns", 2)
			_anim(e, "idle")
			EventBus.hud_message.emit(DataRegistry.t("run.fled"))
		"defeat":
			end_run("muerte", String(e.display_name))
			return
	player.call("set_input_locked", false)
	_after_move()

func _on_boss_defeated() -> void:
	exit_open = true
	if exit_node:
		FloorBuilder.set_exit_open(exit_node, true)
	EventBus.hud_message.emit(DataRegistry.t("run.boss_down"))
	_reopen_boss_room()

# --- Sala del jefe -------------------------------------------------------------------------

## El jefe del piso ({} si ya no está).
func _boss() -> Dictionary:
	for e: Dictionary in fd.enemies:
		if e.kind == RunRules.BOSS:
			return e
	return {}

## Entrar a la sala del jefe (la primera vez) dispara su presentación.
func _wants_boss_intro(cell: Vector2i) -> bool:
	if _intro_running or combat != null or bool(GameState.floor_flags.get("boss_intro", false)):
		return false
	if not fd.boss_room.has_point(cell) or cell == fd.boss_door:
		return false
	var e := _boss()
	return not e.is_empty() and bool(e.get("intro", false))

## La presentación del jefe: la puerta se cierra de un portazo detrás del
## equipo, el equipo mira al jefe (la sala está centrada en ese eje), los
## braseros se encienden de a pares (de la entrada hacia el fondo) y después
## el círculo; el jefe se levanta de su montón, aparece su cartel, se burla y
## se desliza por la alfombra hasta el equipo. Recién ahí empieza el combate,
## con su propia entrada (modo "boss"). Enter / Esc la aceleran.
func _boss_intro() -> void:
	var e := _boss()
	_intro_running = true
	GameState.floor_flags["boss_intro"] = true
	player.call("set_input_locked", true)
	hud.visible = false
	var cine := UICinematic.open(self)
	var step := DataRegistry.bal_f("boss_room.intro_step", 0.3)
	await _wait(step)
	_door_closed = true
	FloorBuilder.set_door_open(boss_room.get("door"), false)
	await _wait(0.16)
	SceneRouter.play_ui("door_slam")
	_shake(0.35, 0.06)
	await _wait(step * 2.0)
	var turn: float = player.call("face_cell", e.cell)
	await _wait(maxf(turn, step))
	var fires: Array = (boss_room.get("braziers", []) as Array).duplicate()
	var pp := (player as Node3D).global_position
	fires.sort_custom(func(a: BrazierFire, b: BrazierFire) -> bool:
		return a.global_position.distance_squared_to(pp) < b.global_position.distance_squared_to(pp))
	# De a pares: los que quedan a la misma distancia se encienden juntos.
	var i := 0
	while i < fires.size():
		var d0 := (fires[i] as BrazierFire).global_position.distance_to(pp)
		while i < fires.size() and absf((fires[i] as BrazierFire).global_position.distance_to(pp) - d0) < 0.5:
			(fires[i] as BrazierFire).light_up()
			i += 1
		SceneRouter.play_ui("brazier")
		await _wait(step * 1.4)
	FloorBuilder.set_circle_lit(boss_room.get("circle"), true)
	await _wait(step)
	SceneRouter.play_ui("boss")
	e["dormant"] = false
	_light_boss_aura(e)
	var rise := _anim(e, "spawn", "idle")
	await _wait(rise * 0.6)
	cine.show_title(DataRegistry.t("boss.card_floor", [UIFormat.roman(GameState.floor_n)]), String(e.display_name),
		String(e.get("epithet", "")), DataRegistry.bal_f("boss_room.title_hold", 2.2))
	await _wait(rise * 0.4)
	await _wait(_anim(e, "taunt", "idle"))
	if cine.title_showing:
		await cine.title_done
	await _boss_approach(e)
	cine.close()
	Engine.time_scale = 1.0
	_intro_running = false
	start_combat(e.cell, player, "boss")

## El jefe se desliza por el camino más corto hasta quedar frente al equipo
## (si otro enemigo le tapa el paso, aparece de golpe en una celda libre al
## lado del equipo, primero la de enfrente).
func _boss_approach(e: Dictionary) -> void:
	var pc: Vector2i = player.get("grid_pos")
	var dist := fd.distances_from(pc)
	var node: Node3D = e.node
	var step_t := DataRegistry.bal_f("boss_room.approach_step", 0.24)
	if int(dist.get(e.cell, 9999)) > 1:
		_anim(e, "walk")
	for _i in 64:
		var ec: Vector2i = e.cell
		if int(dist.get(ec, 9999)) <= 1:
			break
		var next := ec
		for dir in DIRS:
			var n := ec + dir
			if int(dist.get(n, 9999)) < int(dist.get(next, 9999)) and fd.enemy_at(n).is_empty() and not chest_nodes.has(n):
				next = n
		if next == ec:
			break
		_turn_enemy_towards(e, next)
		e["cell"] = next
		var tw := node.create_tween()
		tw.tween_property(node, "position", FloorBuilder.cell_to_world(next), step_t)
		await tw.finished
	if int(dist.get(e.cell, 9999)) > 1:
		var spots: Array[Vector2i] = [player.call("facing_cell")]
		for dir in DIRS:
			spots.append(pc + dir)
		for c in spots:
			if not is_wall(c) and fd.enemy_at(c).is_empty() and c != fd.exit_cell:
				e["cell"] = c
				node.position = FloorBuilder.cell_to_world(c)
				break
	_anim(e, "idle")

## Espera `sec` segundos de juego (los acelera Engine.time_scale).
func _wait(sec: float) -> void:
	await get_tree().create_timer(maxf(sec, 0.0)).timeout

## Sacudón de cámara a saltos (offsets de la cámara: no pisa el encuadre).
func _shake(sec: float, amount: float) -> void:
	var cam := player.get_child(0) as Camera3D
	if cam == null:
		return
	var tw := cam.create_tween()
	var n := maxi(int(sec / 0.04), 1)
	for i in n:
		var k := amount * (1.0 - float(i) / n)
		tw.tween_callback(func() -> void:
			cam.h_offset = randf_range(-k, k)
			cam.v_offset = randf_range(-k, k))
		tw.tween_interval(0.04)
	tw.tween_callback(func() -> void:
		cam.h_offset = 0.0
		cam.v_offset = 0.0)

## El aura del jefe (visual.light) se enciende cuando se levanta.
func _light_boss_aura(e: Dictionary, animate := true) -> void:
	var v := _visual(e)
	if v == null or v.light == null or not v.light.has_meta("energy"):
		return
	var energy := float(v.light.get_meta("energy"))
	if animate:
		v.light.create_tween().tween_property(v.light, "base_energy", energy, 0.6)
	else:
		v.light.base_energy = energy

## La sala como queda después de la presentación, sin ella (debug, capturas).
func _dress_boss_room_now() -> void:
	GameState.floor_flags["boss_intro"] = true
	_door_closed = fd.boss_door.x >= 0
	FloorBuilder.set_door_open(boss_room.get("door"), false, false)
	for f: BrazierFire in boss_room.get("braziers", []):
		if not f.is_lit():
			f.light_up(false)
	FloorBuilder.set_circle_lit(boss_room.get("circle"), true, false)
	var e := _boss()
	if not e.is_empty():
		_light_boss_aura(e, false)

## Abre la puerta de la sala del jefe (chocándola desde el pasillo).
func _open_boss_door() -> void:
	_door_closed = false
	FloorBuilder.set_door_open(boss_room.get("door"), true)
	SceneRouter.play_ui("descend")
	EventBus.hud_message.emit(DataRegistry.t("run.boss_door_open"))
	_after_move()

## Muerto el jefe: se abre la puerta y se apaga el círculo (los braseros quedan).
func _reopen_boss_room() -> void:
	if boss_room.is_empty():
		return
	FloorBuilder.set_circle_lit(boss_room.get("circle"), false)
	if _door_closed:
		_door_closed = false
		FloorBuilder.set_door_open(boss_room.get("door"), true)
		SceneRouter.play_ui("descend")

# --- Salida, retiro, fin ------------------------------------------------------------------

func _is_last_floor() -> bool:
	return GameState.floor_n >= DataRegistry.bal_i("floors_per_run", 5)

## Punto de retiro tras el jefe: bajar, retirarse con el botín o quedarse.
func _exit_dialog() -> void:
	if dialog_open:
		return
	dialog_open = true
	player.call("set_input_locked", true)
	var d: UIChoiceDialog
	if _is_last_floor():
		d = UIChoiceDialog.ask(self, DataRegistry.t("exit.title_last"), DataRegistry.t("exit.text_last"), [DataRegistry.t("exit.win")], DataRegistry.t("exit.stay"))
	else:
		d = UIChoiceDialog.ask(self, DataRegistry.t("exit.title"), DataRegistry.t("exit.text"), [DataRegistry.t("exit.descend", [GameState.floor_n + 1]), DataRegistry.t("exit.retreat")], DataRegistry.t("exit.stay"))
		var loot := UILedgerRow.new(DataRegistry.t("exit.loot"), UIFormat.number(GameState.run_coins()), "CoinLabel", "monedas", "moneda")
		loot.custom_minimum_size.x = 440
		loot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		d.add_content(loot)
	var choice: int = await d.chosen
	dialog_open = false
	if _is_last_floor() and choice == 0:
		end_run("victoria")
		return
	match choice:
		0:
			advance_floor()
		1:
			end_run("retiro")
		_:
			player.call("set_input_locked", false)

func advance_floor() -> void:
	SceneRouter.play_ui("descend")
	GameState.advance_floor()
	SceneRouter.goto(SceneRouter.RUN)

func end_run(outcome: String, cause := "") -> void:
	if not GameState.active:
		return
	get_tree().paused = false
	GameState.end_run(outcome, cause)
	SceneRouter.goto(SceneRouter.SUMMARY)

# --- Objetos fuera de combate --------------------------------------------------------------

## Usa el objeto del inventario `index` (desde la pantalla de inventario).
## Pide objetivo si hace falta. Devuelve true si se consumió.
func use_item_field(index: int, ui_parent: Node) -> bool:
	if index < 0 or index >= GameState.inventory.size():
		return false
	var id := GameState.inventory[index]
	var it := DataRegistry.get_item(id)
	match String(it.efecto.tipo):
		"curar":
			# Con el HP completo no se gasta la poción.
			var m := _ask_member(ui_parent, String(it.nombre), true, true)
			if m.is_empty():
				UIToast.show(get_tree(), DataRegistry.t("run.nobody_hurt"))
				return false
			var healed := GameState.heal_member(m, int(it.efecto.valor))
			GameState.consume_item_at(index)
			SceneRouter.play_ui("item")
			UIToast.show(get_tree(), DataRegistry.t("run.healed", [m.name, healed]), "good")
		"antorcha":
			GameState.consume_item_at(index)
			SceneRouter.play_ui("item")
			GameState.floor_flags["torch"] = true
			_light_torch()
			UIToast.show(get_tree(), DataRegistry.t("run.torch"), "good")
		"capacidad_alma":
			var m := _ask_member(ui_parent, String(it.nombre), false)
			if m.is_empty():
				return false
			m["soul_capacity"] = int(m.soul_capacity) + int(it.efecto.valor)
			GameState.consume_item_at(index)
			SceneRouter.play_ui("soul")
			UIToast.show(get_tree(), DataRegistry.t("run.capacity_up", [m.name, GameState.member_soul_capacity(m)]), "soul")
		"sello_retiro":
			var d := UIConfirmDialog.ask(ui_parent, String(it.nombre), DataRegistry.t("run.seal_text"), DataRegistry.t("exit.retreat"), DataRegistry.t("ui.cancel"))
			if not await d.answered:
				return false
			GameState.consume_item_at(index)
			SceneRouter.play_ui("item")
			end_run("retiro")
		_:
			return false
	_after_move()
	return true

## A quién usarle un objeto: el héroe (equipo de uno). {} si no aplica
## (caído, o con el HP completo si hurt_only).
func _ask_member(_ui_parent: Node, _title: String, alive_only: bool, hurt_only := false) -> Dictionary:
	var m := GameState.hero()
	if m.is_empty() or (alive_only and int(m.hp) <= 0) or (hurt_only and int(m.hp) >= GameState.member_max_hp(m)):
		return {}
	return m

func _light_torch() -> void:
	var th := DataRegistry.get_theme(GameState.floor_n)
	FloorBuilder.set_fog(float(th.get("niebla_cerca", 5.0)) + DataRegistry.bal_f("fog.torch_near_bonus", 3.0), float(th.get("niebla_lejos", 16.0)) + DataRegistry.bal_f("fog.torch_far_bonus", 6.0))

# --- Menús ----------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _intro_running:
		# Durante la presentación no hay menús: Enter / Esc la aceleran.
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
			Engine.time_scale = DataRegistry.bal_f("boss_room.skip_speed", 4.0)
			get_viewport().set_input_as_handled()
		return
	if combat != null or dialog_open or not GameState.active:
		return
	if is_instance_valid(menu):
		return
	if field_map.is_open:
		# Con el mapa en la mano solo se lo guarda (M, Esc o Pausa).
		if event.is_action_pressed("open_map") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			close_field_map()
		return
	if event.is_action_pressed("open_map"):
		get_viewport().set_input_as_handled()
		open_field_map()
		return
	var screen: UIScreen = null
	var pause := false
	if event.is_action_pressed("pause"):
		screen = PauseMenu.new(self)
		pause = true
	elif event.is_action_pressed("open_status"):
		screen = StatusScreen.new()
	elif event.is_action_pressed("open_inventory"):
		screen = InventoryScreen.new(self)
	if screen == null:
		return
	get_viewport().set_input_as_handled()
	_open_menu(screen, pause)

func _open_menu(screen: UIScreen, pause: bool) -> void:
	player.call("set_input_locked", true)
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	layer.add_child(screen)
	menu = screen
	if pause:
		get_tree().paused = true
	screen.closed.connect(func() -> void:
		get_tree().paused = false
		layer.queue_free()
		menu = null
		if GameState.active:
			player.call("set_input_locked", false)
			_after_move()
	)

## M: el héroe baja la mirada y levanta el pergamino (FieldMap) con lo
## descubierto del piso; no se mueve hasta guardarlo.
func open_field_map() -> void:
	if field_map.is_open or combat != null or dialog_open or _intro_running or is_instance_valid(menu) or not GameState.active:
		return
	player.call("set_input_locked", true)
	var pc: Vector2i = player.get("grid_pos")
	field_map.open(MapParchment.render(fd, GameState.visited, pc, int(player.get("facing")), map_markers(), GameState.floor_n, GameState.run_seed + GameState.floor_n))
	hud.set_map_open(true)
	SceneRouter.play_ui("page")

func close_field_map() -> void:
	if not field_map.is_open:
		return
	field_map.close()
	hud.set_map_open(false)
	SceneRouter.play_ui("page")

## Guardado el pergamino, vuelve el control.
func _on_field_map_toggled(is_open: bool) -> void:
	if not is_open and GameState.active and combat == null and not dialog_open and not is_instance_valid(menu):
		player.call("set_input_locked", false)

# --- Debug (panel F1 / smoke test) ----------------------------------------------------------

func debug_kill_front() -> void:
	var cell: Vector2i = player.call("facing_cell")
	var e := fd.enemy_at(cell)
	if e.is_empty():
		EventBus.hud_message.emit(DataRegistry.t("debug.no_enemy_front"))
		return
	_on_combat_ended_debug(e)

## EXP para el equipo vivo y aviso de cada subida de nivel (los puntos se
## reparten en Estado → Atributos).
func _grant_xp(xp: int) -> void:
	var ups: Array = GameState.add_xp(xp)
	# Un toast por personaje con el nivel al que llegó (aunque suba varios).
	var last_up := {}
	var slots := {}
	for up: Dictionary in ups:
		var mid := String(up.member_id)
		last_up[mid] = up
		slots[mid] = int(slots.get(mid, 0)) + int(up.slots)
	for mid: Variant in last_up.keys():
		var up: Dictionary = last_up[mid]
		UIToast.show(get_tree(), DataRegistry.t("run.level_up_toast", [up.name, int(up.level)]), "level")
		var hint := DataRegistry.t("run.level_up_hint", [up.name, int(GameState.get_member(String(mid)).get("points", 0))])
		if int(slots[mid]) > 0:
			hint += " " + DataRegistry.t("run.level_up_slot")
		EventBus.hud_message.emit(hint)
	if not ups.is_empty():
		SceneRouter.play_ui("level_up")
	if hud:
		hud.refresh()

func _on_combat_ended_debug(e: Dictionary) -> void:
	GameState.register_kill(String(e.species_id), int(e.rank), String(e.kind))
	_grant_xp(GameState.kill_xp(int(e.rank), String(e.kind)))
	_dispose_corpse(e)
	fd.enemies.erase(e)
	if e.kind == RunRules.BOSS:
		_on_boss_defeated()
	_after_move()

## Pone al jugador frente al enemigo más cercano (no jefe) y empieza el
## combate. Para el panel de debug, capturas y el smoke test.
func debug_fight_nearest(include_boss := false) -> void:
	var pc: Vector2i = player.get("grid_pos")
	var best: Dictionary = {}
	var best_d := 1 << 30
	for e: Dictionary in fd.enemies:
		if e.kind == RunRules.BOSS and not include_boss:
			continue
		var ec: Vector2i = e.cell
		var d := absi(ec.x - pc.x) + absi(ec.y - pc.y)
		if d < best_d:
			best_d = d
			best = e
	if best.is_empty():
		return
	var target_cell: Vector2i = best.cell
	for i in DIRS.size():
		var stand := target_cell - DIRS[i]
		if not is_wall(stand) and fd.enemy_at(stand).is_empty():
			player.call("teleport", stand, i)
			_after_move()
			start_combat(target_cell, player, "surprise")
			return

## Mueve al jugador a "x,y,facing" (capturas de pantalla / pruebas visuales).
func debug_teleport(spec: String) -> void:
	var p := spec.split(",")
	if p.size() < 3:
		return
	player.call("teleport", Vector2i(int(p[0]), int(p[1])), int(p[2]))
	_after_move()

## Pone al jugador frente al jefe del piso y empieza el combate (capturas).
## La sala queda como después de la presentación (rejas, braseros, círculo).
func debug_fight_boss() -> void:
	_dress_boss_room_now()
	for e: Dictionary in fd.enemies:
		if e.kind != RunRules.BOSS:
			continue
		var target_cell: Vector2i = e.cell
		for i in DIRS.size():
			var stand := target_cell - DIRS[i]
			if not is_wall(stand) and fd.enemy_at(stand).is_empty():
				player.call("teleport", stand, i)
				_after_move()
				start_combat(target_cell, player, "normal")
				return

## Capturas: abre la puerta de la sala del jefe y pone al equipo en el
## umbral mirando hacia adentro. `intro`: un paso más (ya adentro) y arranca
## la presentación.
func debug_boss_entrance(intro := false) -> void:
	if fd.boss_door.x < 0:
		return
	_door_closed = false
	FloorBuilder.set_door_open(boss_room.get("door"), true, false)
	var cell := fd.boss_door + DIRS[fd.boss_door_dir] if intro else fd.boss_door
	player.call("teleport", cell, fd.boss_door_dir)
	_after_move()
	if intro:
		_boss_intro()

## Abre el cofre de enfrente (capturas de la animación de apertura).
func debug_open_front() -> void:
	var cell: Vector2i = player.call("facing_cell")
	if chest_nodes.has(cell):
		_open_chest(cell)

func debug_heal_party() -> void:
	for m: Dictionary in GameState.party:
		m["hp"] = GameState.member_max_hp(m)
	_after_move()

func debug_goto_floor(n: int) -> void:
	if GameState.test_room:
		return
	GameState.floor_n = clampi(n, 1, DataRegistry.bal_i("floors_per_run", 5)) - 1
	advance_floor()

func debug_kill_boss() -> void:
	for e: Dictionary in fd.enemies.duplicate():
		if e.kind == RunRules.BOSS:
			_on_combat_ended_debug(e)

## Capturas de pantalla / pruebas visuales: abre un menú o deja el combate en
## un estado concreto. ("status" | "inventory" | "map" | "pause" | "victory" | "soul" |
## "boss_soul": la elección de almas del jefe)
func debug_demo(what: String) -> void:
	match what:
		"status":
			_open_menu(StatusScreen.new(), false)
		"inventory":
			_open_menu(InventoryScreen.new(self), false)
		"map":
			for c in fd.floor_cells():
				if c.distance_to(player.get("grid_pos")) < 9.0:
					GameState.visited[c] = true
			open_field_map()
		"pause":
			_open_menu(PauseMenu.new(self), true)
		"boss_soul":
			debug_fight_boss()
			if combat:
				combat.call("debug_win")
				combat.call("_after_victory_summary")
		"victory", "soul":
			DebugTools.force_soul_drop = what == "soul"
			debug_fight_nearest()
			if combat:
				combat.call("debug_win")
				if what == "soul":
					combat.call("_after_victory_summary")
