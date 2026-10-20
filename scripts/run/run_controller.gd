class_name RunController
extends Node
## Escena de la expedición (Run.tscn). Construye el piso actual de GameState
## (generado con semilla, o la sala de pruebas), coloca al jugador y maneja la
## exploración: enemigos que patrullan y persiguen, cofres, objetos sueltos,
## salida custodiada por el jefe, combates y menús (pausa, estado,
## inventario, mapa).
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
var dialog_open := false
var exit_node: Node3D = null
var exit_open := false
var chest_nodes: Dictionary = {}     # Vector2i -> Node3D
var item_nodes: Dictionary = {}      # Vector2i -> {node, item_id}
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
	return fd.is_wall(cell) or chest_nodes.has(cell)

func get_enemy_at(cell: Vector2i) -> bool:
	return not fd.enemy_at(cell).is_empty()

## Cofres (se abren chocándolos) y salida sellada. true = el paso se consume.
func try_interact(cell: Vector2i, _p: Node3D) -> bool:
	if chest_nodes.has(cell):
		_open_chest(cell)
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
	_enemies_act()
	if combat == null and cell == fd.exit_cell and exit_open:
		_exit_dialog()

## Descubre celdas (radio 1 + línea recta hacia adelante) para el minimapa,
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

## Marcadores conocidos para el minimapa (solo en celdas descubiertas).
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
		SceneRouter.play_ui("coin")
	else:
		EventBus.hud_message.emit(DataRegistry.t("run.inventory_full", [it.nombre]))

func _open_chest(cell: Vector2i) -> void:
	var node: Node3D = chest_nodes[cell]
	chest_nodes.erase(cell)
	var coins := RunRules.chest_coins(GameState.floor_n, GameState.rng)
	GameState.add_coins(coins, "chests")
	var id := FloorGenerator.roll_item(GameState.rng, MetaState.available_items())
	var msg := DataRegistry.t("run.chest_coins", [UIFormat.coins(coins)])
	if id != "":
		var it := DataRegistry.get_item(id)
		if GameState.add_item(id):
			msg += " " + DataRegistry.t("run.chest_item", [it.nombre])
		else:
			# Inventario lleno: el objeto queda en el piso, al lado del cofre abierto.
			item_nodes[cell] = {"node": builder.spawn_item(cell), "item_id": id}
			msg += " " + DataRegistry.t("run.chest_item_left", [it.nombre])
	node.queue_free()
	var open := builder.spawn_prop("Crate_1_open", FloorBuilder.cell_to_world(cell), node.rotation_degrees.y)
	if open:
		open.scale = Vector3.ONE * 1.2
	EventBus.hud_message.emit(msg)
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

## El modelo animado de un enemigo (null si es de los viejos, sin animación,
## o si ya se liberó).
func _visual(e: Dictionary) -> EnemyVisual:
	var n: Variant = e.get("node")
	if n == null or not is_instance_valid(n):
		return null
	return n as EnemyVisual

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
		elif e.kind == RunRules.BOSS:
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
	# Sabiduría (mejora) y SUE del equipo suman puntos porcentuales.
	var chance := RunRules.soul_drop_chance(rank, kind, MetaState.upgrade_bonus("soul_chance_pct") + 100.0 * RunRules.stat_soul(GameState.party_stat_total("sue")))
	if DebugTools.force_soul_drop or GameState.rng.randf() < chance:
		soul = DataRegistry.make_soul(String(e.soul_id), rank, String(e.display_name))

	var coin_preview := roundi(RunRules.kill_coins(rank, kind, GameState.floor_n) * (1.0 + GameState.party_coin_bonus()))
	var first_kill := not MetaState.has_killed(String(e.species_id)) and not GameState.kills_by_species.has(e.species_id)

	var roster: Array = []
	for m: Dictionary in GameState.party:
		roster.append({
			"id": m.id, "name": m.name, "hp": int(m.hp), "max_hp": GameState.member_max_hp(m),
			"atk": GameState.member_atk(m), "souls": (m.souls as Array).duplicate(true),
			"soul_capacity": GameState.member_soul_capacity(m),
			"def": GameState.member_def(m), "ability_bonus": GameState.member_ability_bonus(m),
			"crit_bonus": GameState.member_crit_bonus(m),
		})

	combat = COMBAT_SCRIPT.new()
	combat.set("enemy_data", {
		"name": e.display_name, "rank": rank, "hp": stats.hp, "atk": stats.atk,
		"ability_damage": stats.ability_damage, "kind": kind, "species_id": e.species_id,
		"ability_name": String(DataRegistry.get_soul(String(e.soul_id)).get("active", {}).get("name", "")),
	})
	combat.set("party_roster", roster)
	combat.set("inventory", GameState.inventory.duplicate())
	combat.set("start_mode", mode)
	# AGI promedio del equipo vivo facilita huir (dentro de los topes de balance).
	var flee := RunRules.flee_chance(rank, GameState.floor_n) + RunRules.stat_flee(roundi(GameState.party_stat_average("agi")))
	combat.set("flee_chance", clampf(flee, DataRegistry.bal_f("flee.min", 0.1), DataRegistry.bal_f("flee.max", 0.9)))
	combat.set("soul_drop", soul)
	combat.set("reward_preview", {"coins": coin_preview, "xp": RunRules.kill_xp(rank, kind), "first_kill": first_kill, "first_kill_bonus": RunRules.first_kill_bonus(int(species.get("rank", rank))), "species_name": String(species.get("display_name", e.display_name))})
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
	combat.connect("combat_ended", func(outcome: String, result: Dictionary) -> void: _on_combat_ended(e, outcome, result))
	hud.visible = false
	_frame_combat_camera(true)
	add_child(combat)

