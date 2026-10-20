extends Node
## Herramienta de desarrollo: hornea los retratos de héroes y objetos en estilo
## "render 3D con filtro PS1" (modelos y fuentes: tools/portraits/README.md).
## Necesita display real o virtual (con --headless no renderiza):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     res://tools/portraits/bake_portraits.tscn [-- --only=bjorn,venda --preview=RUTA.png --debug]
##
## Por retrato:
## 1. SubViewport propio (mundo 3D aparte, fondo transparente, sin MSAA) a
##    SUPERSAMPLE veces el tamaño final.
## 2. Materiales PSX del juego (FloorBuilder.make_psx_material: sombreado por
##    vértice, snapping, afín) con la textura original de cada modelo. Solo se
##    usan permutaciones de shader que ya existen en addons/psx/shaders/cache
##    (crear otras escribiría archivos nuevos en el addon).
## 3. Luz: clave cálida de antorcha (#ffc98a) de un costado, relleno frío
##    tenue (#3a4d7a) del otro y ambiente bajo. Niebla lejos.
## 4. Post-proceso sobre la Image: reducción por caja (promedio premultiplicado),
##    alfa binaria (0/255), fondo con degradé y viñeta para los héroes, trama
##    Bayer 4x4 a 15 bits (igual que shaders/psx_viewport_dither.gdshader:
##    31 niveles por canal, umbral Bayer/16) y, en objetos, contorno de 1 px
##    (#0a0806) en los píxeles transparentes vecinos a opacos.
## 5. PNG en assets/portraits/{heroes,items}/<id>.png y hoja de contacto
##    (todo ampliado x3, nearest; abajo, los objetos a tamaño real sobre una
##    ranura oscura como la del inventario).
##
## Opciones (después de --): --only=id1,id2  --preview=RUTA.png  --ss=N
## --debug (imprime franjas del atlas y AABB de cada modelo).

const HERO_SIZE := 96
const ITEM_SIZE := 64
const SUPERSAMPLE := 4
const OUT_HEROES := "res://assets/portraits/heroes/"
const OUT_ITEMS := "res://assets/portraits/items/"
const DEFAULT_PREVIEW := "user://portraits_preview.png"
const PREVIEW_ZOOM := 3

# Permutaciones de PsxMaterial3D ya horneadas en addons/psx/shaders/cache.
const ALLOWED_SHADERS: Array[int] = [0, 7, 42, 49, 210, 2310, 2478, 4746]

# Luz y paleta (colores de escena 3D y de la imagen, no de UI).
const KEY_COLOR := Color("#ffc98a")
const FILL_COLOR := Color("#3a4d7a")
const AMBIENT_COLOR := Color("#2a221c")
const BG_INNER := Color("#3b2f25")
const BG_OUTER := Color("#120e0b")
const OUTLINE := Color("#0a0806")
const FLAME_OUTER := Color("#ff8a2a")
const FLAME_INNER := Color("#ffe08a")
const SOUL_GLOW := Color("#6ab7d9") # = UIStyle.SOUL
const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const DITHER_LEVELS := 31.0
## Snapping de vértices proporcional al tamaño final: en el juego (preset
## "clasico") precision_xy = 160 para 240 líneas.
const SNAP_PER_LINE := 160.0 / 240.0

const DUNGEON := "res://addons/kaykit_dungeon_remastered/Assets/gltf/"
const MODELS := "res://tools/portraits/models/"

