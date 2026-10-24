class_name FloorBuilder
extends RefCounted
## Vuelve 3D un FloorData con el BIOMA del piso (data/floors.json → themes),
## en estilo PS1 / Lunacid:
## - Geometría: una malla por bloque de CHUNK×CHUNK celdas (así cada bloque
##   tiene su propia lista de luces), con las caras de 2×2 m subdivididas en
##   SUBDIV×SUBDIV: la luz por vértice dibuja el "charco" de las antorchas y la
##   deformación afín de las texturas no se exagera (lo mismo hacían en PS1).
## - Texturas del bioma (assets/textures/<tema>/, ver tools/assets): UV en
##   coordenadas de mundo, una textura cada TEX_WORLD metros, repetida sin
##   costura; algunas caras usan la variante (_b) para romper la repetición.
## - Colores de vértice = oclusión ambiental falsa horneada (uniones
##   piso-pared, rincones, techo más oscuro) + ruido de ±8%. Truco de PS1.
## - Luz: sin "sol" (solo luz de luna en su bioma). Ambiente tintado, niebla
##   del mismo color que el fondo, antorchas de pared con parpadeo escalonado.
## - Columnas de 8 lados con la textura del bioma; antorchas de KayKit Dungeon
##   Remastered (CC0). Props: pack PSX de cajas/barriles. Enemigos, cofres,
##   objetos sueltos y salida.
##
## Los nodos (jugador, enemigos) van al CENTRO de la celda: cell_to_world().

const CELL_SIZE := 2.0
const WALL_HEIGHT := 2.0
## Subdivisiones por lado de cada cara (4 → quads de 0,5 m).
const SUBDIV := 4
## Celdas por lado de cada bloque de malla.
const CHUNK := 8
## Metros que cubre una textura (128 px → 32 texeles por metro).
const TEX_WORLD := 4.0
const TEXTURE_SLOTS: Array[String] = ["wall_a", "wall_b", "floor_a", "floor_b", "ceiling"]
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

# Oclusión falsa: [mínimo, alcance en metros].
const AO_FLOOR := Vector2(0.55, 0.8)
const AO_WALL_BOTTOM := Vector2(0.6, 0.8)
const AO_WALL_TOP := Vector2(0.75, 0.5)
const AO_CORNER := Vector2(0.7, 0.6)
const CEILING_DARK := 0.8
const VERTEX_NOISE := 0.08

const TORCH_SCENE := "res://addons/kaykit_dungeon_remastered/Assets/gltf/torch_mounted.gltf.glb"
const TORCH_HEIGHT := 1.25

# Colores del MUNDO 3D (la UI usa UIStyle; estos son materiales de escena).
const ITEM_GLOW := Color(0.95, 0.72, 0.3)
const EXIT_SEALED := Color(0.55, 0.12, 0.12)
const EXIT_OPEN := Color(0.35, 0.75, 0.95)

var world: Node3D
## Bioma: DataRegistry.get_theme() (niebla, ambiente, texturas, antorchas).
var theme: Dictionary
var _mats: Dictionary = {}          # slot de TEXTURE_SLOTS -> PsxMaterial3D
var _props_template: Node3D = null
var _flame_mat: PsxMaterial3D = null

## Arrays de una superficie (un material) de un bloque de malla.
class SurfaceArrays:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

static func cell_to_world(cell: Vector2i, y := 0.0) -> Vector3:
	return Vector3(cell.x * CELL_SIZE + CELL_SIZE / 2.0, y, cell.y * CELL_SIZE + CELL_SIZE / 2.0)

## El plugin PSX registra sus parámetros globales de shader desde el EDITOR
## (EditorPlugin._enter_tree), algo que una partida jugada nunca recibe. Sin
## esto el shader referencia globals inexistentes (pantalla negra). Solo se
## agregan los que falten: project.godot ya declara los suyos.
static func ensure_psx_shader_globals() -> void:
	var defaults := {
		&"psx_affine_strength": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.6],
		&"psx_bit_depth": [RenderingServer.GLOBAL_VAR_TYPE_INT, 0],
		&"psx_fog_color": [RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.05, 0.05, 0.08, 1.0)],
		&"psx_fog_far": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 16.0],
		&"psx_fog_near": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 5.0],
		&"psx_precision_uv": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		&"psx_precision_xy": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 160.0],
		&"psx_precision_z": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
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

