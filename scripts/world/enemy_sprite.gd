class_name EnemySprite
extends EnemyBody
## Enemigo como sprite de pixel art en el mundo 3D (estilo HD-2D): un quad que
## siempre mira a la cámara, con el cuadro de la hoja que toca según el papel
## de animación y hacia dónde mira el enemigo respecto del jugador (de frente,
## de espaldas o de costado). Lo iluminan las antorchas y le llega la niebla
## PSX como al resto (shaders/enemy_sprite.gdshader).
##
## La hoja sale de visual.sprite (JSON + PNG; formato en tools/sprites/README.md).
## Hoy las hojas son de prueba, horneadas desde los modelos 3D por
## tools/sprites/; el arte definitivo las reemplaza con el mismo formato.
##
## Direcciones de la hoja (hacia dónde mira el enemigo respecto de la
## cámara): s de frente, se tres cuartos a la derecha de la pantalla, e de
## perfil a la derecha, ne de espaldas a la derecha, n de espaldas, y nw, w,
## sw del otro lado. Se usa la más cercana que traiga la hoja, contando las
## espejadas (w sale de e espejado, sw de se...): una hoja de solo s, e y n
## también sirve.

const SHADER := preload("res://shaders/enemy_sprite.gdshader")
## Ángulo de cada dirección (0 = mira a la cámara, + hacia la derecha de la pantalla).
const DIR_ANGLES := {"s": 0.0, "se": 45.0, "e": 90.0, "ne": 135.0, "n": 180.0, "nw": -135.0, "w": -90.0, "sw": -45.0}
## Cuánto dura el destello blanco de un golpe (dos pasos).
const FLASH_STEP := 0.06

## Hojas ya cargadas: ruta del JSON -> {meta, sheet, glow}.
static var _cache: Dictionary = {}

var meta: Dictionary = {}
var quad: MeshInstance3D
var mat: ShaderMaterial
var anim_speed: Dictionary = {}
var _anim := ""
var _then := "idle"
var _t := 0.0
var _speed := 1.0
## Hacia dónde mira respecto de la cámara, en grados (ver DIR_ANGLES).
var _angle := 0.0
var _shown := -1
var _shown_flip := false
var _flip := false
var _dead := false
var _done := false
var _flash_t := 0.0
var _frame_uv := Vector2.ONE
var _columns := 1
var _rng := RandomNumberGenerator.new()

## Carga (una vez) el JSON de una hoja y sus texturas. Vacío si algo falla.
static func load_sheet(json_path: String) -> Dictionary:
	if _cache.has(json_path):
		return _cache[json_path]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("EnemySprite: no se pudo leer %s" % json_path)
		return {}
	var m: Dictionary = parsed
	var dir := json_path.get_base_dir()
	var sheet: Texture2D = load(dir.path_join(String(m.get("sheet", ""))))
	var glow: Texture2D = null
	if m.has("glow") and ResourceLoader.exists(dir.path_join(String(m.glow))):
		glow = load(dir.path_join(String(m.glow)))
	var data := {"meta": m, "sheet": sheet, "glow": glow}
	_cache[json_path] = data
	return data

func setup(def: Dictionary, tint: Color, eye: Color, variant_seed: int) -> void:
	_rng.seed = variant_seed
	anim_speed = def.get("anim_speed", {})
	var data := load_sheet(String(def.sprite))
	if data.is_empty() or data.sheet == null:
		return
	meta = data.meta
	var sheet: Texture2D = data.sheet
	var frame: Array = meta.get("frame", [128, 128])
	var pivot: Array = meta.get("pivot", [64, 124])
	var fw := float(frame[0])
	var fh := float(frame[1])
	var ppm := float(meta.get("pixels_per_meter", 64.0))
	_columns = maxi(1, int(meta.get("columns", 1)))
	_frame_uv = Vector2(fw / sheet.get_width(), fh / sheet.get_height())
	# Quad del tamaño del cuadro, con los pies (pivot) en el origen del nodo.
	var q := QuadMesh.new()
	q.size = Vector2(fw, fh) / ppm
	q.center_offset = Vector3((fw / 2.0 - float(pivot[0])) / ppm, (float(pivot[1]) - fh / 2.0) / ppm, 0.0)
	quad = MeshInstance3D.new()
	quad.mesh = q
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("sheet", sheet)
	if data.glow != null:
		mat.set_shader_parameter("glow", data.glow)
	# La hoja ya trae su luz y sombra: menos realce que los modelos 3D.
	var boost := DataRegistry.bal_f("enemies.sprite_albedo", 1.0)
	mat.set_shader_parameter("tint", Color(tint.r * boost, tint.g * boost, tint.b * boost, 1.0))
	mat.set_shader_parameter("eye_color", eye)
	mat.set_shader_parameter("self_light", DataRegistry.bal_f("enemies.sprite_self_light", 0.12))
	quad.material_override = mat
	add_child(quad)
	add_child(_make_blob_shadow(float(def.get("shadow", 0.9))))
	_add_own_light(def, eye)

