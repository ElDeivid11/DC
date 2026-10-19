class_name FloorBuilder
extends RefCounted
## Vuelve 3D un FloorData: LevelBlock por celda de piso (con atlas de grilla
## generado por código), columnas, props del pack PSX, luz + niebla, y los
## nodos de enemigos, cofres, objetos sueltos y salida. Todo con materiales
## PsxMaterial3D (vertex snapping, afín, niebla por vértice).
##
## Es la lógica de construcción que antes vivía en Main.gd, sin cambios de
## aspecto, salvo un arreglo: los nodos (jugador, enemigos) van al CENTRO de
## la celda. Antes iban a la esquina (x*2) mientras el cubo de LevelBlock
## ocupa de x*2 a x*2+2, así que la cámara quedaba pegada a la pared.

const CELL_SIZE := 2.0
const WALL_HEIGHT := 2.0 # LevelBlock genera cubos de lado fijo = CELL_SIZE

const GRID_TILE_FLOOR := 0
const GRID_TILE_WALL := 1
const GRID_TILE_CEILING := 2

# Colores del MUNDO 3D (la UI usa UIStyle; estos son materiales de escena).
const ITEM_GLOW := Color(0.95, 0.72, 0.3)
const EXIT_SEALED := Color(0.55, 0.12, 0.12)
const EXIT_OPEN := Color(0.35, 0.75, 0.95)
const PILLAR_A := Color(0.45, 0.4, 0.35)
const PILLAR_B := Color(0.28, 0.25, 0.22)

var world: Node3D
var _block_mat: PsxMaterial3D
var _atlas: ImageTexture
var _props_template: Node3D = null

static func cell_to_world(cell: Vector2i, y := 0.0) -> Vector3:
	return Vector3(cell.x * CELL_SIZE + CELL_SIZE / 2.0, y, cell.y * CELL_SIZE + CELL_SIZE / 2.0)

## El plugin PSX registra sus parámetros globales de shader desde el EDITOR
## (EditorPlugin._enter_tree), algo que una partida jugada nunca recibe. Sin
## esto el shader referencia globals inexistentes (pantalla negra). Solo se
## agregan los que falten: project.godot ya declara los suyos.
static func ensure_psx_shader_globals() -> void:
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
	# Los declarados en project.godot ([shader_globals]) ya los carga el motor
	# al arrancar. (global_shader_parameter_get_list() solo sirve en el editor.)
	for k: StringName in defaults.keys():
		if ProjectSettings.has_setting("shader_globals/" + String(k)):
			continue
		var rtype: int = defaults[k][0]
		var default_value: Variant = defaults[k][1]
		RenderingServer.global_shader_parameter_add(k, rtype, default_value)

static func make_psx_material(color: Color, texture: Texture2D = null) -> PsxMaterial3D:
	var mat := PsxMaterial3D.new()
	mat.transparency_mode = 0 # Opaque
	mat.shading_mode = 2 # Per-Vertex — más fiel al look PS1 real
	mat.fog_mode = PsxMaterial3D.FogMode.PER_VERTEX
	mat.albedo_color = color
	if texture:
		mat.albedo_texture = texture
	mat.refresh_shader() # por si el plugin todavía no corrió su _init de editor
	return mat

static func make_glow_material(color: Color) -> PsxMaterial3D:
	var mat := make_psx_material(color)
	mat.shading_mode = 0 # Unshaded: se ve en la oscuridad
	mat.emission_enabled = true
	mat.emission = color
	mat.refresh_shader()
	return mat

## Damero por código (sin archivos): deja ver el mapeo afín del plugin PSX.
static func checker_texture(color_a: Color, color_b: Color, tiles: int = 4) -> ImageTexture:
	var img := Image.create(tiles, tiles, false, Image.FORMAT_RGB8)
	for y in tiles:
		for x in tiles:
			img.set_pixel(x, y, color_a if (x + y) % 2 == 0 else color_b)
	return ImageTexture.create_from_image(img)

## Atlas de 3 tiles (piso / pared / techo) con líneas de grilla en el borde:
## el look clásico de dungeon crawler (se nota la costura entre celdas).
static func grid_atlas(tile_px: int = 64) -> ImageTexture:
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

func _init(p_world: Node3D) -> void:
	world = p_world
	ensure_psx_shader_globals()
	_atlas = grid_atlas()
	_block_mat = make_psx_material(Color(1, 1, 1), _atlas)

## Libera la plantilla de props (nunca entra al árbol: nadie más la libera).
func dispose() -> void:
	if _props_template:
		_props_template.free()
		_props_template = null

# --- Geometría ----------------------------------------------------------------------

