extends Node
## Herramienta de desarrollo, paso 1 de 2 de los sprites de enemigos de
## prueba: renderiza los esqueletos 3D animados (los mismos de EnemyVisual,
## con armas) cuadro por cuadro, de frente, de espaldas y de los dos costados,
## y guarda los cuadros en crudo (4x el tamaño final) para que
## tools/sprites/pixelize_sprites.py los convierta en pixel art.
## Necesita display real o virtual (con --headless no renderiza):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     res://tools/sprites/bake_enemy_sprites.tscn -- --out=/tmp/sprites_raw [--only=esqueleto_esbirro]
##
## Por especie (las activas con bloque "visual" en data/species.json) deja en
## <out>/<especie>/:
##   <anim>_<dir>_<i>.png       color (luz toon de arriba a la izquierda)
##   <anim>_<dir>_<i>_glow.png  máscara de lo que brilla (los ojos), blanco/negro
##   meta.json                  cuadros, duración y si se repite, por animación
##
## Animaciones: los papeles de visual.anims (las variantes de attack/hit son
## attack, attack_2...). Direcciones: s (mira a la cámara), e (mira a la
## derecha de la pantalla), n (de espaldas), w (a la izquierda); solo idle y
## walk van en las cuatro, el resto pasa siempre de frente al jugador.

const FRAME := Vector2i(144, 144)
## Fila del cuadro (desde arriba) donde quedan los pies.
const PIVOT := Vector2i(72, 140)
const PIXELS_PER_METER := 64.0
const SS := 4
## Cuadros por papel (los que se repiten se muestrean sin repetir el último).
const FRAMES := {
	"idle": 6, "walk": 8, "combat": 6, "attack": 8, "hit": 4, "death": 10,
	"spawn": 12, "dormant": 1, "taunt": 10, "ability": 8,
}
const LOOPING: Array[String] = ["idle", "walk", "combat", "dormant"]
const ALL_DIRS: Array[String] = ["s", "e", "n", "w"]
## Giro del modelo (que mira hacia +Z, la cámara) para cada dirección.
const DIR_YAW := {"s": 0.0, "e": 90.0, "n": 180.0, "w": -90.0}

var _out := "user://sprites_raw"
var _only: PackedStringArray = []
var _vp: SubViewport
var _cam: Camera3D

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--only="):
			_only = arg.substr(7).split(",", false)
	FloorBuilder.ensure_psx_shader_globals()
	FloorBuilder.set_fog(50.0, 100.0)
	_bake_all.call_deferred()

func _bake_all() -> void:
	_make_viewport()
	for id in DataRegistry.species_ids():
		var sp := DataRegistry.get_species(id)
		if not sp.has("visual") or (not _only.is_empty() and not _only.has(id)):
			continue
		await _bake_species(id, sp.visual)
	get_tree().quit()

func _make_viewport() -> void:
	_vp = SubViewport.new()
	_vp.size = FRAME * SS
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.40, 0.48)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# Luz clave de arriba a la izquierda y algo de frente (convención del pixel art).
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 1.25
	key.look_at_from_position(Vector3(-1.0, 1.4, 1.2), Vector3.ZERO)
	_vp.add_child(key)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = FRAME.y / PIXELS_PER_METER
	_cam.position = Vector3(0, (PIVOT.y - FRAME.y / 2.0) / PIXELS_PER_METER, 20.0)
	_cam.near = 0.1
	_cam.far = 60.0
	_vp.add_child(_cam)
	add_child(_vp)