## Nombre de la animación para un papel: el papel o una de sus variantes
## (attack, attack_2, ...) al azar.
func _pick(role: String) -> String:
	var anims: Dictionary = meta.get("anims", {})
	var options: Array[String] = []
	if anims.has(role):
		options.append(role)
	var n := 2
	while anims.has("%s_%d" % [role, n]):
		options.append("%s_%d" % [role, n])
		n += 1
	if options.is_empty():
		return ""
	return options[_rng.randi_range(0, options.size() - 1)]

func has_role(role: String) -> bool:
	return _pick(role) != ""

func play_role(role: String, then := "idle") -> float:
	if _dead or meta.is_empty():
		return 0.0
	var anim_name := _pick(role)
	if anim_name == "":
		return 0.0
	current_role = role
	_anim = anim_name
	_then = then
	_done = false
	_speed = float(anim_speed.get(role, 1.0))
	var a: Dictionary = meta.anims[anim_name]
	var fps := maxf(float(a.get("fps", 8.0)), 0.1)
	var count := _frames(a).size()
	# Los que se repiten arrancan en un cuadro al azar (dos iguales no van
	# sincronizados); los demás, del principio.
	_t = floorf(_rng.randf() * count) / fps if role in LOOPING else 0.0
	if role == "hit":
		_flash_t = FLASH_STEP * 2.0
	if role == "death":
		_dead = true
	_update(0.0)
	return count / fps

func set_then(role: String) -> void:
	_then = role

func is_dead() -> bool:
	return _dead

## Cuadros de la dirección más cercana a _angle (y en _flip, si hay que
## espejarlos). Con empate gana la que no se espeja.
func _frames(a: Dictionary) -> Array:
	var dirs: Dictionary = a.get("dirs", {})
	_flip = false
	var best_key := ""
	var best_d := 1e9
	for key: String in dirs.keys():
		if not DIR_ANGLES.has(key):
			continue
		var ang: float = DIR_ANGLES[key]
		for mirrored: bool in [false, true]:
			var d := absf(wrapf(_angle - (-ang if mirrored else ang), -180.0, 180.0)) + (0.01 if mirrored else 0.0)
			if d < best_d:
				best_d = d
				best_key = key
				_flip = mirrored
	if best_key == "":
		if dirs.is_empty():
			return []
		best_key = String(dirs.keys()[0])
	var frames: Array = dirs[best_key]
	return frames

func _process(delta: float) -> void:
	if quad == null:
		return
	_face_camera()
	_update(delta)

## Billboard en Y y ángulo de hacia dónde mira el enemigo (+Z del nodo)
## respecto de la cámara.
func _face_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_cam := cam.global_position - global_position
	to_cam.y = 0.0
	if to_cam.length_squared() < 0.0001:
		return
	quad.rotation.y = atan2(to_cam.x, to_cam.z) - global_rotation.y
	var fwd := global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	_angle = rad_to_deg(atan2(fwd.dot(cam.global_basis.x), fwd.dot(to_cam.normalized())))

func _update(delta: float) -> void:
	if _anim == "":
		return
	var a: Dictionary = meta.anims[_anim]
	var frames := _frames(a)
	if frames.is_empty():
		return
	var fps := maxf(float(a.get("fps", 8.0)), 0.1)
	_t += delta * _speed
	var k := int(floorf(_t * fps))
	if bool(a.get("loop", false)):
		k = posmod(k, frames.size())
	elif k >= frames.size():
		k = frames.size() - 1
		if not _done:
			_done = true
			var role := current_role
			finished_role.emit(role)
			if _then != "" and not _dead:
				play_role(_then)
				return
	var idx := int(frames[k])
	if idx != _shown or _flip != _shown_flip:
		_shown = idx
		_shown_flip = _flip
		mat.set_shader_parameter("frame_rect", Vector4((idx % _columns) * _frame_uv.x, floori(float(idx) / _columns) * _frame_uv.y, _frame_uv.x, _frame_uv.y))
		mat.set_shader_parameter("flip_h", _flip)
	# Destello de golpe a pasos: blanco, medio, nada.
	if _flash_t > 0.0:
		_flash_t -= delta
		mat.set_shader_parameter("flash", 1.0 if _flash_t > FLASH_STEP else (0.5 if _flash_t > 0.0 else 0.0))