## Sin sombrear (se ve en la oscuridad). `fog` = false: tampoco lo tapa la
## niebla (los ojos de los enemigos se ven antes que el cuerpo).
static func make_glow_material(color: Color, fog := true) -> PsxMaterial3D:
	var mat := make_psx_material(color)
	mat.shading_mode = 0 # Unshaded
	if not fog:
		mat.fog_mode = PsxMaterial3D.FogMode.DISABLED
	mat.emission_enabled = true
	mat.emission = color
	mat.refresh_shader()
	return mat

## Damero por código (sin archivos): placeholder de las especies viejas.
static func checker_texture(color_a: Color, color_b: Color, tiles: int = 4) -> ImageTexture:
	var img := Image.create(tiles, tiles, false, Image.FORMAT_RGB8)
	for y in tiles:
		for x in tiles:
			img.set_pixel(x, y, color_a if (x + y) % 2 == 0 else color_b)
	return ImageTexture.create_from_image(img)

## Niebla PSX (globals del shader). El color va aparte: set_fog_color().
static func set_fog(near: float, far: float) -> void:
	Psx.fog_near = near
	Psx.fog_far = far

static func set_fog_color(color: Color) -> void:
	Psx.fog_color = Color(color.r, color.g, color.b, 1.0)

func _init(p_world: Node3D, p_theme: Dictionary = {}) -> void:
	world = p_world
	theme = p_theme if not p_theme.is_empty() else DataRegistry.get_theme(1)
	ensure_psx_shader_globals()
	for slot in TEXTURE_SLOTS:
		_mats[slot] = make_psx_material(Color.WHITE, _load_texture(slot))

## Textura del bioma; si falta (o no hay bioma) un gris liso, para no romper.
func _load_texture(slot: String) -> Texture2D:
	var path := String(theme.get("texturas", "")) + slot + ".png"
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		return tex
	push_warning("FloorBuilder: falta la textura '%s'" % path)
	var grey := 0.35 if slot != "ceiling" else 0.18
	return checker_texture(Color(grey, grey, grey), Color(grey * 0.85, grey * 0.85, grey * 0.85), 2)

## Libera la plantilla de props (nunca entra al árbol: nadie más la libera).
func dispose() -> void:
	if _props_template:
		_props_template.free()
		_props_template = null

# --- Geometría ----------------------------------------------------------------------

## Piso, techo y paredes de cada celda de PISO (la "pared" es la cara de la
## celda de piso que da a una celda de pared, mirando hacia adentro).
func build_blocks(fd: FloorData) -> void:
	var chunks := {} # Vector2i -> {slot: SurfaceArrays}
	var wall_var := float(theme.get("variante_pared", 0.15))
	var floor_var := float(theme.get("variante_piso", 0.2))
	for y in fd.height:
		for x in fd.width:
			var cell := Vector2i(x, y)
			if fd.is_wall(cell):
				continue
			var key := Vector2i(floori(x / float(CHUNK)), floori(y / float(CHUNK)))
			if not chunks.has(key):
				chunks[key] = {}
			var surfs: Dictionary = chunks[key]
			var o := Vector3(x * CELL_SIZE, 0.0, y * CELL_SIZE)
			var h := fd.ceiling_at(cell)
			var floor_slot := "floor_b" if _roll(fd, cell, 4) < floor_var else "floor_a"
			_add_face(fd, cell, _surface(surfs, floor_slot), o, Vector3(CELL_SIZE, 0, 0), Vector3(0, 0, CELL_SIZE), Vector3.UP, -1)
			_add_face(fd, cell, _surface(surfs, "ceiling"), o + Vector3(CELL_SIZE, h, 0), Vector3(-CELL_SIZE, 0, 0), Vector3(0, 0, CELL_SIZE), Vector3.DOWN, -2)
			for d in DIRS.size():
				# Pared entera contra una celda de pared; contra una celda de piso
				# de techo más bajo, solo la franja de arriba (el dintel).
				var bottom := 0.0
				if not fd.is_wall(cell + DIRS[d]):
					bottom = fd.ceiling_at(cell + DIRS[d])
					if bottom >= h:
						continue
				var slot := "wall_b" if _roll(fd, cell, d) < wall_var else "wall_a"
				# Esquina superior izquierda vista desde adentro y eje "derecha".
				var origin: Vector3
				var right: Vector3
				match d:
					0: # norte: se mira hacia -Z
						origin = o + Vector3(0, h, 0)
						right = Vector3(CELL_SIZE, 0, 0)
					1: # este: se mira hacia +X
						origin = o + Vector3(CELL_SIZE, h, 0)
						right = Vector3(0, 0, CELL_SIZE)
					2: # sur: se mira hacia +Z
						origin = o + Vector3(CELL_SIZE, h, CELL_SIZE)
						right = Vector3(-CELL_SIZE, 0, 0)
					_: # oeste: se mira hacia -X
						origin = o + Vector3(0, h, CELL_SIZE)
						right = Vector3(0, 0, -CELL_SIZE)
				var normal := -Vector3(DIRS[d].x, 0, DIRS[d].y)
				var rows := maxi(1, ceili(SUBDIV * (h - bottom) / CELL_SIZE))
				_add_face(fd, cell, _surface(surfs, slot), origin, right, Vector3(0, bottom - h, 0), normal, d, rows)
	for key: Vector2i in chunks.keys():
		var mesh := ArrayMesh.new()
		var surfs: Dictionary = chunks[key]
		for slot in TEXTURE_SLOTS:
			if not surfs.has(slot):
				continue
			var s: SurfaceArrays = surfs[slot]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = s.verts
			arrays[Mesh.ARRAY_NORMAL] = s.normals
			arrays[Mesh.ARRAY_TEX_UV] = s.uvs
			arrays[Mesh.ARRAY_COLOR] = s.colors
			arrays[Mesh.ARRAY_INDEX] = s.indices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _mats[slot])
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.name = "Bloque_%d_%d" % [key.x, key.y]
		world.add_child(inst)

