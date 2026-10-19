extends Node3D
## Genera una mazmorra de prueba desde un array 2D (0 = piso, 1 = pared)
## y coloca al jugador con el controlador de grilla.
## Esto es solo para probar la sensación del movimiento — el layout real
## luego vendrá del generador procedural + eventos curados a mano.
##
## Arquitectura de renderizado: todo el mundo 3D vive dentro de un SubViewport
## de baja resolución (el look "pixelado" real de PS1). La UI de combate se
## agrega como hijo directo de Main (fuera del SubViewport), así se mantiene
## nítida a resolución nativa — mezclar ambas cosas en el mismo viewport
## rompería la UI (botones/texto quedarían gigantes y fuera de pantalla).

const CELL_SIZE := 2.0
const WALL_HEIGHT := 2.0 # LevelBlock genera cubos de lado fijo = CELL_SIZE, por eso coincide con esto ahora
const LOW_RES := Vector2i(320, 180) # resolución interna del mundo 3D — el "pixelado" real

var test_map := [
	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
	[1,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
	[1,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
	[1,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
	[1,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
	[1,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
	[1,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
	[1,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
]

# Sala única abierta de 13x7 celdas (antes era un laberinto angosto de 1 celda
# de ancho) — pensada para tener espacio real donde probar cosas: moverse
# largo trecho, elegir con cuál enemigo enfrentarse primero, ver la niebla a
# distancia real, esquivar props/columnas, etc.

# Bestiario: vive en data/species.json + data/souls.json (DataRegistry).
# Cada especie tiene su rango (10 = más débil, 1 = más fuerte) y el alma que
# otorga. Cada alma SIEMPRE da 1 activa (de combate). La pasiva es opcional:
# algunas especies no dan pasiva con nombre, y en su lugar dan modificadores
# planos a las stats base del personaje que la lleve (stat_modifiers). hp/atk
# del enemigo y el daño de su activa salen del rango vía
# DataRegistry.stats_for_rank().

# Celdas de enemigos de prueba: celda -> id de especie (en data/species.json).
# Más adelante esto vendrá del bestiario/generador, no de un diccionario fijo.
# Repartidos al fondo de la sala (arriba y abajo), así el jugador cruza
# espacio real antes de llegar a cualquiera de los dos — y ahora, además,
# elige de qué especie quiere el alma primero.
var enemy_species: Dictionary = {
	Vector2i(12, 2): "goblin",
	Vector2i(12, 6): "rata_cripta",
	Vector2i(9, 4): "esqueleto_guardian",
	Vector2i(4, 2): "goblin_archer",
	Vector2i(4, 6): "goblin_warrior",
}
var enemy_nodes := {} # Vector2i -> Node3D

# Roster persistente del equipo (2 personajes de prueba). Cada uno lleva sus
# PROPIAS almas — las almas son por personaje, no del grupo. souls: lista de
# almas equipadas {active, passive, stat_modifiers}. Por ahora sin límite de
# capacidad real (eso depende del nivel, que todavía no existe en el
# prototipo); el flujo de asignación sí respeta "una a la vez por ahora".
var party_roster := [
	{"id": "bjorn", "name": "Bjorn", "base_hp": 20, "base_atk": 5, "souls": []},
	{"id": "elena", "name": "Elena", "base_hp": 16, "base_atk": 4, "souls": []},
]

var world: Node3D # todo lo 3D (piso, paredes, jugador, enemigos, luces) vive acá dentro
var player_ref: Node3D # referencia al jugador, para bloquear su input al abrir el menú de estado
var status_menu: Node # CanvasLayer del menú de estado (Tab), hijo directo de Main como el combate

func _ready() -> void:
	_ensure_psx_shader_globals() # debe ir primero: los materiales PSX referencian estos globals
	_setup_low_res_viewport()
	_build_dungeon()
	_spawn_player()
	_spawn_enemies()

	status_menu = preload("res://scripts/StatusMenu.gd").new()
	add_child(status_menu) # hijo directo de Main (resolución nativa), como el combate
	status_menu.close_requested.connect(func(): _toggle_status_menu())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_toggle_status_menu()

func _toggle_status_menu() -> void:
	if status_menu.is_open:
		status_menu.set_open(false)
		player_ref.set_input_locked(false)
		return
	if player_ref.input_locked:
		return # ya bloqueado por otra cosa (un combate en curso, por ejemplo) — no abrir encima
	status_menu.refresh(party_roster)
	status_menu.set_open(true)
	player_ref.set_input_locked(true)

## El plugin PSX Visuals normalmente registra sus parámetros globales de shader
## (psx_fog_color, psx_precision_xy, etc.) desde su EditorPlugin._enter_tree(),
## pero eso SOLO corre dentro del proceso del editor — una partida jugada (Play)
## es un proceso aparte y nunca lo recibe. Sin este registro, el shader referencia
## globals inexistentes y todo se rompe (pantalla negra/geometría corrupta).
## Por eso lo registramos nosotros mismos acá, sin depender de que el editor
## haya cargado el plugin antes.
func _ensure_psx_shader_globals() -> void:
	var defaults := {
		&"psx_affine_strength": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0],
		&"psx_bit_depth": [RenderingServer.GLOBAL_VAR_TYPE_INT, 5],
		&"psx_fog_color": [RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.5, 0.5, 0.5, 0.0)],
		&"psx_fog_far": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 20.0],
		&"psx_fog_near": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 10.0],
		&"psx_precision_uv": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 128.0],
		&"psx_precision_xy": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 256.0],
		&"psx_precision_z": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 512.0],
	}
	# project.godot ya declara estos globals en [shader_globals]; volver a
	# agregarlos tira "global_shader_variables.has(p_name)". Solo se registran
	# los que falten.
	var existing := RenderingServer.global_shader_parameter_get_list()
	for k: StringName in defaults.keys():
		if existing.has(k):
			continue
		var rtype: int = defaults[k][0]
		var default_value: Variant = defaults[k][1]
		RenderingServer.global_shader_parameter_add(k, rtype, default_value)