func _bake_species(id: String, def: Dictionary) -> void:
	var dir := _out.path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)
	var v := EnemyVisual.new()
	v.setup(def, Color.WHITE, Color.WHITE, 0)
	v.set_process(false)
	_vp.add_child(v)
	# Sin sombra ni luz propia: el sprite trae solo la figura.
	for c in v.get_children():
		if c is MeshInstance3D or c is Light3D:
			(c as Node3D).visible = false
	var color_mats := {}
	var glow_mats := {}
	_collect_materials(v, color_mats, glow_mats)
	var meta := {"frame": [FRAME.x, FRAME.y], "pivot": [PIVOT.x, PIVOT.y], "pixels_per_meter": PIXELS_PER_METER, "anims": {}}
	for role: String in FRAMES.keys():
		var names: Array[String] = []
		var raw: Variant = (def.anims as Dictionary).get(role, null)
		if raw == null:
			continue
		if typeof(raw) == TYPE_ARRAY:
			for n: Variant in raw:
				names.append(String(n))
		else:
			names.append(String(raw))
		for i in names.size():
			var anim_id := role if i == 0 else "%s_%d" % [role, i + 1]
			var info := await _bake_anim(v, dir, anim_id, role, names[i], color_mats, glow_mats)
			if not info.is_empty():
				meta.anims[anim_id] = info
	var f := FileAccess.open(dir.path_join("meta.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	v.queue_free()
	print("horneado: %s (%d animaciones)" % [id, (meta.anims as Dictionary).size()])

## Dos juegos de materiales por superficie: color (toon, textura original) y
## máscara de brillo (todo negro salvo los ojos, blancos).
func _collect_materials(node: Node, color_mats: Dictionary, glow_mats: Dictionary) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).visible:
		var mi: MeshInstance3D = node
		var eyes := String(mi.name).ends_with("_Eyes")
		var colors: Array[Material] = []
		var glows: Array[Material] = []
		var n: int = mi.mesh.get_surface_count() if mi.mesh else 0
		for i in n:
			var original: Material = mi.mesh.surface_get_material(i)
			var c := StandardMaterial3D.new()
			c.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			c.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			c.roughness = 1.0
			if eyes:
				c.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				c.albedo_color = Color(1.0, 0.95, 0.8)
			elif original is BaseMaterial3D:
				c.albedo_texture = (original as BaseMaterial3D).albedo_texture
				c.albedo_color = (original as BaseMaterial3D).albedo_color
			colors.append(c)
			var g := StandardMaterial3D.new()
			g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			g.albedo_color = Color.WHITE if eyes else Color.BLACK
			glows.append(g)
		color_mats[mi] = colors
		glow_mats[mi] = glows
	for c in node.get_children():
		_collect_materials(c, color_mats, glow_mats)

func _use(mats: Dictionary) -> void:
	for mi: MeshInstance3D in mats.keys():
		var arr: Array[Material] = mats[mi]
		for i in arr.size():
			mi.set_surface_override_material(i, arr[i])

func _bake_anim(v: EnemyVisual, dir: String, anim_id: String, role: String, anim_name: String, color_mats: Dictionary, glow_mats: Dictionary) -> Dictionary:
	if v.anim == null or not v.anim.has_animation(anim_name):
		push_error("bake: falta la animación %s" % anim_name)
		return {}
	var length := v.anim.get_animation(anim_name).length
	var count: int = FRAMES[role]
	var loop := role in LOOPING
	var dirs: Array[String] = ["s"]
	if role in ["idle", "walk"]:
		dirs = ALL_DIRS
	# La duración en el juego es la misma que la del clip 3D (con la velocidad
	# de visual.anim_speed, que el sprite aplica igual que el modelo).
	var info := {"frames": count, "length": length, "loop": loop, "dirs": dirs}
	v.anim.play(anim_name, 0.0)
	for d in dirs:
		v.rotation_degrees.y = DIR_YAW[d]
		for i in count:
			var t := 0.0
			if count > 1:
				t = length * i / (count if loop else count - 1)
			v.anim.seek(minf(t, length), true)
			v._apply_bone_overrides()
			var base := dir.path_join("%s_%s_%d" % [anim_id, d, i])
			_use(color_mats)
			await _capture(base + ".png")
			_use(glow_mats)
			await _capture(base + "_glow.png")
	v.rotation_degrees.y = 0.0
	return info

func _capture(path: String) -> void:
	for _i in 2:
		await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(path)