func _surface(surfs: Dictionary, slot: String) -> SurfaceArrays:
	if not surfs.has(slot):
		surfs[slot] = SurfaceArrays.new()
	return surfs[slot]

## Número estable en [0, 1) por cara (misma semilla de piso = mismas variantes).
func _roll(fd: FloorData, cell: Vector2i, face: int) -> float:
	return float(absi(hash([fd.floor_n, cell, face])) % 1000) / 1000.0

## Una cara subdividida: `origin` = esquina superior izquierda vista desde el
## frente, `right`/`down` = sus lados. Triángulos en sentido horario visto de
## frente (la cara visible en Godot). face: 0-3 pared en DIRS[face], -1 piso,
## -2 techo.
func _add_face(fd: FloorData, cell: Vector2i, s: SurfaceArrays, origin: Vector3, right: Vector3, down: Vector3, normal: Vector3, face: int, rows := SUBDIV) -> void:
	var base := s.verts.size()
	for j in rows + 1:
		for i in SUBDIV + 1:
			var p := origin + right * (float(i) / SUBDIV) + down * (float(j) / rows)
			s.verts.append(p)
			s.normals.append(normal)
			s.uvs.append(_uv(p, face))
			var shade := _ao(fd, cell, p, face) * (1.0 + (_noise(p) - 0.5) * 2.0 * VERTEX_NOISE)
			s.colors.append(Color(shade, shade, shade))
	var row := SUBDIV + 1
	for j in rows:
		for i in SUBDIV:
			var a := base + j * row + i
			s.indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])

## UV de mundo: la textura se repite cada TEX_WORLD metros y no se corta entre
## celdas. En las paredes v crece hacia abajo, anclada al piso (paredes de
## distinta altura comparten las hiladas de abajo).
func _uv(p: Vector3, face: int) -> Vector2:
	match face:
		-1, -2:
			return Vector2(p.x, p.z) / TEX_WORLD
		0, 2:
			return Vector2(p.x, -p.y) / TEX_WORLD
		_:
			return Vector2(p.z, -p.y) / TEX_WORLD