## Héroes. yaw: giro del modelo (positivo = mira hacia la derecha del cuadro).
## focus: punto que mira la cámara, relativo al hueso de la cabeza (que en
## estos modelos está en el cuello). key / fill: luces, relativas al foco.
## tints: franja del atlas -> color (conserva el degradé de la franja).
const HEROES: Array[Dictionary] = [
	{
		"id": "bjorn", "model": MODELS + "bjorn.glb", "anim": "Idle", "time": 0.0,
		# Cámara un poco más baja que los ojos: se lo ve más grande.
		"yaw": 22.0, "focus": Vector3(0, 0.3, 0), "distance": 3.7, "fov": 26.0, "pitch": 2.0,
		"key": Vector3(1.6, 1.0, 1.8), "key_energy": 2.4, "key_range": 6.0,
		"fill": Vector3(-2.2, 0.1, 0.9), "fill_energy": 1.3, "fill_range": 6.0,
		# Colmillos y piel blanca del gorro de oso: casi del marrón del gorro
		# (en blanco, a 96 px enmarcan los ojos como anteojos). Barba castaño
		# rojiza: con la gris original la cara se lavaba bajo la luz cálida.
		"tints": {Vector2i(2, 1): Color("#7a6852"), Vector2i(1, 0): Color("#64382a")},
	},
	{
		"id": "elena", "model": MODELS + "elena.glb", "anim": "Idle", "time": 0.0,
		"yaw": 28.0, "focus": Vector3(0, 0.3, 0), "distance": 3.7, "fov": 26.0, "pitch": -5.0,
		"key": Vector3(1.6, 1.0, 1.8), "key_energy": 2.4, "key_range": 6.0,
		"fill": Vector3(-2.2, 0.1, 0.9), "fill_energy": 1.3, "fill_range": 6.0,
		# Capucha y capa índigo apagado (arcana) y túnica pizarra: el verde
		# original es demasiado vivo para la paleta de catacumba.
		"tints": {Vector2i(1, 1): Color("#4b3f78"), Vector2i(0, 1): Color("#2f4a52")},
	},
]