## Geometría del piso: por cada celda de PISO, un cubo "hacia adentro" de lado
## CELL_SIZE (piso, techo y las paredes que dan a celdas de pared; la "pared"
## es la cara de la celda de piso vecina).
##
## Es el MISMO algoritmo de caras/UV/normales de LevelBlock
## (addons/level_block/level_block_node.gd → create_mesh()), pero todas las
## celdas van a UNA sola malla. Con un nodo LevelBlock por celda (cientos en
## pisos grandes) se agotaba el buffer de "instance uniforms" del shader PSX
## (3 por instancia) y eran cientos de draw calls; el aspecto es idéntico.
## LevelBlock sigue en el proyecto para armar salas a mano en el editor.
func build_blocks(fd: FloorData) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for y in fd.height:
		for x in fd.width:
			var cell := Vector2i(x, y)
			if fd.is_wall(cell):
				continue
			var faces: Array[int] = [
				GRID_TILE_WALL if fd.is_wall(cell + Vector2i(0, -1)) else -1, # norte
				GRID_TILE_WALL if fd.is_wall(cell + Vector2i(1, 0)) else -1,  # este
				GRID_TILE_WALL if fd.is_wall(cell + Vector2i(0, 1)) else -1,  # sur
				GRID_TILE_WALL if fd.is_wall(cell + Vector2i(-1, 0)) else -1, # oeste
				GRID_TILE_CEILING,
				GRID_TILE_FLOOR,
			]
			_append_block(cell_to_world(cell, WALL_HEIGHT / 2.0), faces, verts, normals, uvs, indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _block_mat)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.name = "FloorGeometry"
	world.add_child(inst)

## Un cubo de LevelBlock (lado 2, caras hacia adentro) en `center`.
## faces: índice de tile del atlas por cara [N, E, S, O, techo, piso]; -1 = sin cara.
func _append_block(center: Vector3, faces: Array[int], verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> void:
	const HALF := CELL_SIZE / 2.0
	var face_normals: Array[Vector3] = [Vector3.BACK, Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN, Vector3.UP]
	var rot_axis: Array[Vector3] = [Vector3.DOWN, Vector3.LEFT]
	var rot_angle: Array[float] = [0.0, PI / 2.0, PI, PI + PI / 2.0, -PI / 2.0, PI / 2.0]
	var gap := float(64) / float(_atlas.get_width())
	var quad: Array[Vector3] = [Vector3(-HALF, HALF, -HALF), Vector3(HALF, HALF, -HALF), Vector3(HALF, -HALF, -HALF), Vector3(-HALF, -HALF, -HALF)]
	var quad_uv: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in 6:
		if faces[i] < 0:
			continue
		var uv0 := Vector2(fmod(gap * faces[i], 1.0), floorf(faces[i] / (1.0 / gap)) * gap)
		var base := verts.size()
		var axis := rot_axis[0 if i < 4 else 1]
		for k in 4:
			verts.append(center + quad[k].rotated(axis, rot_angle[i]))
			normals.append(face_normals[i])
			uvs.append(uv0 + quad_uv[k] * gap)
		indices.append_array([base, base + 1, base + 3, base + 1, base + 2, base + 3])

## Columnas decorativas (no bloquean: is_wall() no las conoce). Pocos lados
## a propósito: más facetado, más PS1, y se nota el vertex snapping.
func build_pillars(fd: FloorData) -> void:
	if fd.pillars.is_empty():
		return
	var mat := make_psx_material(Color(0.4, 0.36, 0.3), checker_texture(PILLAR_A, PILLAR_B))
	for pos in fd.pillars:
		var pillar := CSGCylinder3D.new()
		pillar.radius = 0.3
		pillar.height = WALL_HEIGHT
		pillar.sides = 8
		pillar.position = pos + Vector3(0, WALL_HEIGHT / 2.0, 0)
		pillar.material = mat
		world.add_child(pillar)

func build_lighting(fog_near: float, fog_far: float) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -45, 0)
	light.light_energy = 0.9
	world.add_child(light)

	var ambient := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.35)
	env.ambient_light_energy = 0.5
	# La niebla la maneja el plugin PSX con sus globals; la nativa duplicaría.
	env.fog_enabled = false
	ambient.environment = env
	world.add_child(ambient)
	set_fog(fog_near, fog_far)

static func set_fog(near: float, far: float) -> void:
	Psx.fog_color = Color(0.05, 0.05, 0.08, 1.0)
	Psx.fog_near = near
	Psx.fog_far = far

# --- Props (pack PSX de cajas/barriles) ------------------------------------------------
# El .glb trae varios objetos juntos (Crate_1, Barrel_1, Chest_1...). Se
# instancia UNA vez como plantilla fuera del árbol y se duplica solo el nodo
# pedido.

func _get_props_template() -> Node3D:
	if _props_template == null:
		var packed: PackedScene = load("res://assets/psx_boxes_barrels/Crates_and_barrels_glb.glb")
		_props_template = packed.instantiate()
	return _props_template

func spawn_prop(node_name: String, pos: Vector3, rot_y_deg: float = 0.0) -> Node3D:
	var source := _get_props_template().get_node_or_null(node_name)
	if source == null:
		push_warning("Prop '%s' no encontrado en el pack de cajas/barriles." % node_name)
		return null
	var inst: Node3D = source.duplicate()
	_apply_psx_material_recursive(inst, Color.WHITE) # niebla y snapping como el resto
	world.add_child(inst)
	inst.position = pos
	inst.rotation_degrees.y = rot_y_deg
	return inst