func _setup_low_res_viewport() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # reescalado sin blur: el pixelado real, no una imagen borrosa
	add_child(container)

	var viewport := SubViewport.new()
	viewport.size = LOW_RES
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	world = Node3D.new()
	viewport.add_child(world)

func is_wall(cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= test_map.size():
		return true
	if cell.x < 0 or cell.x >= test_map[cell.y].size():
		return true
	return test_map[cell.y][cell.x] == 1

func get_enemy_at(cell: Vector2i) -> bool:
	return enemy_nodes.has(cell)

func _spawn_enemies() -> void:
	for cell in enemy_species.keys():
		var species: Dictionary = DataRegistry.get_species(enemy_species[cell])
		var node: Node3D
		if species.has("model_path"):
			node = _spawn_model_enemy(species)
		else:
			node = _spawn_box_enemy(species)
		node.position = Vector3(cell.x * CELL_SIZE, 0, cell.y * CELL_SIZE)
		world.add_child(node)
		enemy_nodes[cell] = node

func _spawn_model_enemy(species: Dictionary) -> Node3D:
	var packed: PackedScene = load(species.model_path)
	var inst: Node3D = packed.instantiate()
	inst.scale = Vector3.ONE * float(species.model_scale)
	_apply_psx_material_recursive(inst)
	return inst

## Recorre el modelo instanciado, y para cada malla, arma un PsxMaterial3D
## que reutiliza la textura ORIGINAL de esa malla (para no perder el dibujo
## del personaje) pero con el shading/niebla del plugin PSX aplicado encima.
func _apply_psx_material_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node
		var surface_count: int = mesh_inst.mesh.get_surface_count() if mesh_inst.mesh else 0
		for i in surface_count:
			var original: Material = mesh_inst.mesh.surface_get_material(i)
			var tex: Texture2D = null
			if original is BaseMaterial3D:
				tex = (original as BaseMaterial3D).albedo_texture
			var psx_mat := _make_psx_material(Color(1, 1, 1), tex)
			mesh_inst.set_surface_override_material(i, psx_mat)
	for child in node.get_children():
		_apply_psx_material_recursive(child)

func _spawn_box_enemy(species: Dictionary) -> Node3D:
	var enemy_tex := _make_checker_texture(species.color_a, species.color_b)
	var enemy_mat := _make_psx_material(Color(0.9, 0.9, 0.9), enemy_tex)
	var box := CSGBox3D.new()
	box.size = Vector3(0.8, 1.4, 0.8)
	box.position = Vector3(0, 0.7, 0) # relativo al nodo contenedor, que ya se posiciona en la celda
	box.material = enemy_mat
	var holder := Node3D.new()
	holder.add_child(box)
	return holder

## Se llama desde GridPlayer cuando el jugador "choca" contra la celda de un enemigo.
## La cámara de exploración queda congelada (input_locked) y el combate por turnos
## corre encima, en un CanvasLayer — sin cambiar de escena ni de vista.
## Ojo: el combate se agrega como hijo de Main (NO de "world"), a propósito,
## para que su UI se renderice a resolución nativa y no en baja resolución.
func start_combat(cell: Vector2i, player: Node3D) -> void:
	player.set_input_locked(true)
	var species: Dictionary = DataRegistry.get_species(enemy_species[cell])
	var stats := DataRegistry.stats_for_rank(species.rank)

	# El daño de la activa depende del rango de ESTE monstruo; make_soul()
	# también anota de qué especie/rango salió, para el menú de estado.
	var soul_data := DataRegistry.make_soul(species.soul_id, species.rank, species.display_name)

	# Garantiza alma (para testing) mientras no todos los personajes tengan
	# ya una equipada — así se puede probar la asignación con cada uno sin
	# depender del 0,2% real.
	var souls_distributed := 0
	for member in party_roster:
		souls_distributed += member.souls.size()
	var guarantee: bool = souls_distributed < party_roster.size()

	var combat: Node = preload("res://scripts/CombatManager.gd").new()
	combat.enemy_data = {
		"name": species.display_name,
		"rank": species.rank,
		"hp": stats.hp,
		"atk": stats.atk,
	}
	combat.soul_data = soul_data
	combat.guarantee_soul = guarantee
	combat.party_roster = party_roster.duplicate(true)
	add_child(combat)
	combat.combat_ended.connect(func(victory: bool, soul_result: Dictionary):
		_on_combat_ended(cell, player, combat, victory, soul_result)
	)

func _on_combat_ended(cell: Vector2i, player: Node3D, combat: Node, victory: bool, soul_result: Dictionary) -> void:
	if victory and soul_result.get("picked_up", false):
		var member_id: String = soul_result.member_id
		for member in party_roster:
			if member.id == member_id:
				member.souls.append(soul_result.soul)
				break
	if enemy_nodes.has(cell):
		enemy_nodes[cell].queue_free()
		enemy_nodes.erase(cell)
	combat.queue_free()
	player.set_input_locked(false)

func _spawn_player() -> void:
	var player := Node3D.new()
	player.set_script(preload("res://scripts/GridPlayer.gd"))

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 75.0
	player.add_child(cam) # se agrega ANTES de meter al jugador en el árbol,
						  # así $Camera3D ya existe cuando corre _ready()

	world.add_child(player)
	player_ref = player
	# Esquina izquierda de la sala, mirando al este (facing=1) — de frente
	# a todo el largo del salón, con los enemigos, columnas y props a la vista
	# a distintas distancias.
	player.setup(Vector2i(2, 4), self, 1)

func _build_dungeon() -> void:
	_build_rooms_with_levelblock()

	var pillar_mat := _make_psx_material(Color(0.4, 0.36, 0.3), _make_checker_texture(Color(0.45, 0.4, 0.35), Color(0.28, 0.25, 0.22)))

	# Columnas decorativas — geometría cilíndrica en un par de celdas abiertas,
	# corridas hacia una esquina para no bloquear el paso lógico del grid
	# (is_wall() no las conoce, son puramente visuales). Sirven para ver el
	# efecto de vertex snapping en curvas, que en cubos planos casi no se nota.
	var pillar_cells: Array[Vector2i] = [Vector2i(7, 2), Vector2i(7, 6)]
	for cell in pillar_cells:
		var pillar := CSGCylinder3D.new()
		pillar.radius = 0.3
		pillar.height = WALL_HEIGHT
		pillar.sides = 8 # pocos lados a propósito: más facetado, más "PS1"
		pillar.position = Vector3(cell.x * CELL_SIZE + 0.6, WALL_HEIGHT / 2.0, cell.y * CELL_SIZE + 0.6)
		pillar.material = pillar_mat
		world.add_child(pillar)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -45, 0)
	light.light_energy = 0.9
	world.add_child(light)

	_spawn_test_props()

	var ambient := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.35)
	env.ambient_light_energy = 0.5
	# La niebla la maneja el plugin PSX Visuals con sus propios globals (más abajo),
	# no la niebla nativa de Godot — tenerlas las dos activas duplicaría el efecto.
	env.fog_enabled = false
	ambient.environment = env
	world.add_child(ambient)

	# Niebla propia del plugin PSX Visuals — reajustada para la sala grande
	# (13x7 celdas, CELL_SIZE=2 → ~26x14 unidades). Con los valores viejos
	# (pensados para el laberinto angosto) se comía a los enemigos del fondo.
	Psx.fog_color = Color(0.05, 0.05, 0.08, 1.0)
	Psx.fog_near = 10.0
	Psx.fog_far = 24.0