## Objetos: lista de piezas (modelo o primitiva low-poly), giro de 3/4 y
## cuánto del cuadro ocupan ("fill"). En modelos: swaps (franja del atlas ->
## franja que la reemplaza; atlas KayKit de 8x4 franjas de 128x256 px), tints
## (franja -> color) y tint (multiplica todo el modelo).
const ITEMS: Array[Dictionary] = [
	{
		"id": "pocion_menor", "fill": 0.66, "yaw": 30.0, "pitch": -22.0, "roll": 0.0,
		"parts": [{"model": DUNGEON + "bottle_C_green.gltf.glb", "swaps": {Vector2i(0, 2): Vector2i(3, 2)}}],
	},
	{
		# Rollo de venda de lino con la tira suelta; manchas de sangre seca.
		"id": "venda", "fill": 0.86, "yaw": 34.0, "pitch": -26.0, "roll": 0.0,
		"parts": [
			{"prim": "cylinder", "radius": 0.3, "height": 0.34, "sides": 10, "rot": Vector3(0, 0, 90), "color": Color("#e2d8c4"), "tex": "lino"},
			{"prim": "cylinder", "radius": 0.2, "height": 0.36, "sides": 10, "rot": Vector3(0, 0, 90), "color": Color("#b9ad94"), "tex": "lino"},
			{"prim": "cylinder", "radius": 0.07, "height": 0.37, "sides": 6, "rot": Vector3(0, 0, 90), "color": Color("#8a7b62")},
			{"prim": "box", "size": Vector3(0.32, 0.03, 0.34), "pos": Vector3(0, -0.29, 0.3), "rot": Vector3(4, 0, 0), "color": Color("#e2d8c4"), "tex": "lino_sangre"},
			{"prim": "box", "size": Vector3(0.32, 0.03, 0.26), "pos": Vector3(0.0, -0.27, 0.58), "rot": Vector3(-14, 8, 0), "color": Color("#d8ccb4"), "tex": "lino"},
		],
	},
	{
		"id": "antorcha_vieja", "fill": 0.9, "yaw": 20.0, "pitch": -18.0, "roll": -38.0,
		"parts": [
			{"model": DUNGEON + "torch.gltf.glb", "scale": Vector3(1.3, 1.0, 1.3), "tint": Color("#c8b8a4")},
			{"prim": "prism", "size": Vector3(0.3, 0.46, 0.3), "pos": Vector3(0, 0.84, 0), "glow": FLAME_OUTER},
			{"prim": "prism", "size": Vector3(0.16, 0.3, 0.16), "pos": Vector3(0, 0.78, 0.08), "rot": Vector3(0, 45, 0), "glow": FLAME_INNER},
		],
	},
	{
		"id": "sello_retiro", "fill": 0.88, "yaw": 25.0, "pitch": -30.0, "roll": 0.0,
		"parts": [
			{"prim": "cylinder", "radius": 0.2, "height": 0.95, "sides": 8, "rot": Vector3(0, 0, 90), "color": Color("#cdb48a"), "tex": "pergamino"},
			{"prim": "cylinder", "radius": 0.23, "height": 0.08, "sides": 8, "rot": Vector3(0, 0, 90), "pos": Vector3(-0.42, 0, 0), "color": Color("#8a6a48")},
			{"prim": "cylinder", "radius": 0.23, "height": 0.08, "sides": 8, "rot": Vector3(0, 0, 90), "pos": Vector3(0.42, 0, 0), "color": Color("#8a6a48")},
			{"prim": "box", "size": Vector3(0.1, 0.42, 0.42), "pos": Vector3(0, 0, 0), "color": Color("#6e2a24")},
			{"prim": "cylinder", "radius": 0.17, "height": 0.07, "sides": 10, "rot": Vector3(90, 0, 0), "pos": Vector3(0, 0, 0.22), "color": Color("#a8302a")},
		],
	},
	{
		# Bomba redonda de hierro con mecha encendida y humo, con primitivas.
		# (Se probó la "smokebomb" del pack Adventurers: de anillos apilados,
		# a 64 px no se leía como bomba.)
		"id": "bomba_humo", "fill": 0.86, "yaw": 30.0, "pitch": -20.0, "roll": 0.0,
		"parts": [
			{"prim": "sphere", "radius": 0.3, "sides": 10, "rings": 6, "color": Color("#6a707e")},
			{"prim": "cylinder", "radius": 0.1, "height": 0.1, "sides": 8, "pos": Vector3(0, 0.3, 0), "color": Color("#6e6a62")},
			{"prim": "cylinder", "radius": 0.022, "height": 0.16, "sides": 4, "pos": Vector3(0.04, 0.41, 0), "rot": Vector3(0, 0, -28), "color": Color("#3a2c20")},
			{"prim": "sphere", "radius": 0.045, "pos": Vector3(0.08, 0.49, 0), "glow": FLAME_INNER},
			{"prim": "sphere", "radius": 0.1, "sides": 6, "pos": Vector3(0.18, 0.6, -0.04), "color": Color("#b4aea2")},
			{"prim": "sphere", "radius": 0.14, "sides": 6, "pos": Vector3(0.3, 0.76, -0.08), "color": Color("#a29c90")},
			{"prim": "sphere", "radius": 0.09, "sides": 6, "pos": Vector3(0.08, 0.76, -0.06), "color": Color("#bdb7aa")},
		],
	},
	{
		# Hueso colgado de un cordón de cuero, con una chispa de alma.
		"id": "amuleto_hueso", "fill": 0.86, "yaw": 20.0, "pitch": -20.0, "roll": 0.0,
		"parts": [
			{"prim": "torus", "inner": 0.3, "outer": 0.38, "sides": 10, "rot": Vector3(90, 0, 0), "pos": Vector3(0, 0.25, 0), "color": Color("#5a4030")},
			{"model": MODELS + "bone_a.glb", "rot": Vector3(0, 0, 90), "pos": Vector3(0, -0.28, 0), "scale": 1.15},
			{"prim": "sphere", "radius": 0.075, "pos": Vector3(0, -0.28, 0.11), "glow": SOUL_GLOW},
		],
	},
	{
		"id": "pocion_mayor", "fill": 0.9, "yaw": 30.0, "pitch": -18.0, "roll": 0.0,
		"parts": [{"model": DUNGEON + "bottle_A_labeled_brown.gltf.glb", "swaps": {Vector2i(6, 0): Vector2i(4, 1)}}],
	},
	{
		# Cráneo con brasas en las cuencas (+1 ataque).
		"id": "talisman_hueso", "fill": 0.78, "yaw": 25.0, "pitch": -15.0, "roll": 0.0,
		"parts": [
			{"model": MODELS + "skull.glb"},
			{"prim": "sphere", "radius": 0.08, "pos": Vector3(-0.19, 0.42, 0.34), "glow": FLAME_OUTER},
			{"prim": "sphere", "radius": 0.08, "pos": Vector3(0.19, 0.42, 0.34), "glow": FLAME_OUTER},
		],
	},
]