## Oclusión ambiental falsa de un vértice (1 = sin oscurecer).
func _ao(fd: FloorData, cell: Vector2i, p: Vector3, face: int) -> float:
	var o := Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE)
	var q := Vector2(p.x, p.z)
	if face < 0:
		# Piso y techo: se oscurecen al acercarse a cualquiera de las 8 vecinas
		# que sean pared (borde o esquina).
		var fao := 1.0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if (dx == 0 and dy == 0) or not fd.is_wall(cell + Vector2i(dx, dy)):
					continue
				var r := Rect2(o + Vector2(dx, dy) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))
				fao *= _falloff(_dist_to_rect(q, r), AO_FLOOR)
		return fao * (CEILING_DARK if face == -2 else 1.0)
	# Pared: abajo (unión con el piso), arriba (techo) y rincones con las
	# paredes perpendiculares de la misma celda.
	var ao := _falloff(p.y, AO_WALL_BOTTOM) * _falloff(fd.ceiling_at(cell) - p.y, AO_WALL_TOP)
	for side: int in [1, 3]:
		var d2: Vector2i = DIRS[(face + side) % 4]
		if not fd.is_wall(cell + d2):
			continue
		var r := Rect2(o + Vector2(d2) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))
		ao *= _falloff(_dist_to_rect(q, r), AO_CORNER)
	return ao

static func _falloff(dist: float, ao: Vector2) -> float:
	return lerpf(ao.x, 1.0, smoothstep(0.0, ao.y, dist))

static func _dist_to_rect(q: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - q.x, 0.0), q.x - r.end.x)
	var dy := maxf(maxf(r.position.y - q.y, 0.0), q.y - r.end.y)
	return Vector2(dx, dy).length()

## Ruido estable por posición (vértices compartidos entre caras dan lo mismo).
static func _noise(p: Vector3) -> float:
	var k := Vector3i(roundi(p.x * 100.0), roundi(p.y * 100.0), roundi(p.z * 100.0))
	return float(absi(hash(k)) % 1024) / 1024.0

## Columnas decorativas (no bloquean: is_wall() no las conoce): prisma de 8
## lados con basa y capitel cuadrados, hecho con la textura de pared del
## bioma (así combina con el resto) y oclusión falsa abajo.
func build_pillars(fd: FloorData) -> void:
	if fd.pillars.is_empty():
		return
	for pos in fd.pillars:
		var h := fd.ceiling_at(Vector2i(floori(pos.x / CELL_SIZE), floori(pos.z / CELL_SIZE)))
		var s := SurfaceArrays.new()
		_append_prism(s, pos, 0.3, 0.32, h - 0.32, 8)
		_append_prism(s, pos, 0.42, 0.0, 0.32, 4, PI / 4.0)
		_append_prism(s, pos, 0.42, h - 0.32, h, 4, PI / 4.0)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.verts
		arrays[Mesh.ARRAY_NORMAL] = s.normals
		arrays[Mesh.ARRAY_TEX_UV] = s.uvs
		arrays[Mesh.ARRAY_COLOR] = s.colors
		arrays[Mesh.ARRAY_INDEX] = s.indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _mats["wall_a"])
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		world.add_child(inst)

## Prisma vertical de `sides` caras (sin tapas: van contra piso y techo o las
## tapa la basa). Caras planas (normales por cara: facetado PS1), UV de mundo
## alrededor y en altura, y más oscuro abajo.
func _append_prism(s: SurfaceArrays, center: Vector3, radius: float, y0: float, y1: float, sides: int, phase := 0.0) -> void:
	var rows := maxi(1, ceili((y1 - y0) / 0.5))
	for k in sides:
		var a0 := phase + TAU * k / sides
		var a1 := phase + TAU * (k + 1) / sides
		var p0 := center + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := center + Vector3(cos(a1), 0, sin(a1)) * radius
		var normal := Vector3(cos((a0 + a1) / 2.0), 0, sin((a0 + a1) / 2.0))
		var u0 := radius * a0
		var u1 := radius * a1
		var base := s.verts.size()
		for j in rows + 1:
			var y := lerpf(y1, y0, float(j) / rows)
			for p: Vector3 in [p0, p1]:
				s.verts.append(Vector3(p.x, y, p.z))
				s.normals.append(normal)
			s.uvs.append(Vector2(u0, -y) / TEX_WORLD)
			s.uvs.append(Vector2(u1, -y) / TEX_WORLD)
			var shade := _falloff(y, AO_WALL_BOTTOM)
			s.colors.append(Color(shade, shade, shade))
			s.colors.append(Color(shade, shade, shade))
		# Vista desde afuera, p0 → p1 va de derecha a izquierda (sentido
		# antihorario visto desde arriba): triángulos horarios vistos de frente.
		for j in rows:
			var a := base + j * 2
			s.indices.append_array([a + 1, a, a + 3, a, a + 2, a + 3])