func _make_psx_material(color: Color, texture: Texture2D = null) -> PsxMaterial3D:
	var mat := PsxMaterial3D.new()
	mat.transparency_mode = 0 # Opaque
	mat.shading_mode = 2 # Per-Vertex — más fiel al look PS1 real (sombreado por vértice, no por píxel)
	mat.fog_mode = PsxMaterial3D.FogMode.PER_VERTEX
	mat.albedo_color = color
	if texture:
		mat.albedo_texture = texture
	mat.refresh_shader() # por si el plugin todavía no corrió su _init de editor (p. ej. primer Play)
	return mat

## Genera una textura de damero por código (sin depender de ningún archivo de
## imagen) — sirve para ver de verdad el mapeo de texturas afín del plugin
## PSX (con un color plano no hay nada que "deforme", así que no se nota).
func _make_checker_texture(color_a: Color, color_b: Color, tiles: int = 4) -> ImageTexture:
	var img := Image.create(tiles, tiles, false, Image.FORMAT_RGB8)
	for y in tiles:
		for x in tiles:
			img.set_pixel(x, y, color_a if (x + y) % 2 == 0 else color_b)
	return ImageTexture.create_from_image(img)

## Genera un atlas de 3 tiles (piso / pared / techo) con líneas de grilla en
## el borde de cada tile — el look clásico de dungeon crawler (Grimrock,
## Wizardry): se nota la costura entre cada celda de 2x2, no un patrón
## decorativo como el damero. Por código, sin depender de ningún archivo.
func _make_grid_atlas(tile_px: int = 64) -> ImageTexture:
	var tiles := [
		{"bg": Color(0.42, 0.38, 0.32), "line": Color(0.2, 0.18, 0.14)}, # 0: piso
		{"bg": Color(0.16, 0.19, 0.24), "line": Color(0.32, 0.35, 0.42)}, # 1: pared
		{"bg": Color(0.07, 0.07, 0.09), "line": Color(0.16, 0.16, 0.19)}, # 2: techo
	]
	var img := Image.create(tile_px * tiles.size(), tile_px, false, Image.FORMAT_RGB8)
	for t in tiles.size():
		var bg: Color = tiles[t].bg
		var line: Color = tiles[t].line
		for y in tile_px:
			for x in tile_px:
				var on_edge: bool = x < 2 or x >= tile_px - 2 or y < 2 or y >= tile_px - 2
				img.set_pixel(t * tile_px + x, y, line if on_edge else bg)
	return ImageTexture.create_from_image(img)