func build_props(fd: FloorData) -> void:
	for p: Dictionary in fd.props:
		spawn_prop(String(p.prop), p.pos, float(p.rot))

# --- Entidades ----------------------------------------------------------------------------

## Especies con bloque "visual" → EnemyVisual (modelo animado; arranca en
## "idle" o tirado en el piso si está dormido). Las viejas (model_path o
## color_a/color_b) siguen funcionando como modelo quieto o caja.
func spawn_enemy(e: Dictionary) -> Node3D:
	var species := DataRegistry.get_species(String(e.species_id))
	var tint: Color = e.get("tint", Color.WHITE)
	var scale_mult := float(e.get("scale_mult", 1.0))
	var node: Node3D
	if species.has("visual"):
		var v := EnemyVisual.new()
		v.setup(species.visual, tint, e.get("eye_color", Color.WHITE), int(e.get("variant_seed", 0)))
		v.scale = Vector3.ONE * scale_mult
		v.position = cell_to_world(e.cell)
		v.rotation_degrees.y = 180.0 - int(e.get("facing", 2)) * 90.0
		world.add_child(v)
		v.play_role("dormant" if bool(e.get("dormant", false)) else "idle")
		return v
	if species.has("model_path"):
		var packed: PackedScene = load(String(species.model_path))
		var model: Node3D = packed.instantiate()
		model.scale = Vector3.ONE * float(species.model_scale) * scale_mult
		_apply_psx_material_recursive(model, tint)
		node = Node3D.new()
		node.add_child(model)
	else:
		var enemy_tex := checker_texture(species.color_a, species.color_b)
		var box := CSGBox3D.new()
		box.size = Vector3(0.8, 1.4, 0.8) * scale_mult
		box.position = Vector3(0, 0.7 * scale_mult, 0)
		box.material = make_psx_material(Color(0.9, 0.9, 0.9) * tint, enemy_tex)
		node = Node3D.new()
		node.add_child(box)
	node.position = cell_to_world(e.cell)
	# Los modelos miran hacia +Z (sur, facing 2): rotación = 180 − facing×90.
	node.rotation_degrees.y = 180.0 - int(e.get("facing", 2)) * 90.0
	world.add_child(node)
	return node

## Para cada malla del modelo arma un PsxMaterial3D que reusa la textura
## ORIGINAL (no se pierde el dibujo) con el shading/niebla PSX encima.
func _apply_psx_material_recursive(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node
		var surface_count: int = mesh_inst.mesh.get_surface_count() if mesh_inst.mesh else 0
		for i in surface_count:
			var original: Material = mesh_inst.mesh.surface_get_material(i)
			var tex: Texture2D = null
			if original is BaseMaterial3D:
				tex = (original as BaseMaterial3D).albedo_texture
			mesh_inst.set_surface_override_material(i, make_psx_material(tint, tex))
	for child in node.get_children():
		_apply_psx_material_recursive(child, tint)

func spawn_chest(cell: Vector2i, fd: FloorData) -> Node3D:
	# Mirando hacia el lado abierto de la celda (no contra la pared).
	var rot := 0.0
	for i in 4:
		var d: Vector2i = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)][i]
		if not fd.is_wall(cell + d):
			rot = [0.0, 90.0, 180.0, 270.0][i]
			break
	var chest := spawn_prop("Chest_1", cell_to_world(cell), rot)
	if chest:
		chest.scale = Vector3.ONE * 1.2
	return chest

func spawn_item(cell: Vector2i) -> Node3D:
	var holder := Node3D.new()
	var gem := CSGBox3D.new()
	gem.size = Vector3(0.28, 0.28, 0.28)
	gem.rotation_degrees = Vector3(45, 0, 45)
	gem.material = make_glow_material(ITEM_GLOW)
	gem.position = Vector3(0, 0.45, 0)
	holder.add_child(gem)
	holder.position = cell_to_world(cell)
	world.add_child(holder)
	return holder

func spawn_exit(cell: Vector2i) -> Node3D:
	var holder := Node3D.new()
	var ring := CSGCylinder3D.new()
	ring.radius = 0.75
	ring.height = 0.06
	ring.sides = 10
	ring.position = Vector3(0, 0.04, 0)
	ring.name = "Ring"
	holder.add_child(ring)
	var beam := CSGCylinder3D.new()
	beam.radius = 0.12
	beam.height = WALL_HEIGHT
	beam.sides = 6
	beam.position = Vector3(0, WALL_HEIGHT / 2.0, 0)
	beam.name = "Beam"
	holder.add_child(beam)
	holder.position = cell_to_world(cell)
	world.add_child(holder)
	set_exit_open(holder, false)
	return holder

static func set_exit_open(exit_node: Node3D, open: bool) -> void:
	var mat := make_glow_material(EXIT_OPEN if open else EXIT_SEALED)
	(exit_node.get_node("Ring") as CSGCylinder3D).material = mat
	(exit_node.get_node("Beam") as CSGCylinder3D).material = mat
	(exit_node.get_node("Beam") as CSGCylinder3D).visible = open