## Ambiente tintado del bioma, sin "sol" (solo luz de luna donde la hay), y
## niebla del MISMO color que el fondo (si no, se ve un halo al final de los
## pasillos).
func build_lighting() -> void:
	var fog: Color = theme.get("niebla", Color(0.05, 0.05, 0.08))
	if theme.has("luna"):
		var moon_def: Dictionary = theme.luna
		var moon := DirectionalLight3D.new()
		moon.rotation_degrees = Vector3(-70, -30, 0)
		moon.light_color = moon_def.get("color", Color.WHITE)
		moon.light_energy = float(moon_def.get("energia", 0.3))
		moon.shadow_enabled = false
		world.add_child(moon)
	var ambient := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = fog
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = theme.get("ambiente", Color(0.25, 0.25, 0.28))
	env.ambient_light_energy = float(theme.get("ambiente_energia", 0.5))
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# La niebla la maneja el plugin PSX con sus globals; la nativa duplicaría.
	env.fog_enabled = false
	ambient.environment = env
	world.add_child(ambient)
	set_fog_color(fog)
	set_fog(float(theme.get("niebla_cerca", 5.0)), float(theme.get("niebla_lejos", 16.0)))

## Antorchas de pared (KayKit, CC0): soporte, llama sin sombrear y una luz
## cálida con parpadeo escalonado.
func build_torches(fd: FloorData) -> void:
	var packed: PackedScene = load(TORCH_SCENE) if ResourceLoader.exists(TORCH_SCENE) else null
	var color: Color = theme.get("antorcha", Color(1.0, 0.6, 0.25))
	for t: Dictionary in fd.torches:
		var d := int(t.dir)
		var dir := DIRS[d]
		var holder := Node3D.new()
		holder.position = cell_to_world(t.cell, TORCH_HEIGHT) + Vector3(dir.x, 0, dir.y) * (CELL_SIZE / 2.0)
		# El modelo sale de la pared hacia +Z: girarlo para que mire a la celda.
		holder.rotation_degrees.y = -d * 90.0
		world.add_child(holder)
		if packed:
			var model: Node3D = packed.instantiate()
			model.scale = Vector3.ONE * 0.5
			_apply_psx_material_recursive(model, Color.WHITE)
			holder.add_child(model)
		var flame := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.09, 0.16, 0.09)
		flame.mesh = prism
		flame.position = Vector3(0, 0.42, 0.2)
		flame.material_override = _get_flame_material(color)
		holder.add_child(flame)
		var light := FlickerLight.make(color, 1.8, 5.0, 1.2, 0.12, 12.0)
		light.position = Vector3(0, 0.45, 0.5)
		holder.add_child(light)

func _get_flame_material(color: Color) -> PsxMaterial3D:
	if _flame_mat == null:
		_flame_mat = make_glow_material(color.lightened(0.35))
	return _flame_mat

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

## Especies con bloque "visual" → EnemySprite (pixel art, si la especie tiene
## visual.sprite y el ajuste "enemy_style" es "sprite") o EnemyVisual (modelo
## animado). Arranca en "idle" o tirado en el piso si está dormido. Las viejas
## (model_path o color_a/color_b) siguen funcionando como modelo quieto o caja.
func spawn_enemy(e: Dictionary) -> Node3D:
	var species := DataRegistry.get_species(String(e.species_id))
	var tint: Color = e.get("tint", Color.WHITE)
	var scale_mult := float(e.get("scale_mult", 1.0))
	var node: Node3D
	if species.has("visual"):
		var v: EnemyBody
		if use_sprites(species.visual):
			v = EnemySprite.new()
		else:
			v = EnemyVisual.new()
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

## Pixel art o modelo 3D: Opciones → Enemigos (por defecto, balance.json →
## render.enemy_style_default). Solo especies con hoja (visual.sprite).
static func use_sprites(visual: Dictionary) -> bool:
	var style := String(MetaState.settings.get("enemy_style", DataRegistry.bal("render.enemy_style_default", "sprite")))
	return style == "sprite" and visual.has("sprite")

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