const GRID_TILE_FLOOR := 0
const GRID_TILE_WALL := 1
const GRID_TILE_CEILING := 2

## Construye toda la mazmorra con nodos LevelBlock: un cubo de 2x2x2 por cada
## celda de PISO (las celdas de pared no llevan geometría propia — la "pared"
## que ves es la cara correspondiente de la celda de piso vecina, mirando
## hacia esa dirección). Reemplaza el trío de CSGBox3D piso/pared/techo de
## antes por un solo nodo por celda, con colisión desactivada porque nuestro
## movimiento es 100% lógico por grid (is_wall()), no física.
func _build_rooms_with_levelblock() -> void:
	var atlas := _make_grid_atlas()
	var block_mat := _make_psx_material(Color(1, 1, 1), atlas)
	var level_block_script := preload("res://addons/level_block/level_block_node.gd")

	for y in test_map.size():
		for x in test_map[y].size():
			if test_map[y][x] == 1:
				continue # celda de pared: sin geometría propia
			var block := Node3D.new()
			block.set_script(level_block_script)
			world.add_child(block) # agregar ANTES de configurar propiedades: refresh() necesita estar en el árbol
			block.material = block_mat
			block.texture_sheet = atlas
			block.texture_size = 64
			block.generate_collision = false
			block.top_face = GRID_TILE_CEILING
			block.bottom_face = GRID_TILE_FLOOR
			block.north_face = GRID_TILE_WALL if is_wall(Vector2i(x, y - 1)) else -1
			block.east_face = GRID_TILE_WALL if is_wall(Vector2i(x + 1, y)) else -1
			block.south_face = GRID_TILE_WALL if is_wall(Vector2i(x, y + 1)) else -1
			block.west_face = GRID_TILE_WALL if is_wall(Vector2i(x - 1, y)) else -1
			block.position = Vector3(x * CELL_SIZE + 1.0, WALL_HEIGHT / 2.0, y * CELL_SIZE + 1.0)