var _only: PackedStringArray = []
var _preview_path := DEFAULT_PREVIEW
var _ss := SUPERSAMPLE
var _debug := false
var _hero_images: Array[Image] = []
## Texturas recoloreadas ya hechas (varias mallas comparten el mismo atlas).
var _recolor_cache: Dictionary = {}
var _item_images: Array[Image] = []

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7).split(",", false)
		elif arg.begins_with("--preview="):
			_preview_path = arg.substr(10)
		elif arg.begins_with("--ss="):
			_ss = maxi(1, int(arg.substr(5)))
		elif arg == "--debug":
			_debug = true
	FloorBuilder.ensure_psx_shader_globals()
	FloorBuilder.set_fog(50.0, 100.0)
	_bake_all.call_deferred()

func _bake_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_HEROES))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_ITEMS))
	for job: Dictionary in HEROES:
		if _wanted(job):
			var img := await _bake_hero(job)
			_save(img, OUT_HEROES + String(job.id) + ".png")
			_hero_images.append(img)
	for job: Dictionary in ITEMS:
		if _wanted(job):
			var img := await _bake_item(job)
			_save(img, OUT_ITEMS + String(job.id) + ".png")
			_item_images.append(img)
	_save_contact_sheet()
	get_tree().quit()

func _wanted(job: Dictionary) -> bool:
	return _only.is_empty() or _only.has(String(job.id))

func _save(img: Image, res_path: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(res_path))
	print("%s %s (%dx%d)" % ["guardado" if err == OK else "ERROR al guardar", res_path, img.get_width(), img.get_height()])

# --- Escena de render ---------------------------------------------------------------