## En combate la cámara retrocede un poco (sin moverse de celda) para que el
## enemigo de la celda de enfrente entre entero en cuadro.
func _frame_combat_camera(on: bool) -> void:
	var cam := player.get_child(0) as Camera3D
	if cam == null:
		return
	var tw := cam.create_tween()
	tw.tween_property(cam, "position", Vector3(0, 0.15, 0.75) if on else Vector3.ZERO, 0.2)
	# FOV más cerrado en combate: el enemigo llena el cuadro.
	tw.parallel().tween_property(cam, "fov", DataRegistry.bal_f("render.combat_fov" if on else "render.fov", 64.0), 0.2)

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
	combat.queue_free()
	combat = null
	hud.visible = true
	_frame_combat_camera(false)
	match outcome:
		"victory":
			GameState.register_kill(String(e.species_id), int(e.rank), String(e.kind))
			_grant_xp(RunRules.kill_xp(int(e.rank), String(e.kind)))
			var pick: Dictionary = result.soul_pick
			if not pick.is_empty():
				GameState.add_soul(String(pick.member_id), pick.soul, int(pick.replace_index))
				EventBus.hud_message.emit(DataRegistry.t("run.soul_taken", [GameState.get_member(String(pick.member_id)).name, pick.soul.active.name]))
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
		d = UIChoiceDialog.ask(self, DataRegistry.t("exit.title"), DataRegistry.t("exit.text", [UIFormat.coins(GameState.run_coins())]), [DataRegistry.t("exit.descend", [GameState.floor_n + 1]), DataRegistry.t("exit.retreat")], DataRegistry.t("exit.stay"))
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
			var m := await _ask_member(ui_parent, String(it.nombre), true)
			if m.is_empty():
				return false
			var healed := GameState.heal_member(m, int(it.efecto.valor))
			GameState.consume_item_at(index)
			UIToast.show(get_tree(), DataRegistry.t("run.healed", [m.name, healed]), "good")
		"antorcha":
			GameState.consume_item_at(index)
			GameState.floor_flags["torch"] = true
			_light_torch()
			UIToast.show(get_tree(), DataRegistry.t("run.torch"), "good")
		"capacidad_alma":
			var m := await _ask_member(ui_parent, String(it.nombre), false)
			if m.is_empty():
				return false
			m["soul_capacity"] = int(m.soul_capacity) + int(it.efecto.valor)
			GameState.consume_item_at(index)
			UIToast.show(get_tree(), DataRegistry.t("run.capacity_up", [m.name, int(m.soul_capacity)]), "soul")
		"sello_retiro":
			var d := UIConfirmDialog.ask(ui_parent, String(it.nombre), DataRegistry.t("run.seal_text"), DataRegistry.t("exit.retreat"), DataRegistry.t("ui.cancel"))
			if not await d.answered:
				return false
			GameState.consume_item_at(index)
			end_run("retiro")
		_:
			return false
	_after_move()
	return true

func _ask_member(ui_parent: Node, title: String, alive_only: bool) -> Dictionary:
	var options: Array = []
	var members: Array = []
	for m: Dictionary in GameState.party:
		if alive_only and int(m.hp) <= 0:
			continue
		members.append(m)
		options.append(DataRegistry.t("run.member_option", [m.name, m.hp, GameState.member_max_hp(m), (m.souls as Array).size(), GameState.member_soul_capacity(m)]))
	var d := UIChoiceDialog.ask(ui_parent, title, DataRegistry.t("run.who"), options, DataRegistry.t("ui.cancel"))
	var i: int = await d.chosen
	if i < 0:
		return {}
	return members[i]

func _light_torch() -> void:
	var th := DataRegistry.get_theme(GameState.floor_n)
	FloorBuilder.set_fog(float(th.get("niebla_cerca", 5.0)) + DataRegistry.bal_f("fog.torch_near_bonus", 3.0), float(th.get("niebla_lejos", 16.0)) + DataRegistry.bal_f("fog.torch_far_bonus", 6.0))

# --- Menús ----------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if combat != null or dialog_open or not GameState.active:
		return
	if is_instance_valid(menu):
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
	elif event.is_action_pressed("open_map"):
		screen = MapScreen.new(self)
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
	for up: Dictionary in GameState.add_xp(xp):
		var text := DataRegistry.t("run.level_up", [up.name, int(up.level), DataRegistry.bal_i("leveling.points_per_level", 3)])
		if int(up.slots) > 0:
			text += " " + DataRegistry.t("run.level_up_slot")
		UIToast.show(get_tree(), text, "good")
		SceneRouter.play_ui("coin")
	if hud:
		hud.refresh()

func _on_combat_ended_debug(e: Dictionary) -> void:
	GameState.register_kill(String(e.species_id), int(e.rank), String(e.kind))
	_grant_xp(RunRules.kill_xp(int(e.rank), String(e.kind)))
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
func debug_fight_boss() -> void:
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
## un estado concreto. ("status" | "inventory" | "map" | "pause" | "victory" | "soul")
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
			_open_menu(MapScreen.new(self), false)
		"pause":
			_open_menu(PauseMenu.new(self), true)
		"victory", "soul":
			DebugTools.force_soul_drop = what == "soul"
			debug_fight_nearest()
			if combat:
				combat.call("debug_win")
				if what == "soul":
					combat.call("_after_victory_summary")