# El .glb del pack de cajas/barriles trae VARIOS objetos juntos en un mismo
# archivo (Crate_1, Barrel_1, Chest_1, etc. como nodos separados). Instanciamos
# el archivo UNA sola vez como "plantilla" (sin meterla en el árbol de escena)
# y de ahí vamos duplicando solo el nodo puntual que queremos, tantas veces
# como haga falta, en vez de traer el set completo cada vez.
var _props_template: Node3D = null

func _get_props_template() -> Node3D:
	if _props_template == null:
		var packed: PackedScene = load("res://assets/psx_boxes_barrels/Crates_and_barrels_glb.glb")
		_props_template = packed.instantiate()
	return _props_template

# La plantilla nunca entra al árbol, así que nadie la libera por nosotros.
func _exit_tree() -> void:
	if _props_template:
		_props_template.free()
		_props_template = null

func _spawn_prop(node_name: String, cell_pos: Vector3, rot_y_deg: float = 0.0) -> void:
	var template := _get_props_template()
	var source := template.get_node_or_null(node_name)
	if source == null:
		push_warning("Prop '%s' no encontrado en el pack de cajas/barriles." % node_name)
		return
	var inst: Node3D = source.duplicate()
	world.add_child(inst)
	inst.position = cell_pos
	inst.rotation_degrees.y = rot_y_deg

## Prueba rápida de integración del pack de cajas/barriles PSX: un par de
## props sueltos en celdas abiertas, corridos hacia una esquina como las
## columnas (puramente decorativos, is_wall() no los conoce).
func _spawn_test_props() -> void:
	_spawn_prop("Crate_1", Vector3(3 * CELL_SIZE + 0.5, 0, 2 * CELL_SIZE + 0.5), 15.0)
	_spawn_prop("Barrel_1", Vector3(7 * CELL_SIZE + 0.5, 0, 4 * CELL_SIZE - 0.5), -20.0)
	_spawn_prop("Crate_2", Vector3(11 * CELL_SIZE - 0.5, 0, 4 * CELL_SIZE + 0.5), 40.0)