## SubViewport con su propio mundo, fondo transparente, ambiente bajo y niebla lejos.
func _make_viewport(final_size: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(final_size * _ss, final_size * _ss)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	add_child(vp)
	# Snapping de vértices como en el juego, medido en píxeles finales.
	Psx.precision_xy = SNAP_PER_LINE * final_size
	return vp

func _add_light(parent: Node, color: Color, pos: Vector3, energy: float, light_range: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.0
	l.shadow_enabled = false
	l.position = pos
	parent.add_child(l)

func _capture(vp: SubViewport) -> Image:
	for _i in 3:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img

# --- Héroes -------------------------------------------------------------------------------

func _bake_hero(job: Dictionary) -> Image:
	var vp := _make_viewport(HERO_SIZE)
	var packed: PackedScene = load(String(job.model))
	var model: Node3D = packed.instantiate()
	model.rotation_degrees.y = float(job.yaw)
	vp.add_child(model)
	_apply_psx_materials(model, {}, job.get("tints", {}))
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		anim.play(String(job.anim))
		anim.seek(float(job.time), true)
	await get_tree().process_frame
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var head := Vector3(0, 1.7, 0)
	if skeleton:
		var idx := skeleton.find_bone("head")
		if idx >= 0:
			head = skeleton.global_transform * skeleton.get_bone_global_pose(idx).origin
	var focus: Vector3 = head + (job.focus as Vector3)
	var cam := Camera3D.new()
	cam.fov = float(job.fov)
	var pitch := deg_to_rad(float(job.pitch))
	cam.position = focus + Vector3(0, -sin(pitch), cos(pitch)) * float(job.distance)
	vp.add_child(cam)
	cam.look_at(focus)
	cam.current = true
	_add_light(vp, KEY_COLOR, focus + (job.key as Vector3), float(job.key_energy), float(job.key_range))
	_add_light(vp, FILL_COLOR, focus + (job.fill as Vector3), float(job.fill_energy), float(job.fill_range))
	if _debug:
		print("%s: cabeza en %s" % [job.id, head])
	var raw := await _capture(vp)
	vp.queue_free()
	var img := _downscale(raw, _ss)
	_binarize_alpha(img)
	img = _over_background(img)
	_dither(img)
	img.convert(Image.FORMAT_RGB8)
	return img

# --- Objetos ------------------------------------------------------------------------------

func _bake_item(job: Dictionary) -> Image:
	var vp := _make_viewport(ITEM_SIZE)
	# pivot: giro de 3/4 (yaw), inclinación para leer la silueta (roll).
	var pivot := Node3D.new()
	vp.add_child(pivot)
	var holder := Node3D.new()
	pivot.add_child(holder)
	for part: Dictionary in job.parts:
		holder.add_child(_make_part(part))
	pivot.rotation_degrees = Vector3(0, float(job.yaw), float(job.roll))
	await get_tree().process_frame
	var cam := Camera3D.new()
	cam.fov = 24.0
	var pitch := deg_to_rad(float(job.pitch))
	var view_dir := Vector3(0, -sin(pitch), cos(pitch)).normalized() # de la escena hacia la cámara
	# Encuadre con los vértices reales (la AABB de un objeto girado es mucho
	# más grande que su silueta): centrar en el plano de la cámara y alejarla
	# hasta que el objeto ocupe `fill` del cuadro.
	var pts := _world_points(pivot)
	var right := Vector3.UP.cross(view_dir).normalized()
	var up := view_dir.cross(right).normalized()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var depth_lo := INF
	var depth_hi := -INF
	for p in pts:
		var q := Vector2(p.dot(right), p.dot(up))
		lo = lo.min(q)
		hi = hi.max(q)
		depth_lo = minf(depth_lo, p.dot(view_dir))
		depth_hi = maxf(depth_hi, p.dot(view_dir))
	var mid := (lo + hi) * 0.5
	var center := right * mid.x + up * mid.y + view_dir * (depth_lo + depth_hi) * 0.5
	holder.position -= pivot.global_transform.basis.inverse() * center
	var t := tan(deg_to_rad(cam.fov) * 0.5) * float(job.fill)
	var dist := 0.1
	for p in pts:
		var c := p - center
		dist = maxf(dist, maxf(absf(c.dot(right)), absf(c.dot(up))) / t + c.dot(view_dir))
	cam.position = view_dir * dist
	vp.add_child(cam)
	cam.look_at(Vector3.ZERO)
	cam.current = true
	var box := _world_aabb(pivot)
	var radius := box.size.length() * 0.5
	_add_light(vp, KEY_COLOR, Vector3(1.4, 1.2, 1.6) * maxf(radius, 0.4) * 2.0, 2.2, maxf(radius, 0.4) * 9.0)
	_add_light(vp, FILL_COLOR, Vector3(-1.8, 0.4, -0.4) * maxf(radius, 0.4) * 2.0, 1.4, maxf(radius, 0.4) * 9.0)
	if _debug:
		print("%s: aabb %s, distancia %.2f" % [job.id, box, dist])
	var raw := await _capture(vp)
	vp.queue_free()
	var img := _downscale(raw, _ss)
	_binarize_alpha(img)
	_dither(img)
	_outline(img)
	return img

func _make_part(part: Dictionary) -> Node3D:
	var node: Node3D
	if part.has("model"):
		var packed: PackedScene = load(String(part.model))
		node = packed.instantiate()
		_apply_psx_materials(node, part.get("swaps", {}), part.get("tints", {}), part.get("tint", Color.WHITE))
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = _make_primitive(part)
		if part.has("glow"):
			mi.material_override = FloorBuilder.make_glow_material(part.glow)
		else:
			var tex: Texture2D = _procedural_texture(String(part.get("tex", "")))
			mi.material_override = _checked(FloorBuilder.make_psx_material(part.get("color", Color.WHITE), tex))
		node = mi
	node.position = part.get("pos", Vector3.ZERO)
	node.rotation_degrees = part.get("rot", Vector3.ZERO)
	var s: Variant = part.get("scale", 1.0)
	if s is Vector3:
		node.scale = s
	else:
		node.scale = Vector3.ONE * float(s)
	return node

func _make_primitive(part: Dictionary) -> Mesh:
	match String(part.prim):
		"cylinder":
			var m := CylinderMesh.new()
			m.top_radius = float(part.get("top", part.radius))
			m.bottom_radius = float(part.radius)
			m.height = float(part.height)
			m.radial_segments = int(part.get("sides", 8))
			m.rings = 1
			return m
		"box":
			var m := BoxMesh.new()
			m.size = part.size
			return m
		"sphere":
			var m := SphereMesh.new()
			m.radius = float(part.radius)
			m.height = float(part.radius) * 2.0
			m.radial_segments = int(part.get("sides", 8))
			m.rings = int(part.get("rings", 4))
			return m
		"torus":
			var m := TorusMesh.new()
			m.inner_radius = float(part.inner)
			m.outer_radius = float(part.outer)
			m.rings = int(part.get("sides", 10))
			m.ring_segments = 4
			return m
		_:
			var m := PrismMesh.new()
			m.size = part.size
			return m

## Texturas chicas por código para las primitivas (tela, pergamino).
func _procedural_texture(kind: String) -> Texture2D:
	if kind == "":
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	const N := 16
	var img := Image.create(N, N, false, Image.FORMAT_RGB8)
	for y in N:
		for x in N:
			var v := 0.9 + rng.randf() * 0.1
			var c := Color(v, v, v)
			if kind.begins_with("lino"):
				# Tejido: líneas de trama cada 4 px.
				if y % 4 == 0:
					c = c * 0.84
				if kind == "lino_sangre" and Vector2(x - 9, y - 7).length() < 3.6 + rng.randf():
					c = Color(0.55, 0.16, 0.12) # sangre seca
			elif kind == "pergamino":
				if x % 5 == 0:
					c = c * 0.88
			c.a = 1.0
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

## Materiales PSX como en el juego (scripts/world/enemy_visual.gd), con la
## textura original; `swaps` / `tints` recolorean franjas del atlas en una
## copia de la textura; `tint` multiplica el color de todo el modelo.
func _apply_psx_materials(node: Node, swaps: Dictionary, tints: Dictionary, tint := Color.WHITE) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var n: int = mi.mesh.get_surface_count() if mi.mesh else 0
		for i in n:
			var original: Material = mi.mesh.surface_get_material(i)
			var tex: Texture2D = null
			if original is BaseMaterial3D:
				tex = (original as BaseMaterial3D).albedo_texture
			if tex and not (swaps.is_empty() and tints.is_empty()):
				var key := "%d|%s|%s" % [tex.get_instance_id(), swaps, tints]
				if not _recolor_cache.has(key):
					_recolor_cache[key] = _recolor_atlas(tex, swaps, tints)
				tex = _recolor_cache[key]
			if _debug:
				_print_swatches(mi, i)
			mi.set_surface_override_material(i, _checked(FloorBuilder.make_psx_material(tint, tex)))
	for c in node.get_children():
		_apply_psx_materials(c, swaps, tints, tint)

func _checked(mat: PsxMaterial3D) -> PsxMaterial3D:
	var idx := mat.get_shader_index()
	if not ALLOWED_SHADERS.has(idx):
		push_error("bake_portraits: permutación PSX %d no horneada (no se crea)" % idx)
	return mat

## Copia de la textura con franjas cambiadas: swaps copia otra franja del
## mismo atlas; tints pinta la franja del color pedido conservando su degradé
## (cada píxel = color * luminancia del píxel / luminancia media de la franja).
func _recolor_atlas(tex: Texture2D, swaps: Dictionary, tints: Dictionary) -> Texture2D:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	var src := img.duplicate() as Image
	var cell := Vector2i(floori(img.get_width() / 8.0), floori(img.get_height() / 4.0))
	for from: Vector2i in swaps.keys():
		var to: Vector2i = swaps[from]
		img.blit_rect(src, Rect2i(to * cell, cell), from * cell)
	for at: Vector2i in tints.keys():
		var color: Color = tints[at]
		var origin := at * cell
		var mean := 0.0
		for y in cell.y:
			for x in cell.x:
				mean += src.get_pixel(origin.x + x, origin.y + y).get_luminance()
		mean = maxf(mean / float(cell.x * cell.y), 0.001)
		for y in cell.y:
			for x in cell.x:
				var k := src.get_pixel(origin.x + x, origin.y + y).get_luminance() / mean
				img.set_pixel(origin.x + x, origin.y + y, Color(color.r * k, color.g * k, color.b * k))
	return ImageTexture.create_from_image(img)

func _print_swatches(mi: MeshInstance3D, surface: int) -> void:
	var arrays: Array = mi.mesh.surface_get_arrays(surface)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var hist := {}
	for uv in uvs:
		var k := Vector2i(floori(uv.x * 8.0), floori(uv.y * 4.0))
		hist[k] = int(hist.get(k, 0)) + 1
	print("  %s superficie %d: franjas %s" % [mi.name, surface, hist])

## Caja que envuelve todas las mallas bajo `root` (coordenadas del mundo).
func _world_aabb(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in _meshes(root):
		var b := mi.global_transform * mi.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box

## Vértices (de los triángulos) de todas las mallas bajo `root`, en el mundo.
func _world_points(root: Node) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for mi: MeshInstance3D in _meshes(root):
		var xf := mi.global_transform
		for v in mi.mesh.get_faces():
			pts.append(xf * v)
	return pts

func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root as MeshInstance3D)
	for c in root.get_children():
		out.append_array(_meshes(c))
	return out

# --- Post-proceso (Image) ---------------------------------------------------------------

## Reducción por caja con promedio premultiplicado (los bordes no se oscurecen).
func _downscale(src: Image, factor: int) -> Image:
	var w := floori(src.get_width() / float(factor))
	var h := floori(src.get_height() / float(factor))
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var area := float(factor * factor)
	for y in h:
		for x in w:
			var acc := Vector3.ZERO
			var a := 0.0
			for dy in factor:
				for dx in factor:
					var c := src.get_pixel(x * factor + dx, y * factor + dy)
					acc += Vector3(c.r, c.g, c.b) * c.a
					a += c.a
			var col := acc / a if a > 0.0 else Vector3.ZERO
			out.set_pixel(x, y, Color(col.x, col.y, col.z, a / area))
	return out

func _binarize_alpha(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			c.a = 1.0 if c.a >= 0.5 else 0.0
			img.set_pixel(x, y, c)

## Fondo de catacumba: degradé radial ocre muy oscuro con viñeta, más claro
## detrás de la cabeza y del lado de la antorcha.
func _over_background(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var center := Vector2(w * 0.58, h * 0.36)
	var reach := float(w) * 0.75
	for y in h:
		for x in w:
			var d := clampf(Vector2(x + 0.5, y + 0.5).distance_to(center) / reach, 0.0, 1.0)
			var bg := BG_INNER.lerp(BG_OUTER, smoothstep(0.0, 1.0, d))
			var c := img.get_pixel(x, y)
			out.set_pixel(x, y, c if c.a > 0.0 else bg)
	return out

## Trama Bayer 4x4 a 15 bits (5 por canal), solo en píxeles opacos.
func _dither(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var norm := BAYER[(x & 3) + (y & 3) * 4] / 16.0
			c.r = _quantize(c.r, norm)
			c.g = _quantize(c.g, norm)
			c.b = _quantize(c.b, norm)
			img.set_pixel(x, y, c)

func _quantize(v: float, norm: float) -> float:
	return minf(floorf((v + norm / DITHER_LEVELS) * DITHER_LEVELS), DITHER_LEVELS) / DITHER_LEVELS

## Contorno de 1 px: píxeles transparentes con un vecino (4 direcciones) opaco.
func _outline(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate() as Image
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p := Vector2i(x, y) + d
				if p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and src.get_pixelv(p).a > 0.0:
					img.set_pixel(x, y, OUTLINE)
					break

# --- Hoja de contacto -----------------------------------------------------------------

func _save_contact_sheet() -> void:
	const PAD := 12
	var hero_cell := HERO_SIZE * PREVIEW_ZOOM
	var item_cell := ITEM_SIZE * PREVIEW_ZOOM
	var cols := 4
	var item_rows := ceili(_item_images.size() / float(cols))
	var w := PAD + maxi(2 * (hero_cell + PAD), cols * (item_cell + PAD))
	var h := PAD + hero_cell + PAD + item_rows * (item_cell + PAD) + HERO_SIZE + PAD
	var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(UIStyle.BG_DEEP)
	for i in _hero_images.size():
		var big := _zoomed(_hero_images[i])
		sheet.blit_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(PAD + i * (hero_cell + PAD), PAD))
	var y0 := PAD + hero_cell + PAD
	for i in _item_images.size():
		var pos := Vector2i(PAD + (i % cols) * (item_cell + PAD), y0 + floori(i / float(cols)) * (item_cell + PAD))
		sheet.fill_rect(Rect2i(pos, Vector2i(item_cell, item_cell)), UIStyle.PANEL)
		var big := _zoomed(_item_images[i])
		sheet.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), pos)
	# Tamaño real, sobre ranuras oscuras (como en el inventario).
	var y1 := y0 + item_rows * (item_cell + PAD)
	for i in _item_images.size():
		var pos := Vector2i(PAD + i * (ITEM_SIZE + 6), y1)
		sheet.fill_rect(Rect2i(pos - Vector2i(2, 2), Vector2i(ITEM_SIZE + 4, ITEM_SIZE + 4)), UIStyle.BORDER)
		sheet.fill_rect(Rect2i(pos, Vector2i(ITEM_SIZE, ITEM_SIZE)), UIStyle.PANEL)
		sheet.blend_rect(_item_images[i], Rect2i(Vector2i.ZERO, _item_images[i].get_size()), pos)
	for i in _hero_images.size():
		var pos := Vector2i(PAD + _item_images.size() * (ITEM_SIZE + 6) + i * (HERO_SIZE + 6), y1)
		if pos.x + HERO_SIZE <= w:
			var hero := _hero_images[i].duplicate() as Image
			hero.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(hero, Rect2i(Vector2i.ZERO, hero.get_size()), pos)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_preview_path).get_base_dir())
	var err := sheet.save_png(ProjectSettings.globalize_path(_preview_path))
	print("hoja de contacto: %s (%s)" % [ProjectSettings.globalize_path(_preview_path), "ok" if err == OK else "ERROR"])

func _zoomed(img: Image) -> Image:
	var big := img.duplicate() as Image
	big.convert(Image.FORMAT_RGBA8)
	big.resize(img.get_width() * PREVIEW_ZOOM, img.get_height() * PREVIEW_ZOOM, Image.INTERPOLATE_NEAREST)
	return big
