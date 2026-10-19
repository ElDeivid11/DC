class_name EnemyVisual
extends Node3D
## Modelo 3D animado de un enemigo (esqueletos KayKit adaptados, ver
## tools/assets/). Se configura con el bloque "visual" de data/species.json.
##
## Estilo PS1/Lunacid:
## - Animación a PASOS (12 fps): el AnimationPlayer va en modo manual y se
##   avanza de a 1/12 s, sin interpolar entre cuadros.
## - Proporciones menos "chibi" que el original: cabeza y manos más chicas
##   (escala de huesos tras animar: visual.head_scale y visual.bone_scale).
## - Material PSX (snapping, afín, niebla por vértice) con un tinte por tipo,
##   y ojos que brillan sin sombrear NI niebla: dos puntos en la oscuridad
##   que se ven antes que el cuerpo.
## - Sombra "blob" con trama (recorte, sin transparencia) bajo los pies.
##
## Roles de animación (data: visual.anims): idle, combat, walk, attack
## (lista), hit (lista), death, spawn, dormant, ability, block.

signal finished_role(role: String)

const LOOPING: Array[String] = ["idle", "combat", "walk", "dormant"]

var anim: AnimationPlayer
var skeleton: Skeleton3D
## Luz propia (solo si visual.light existe; p. ej. el aura del nigromante).
var light: OmniLight3D = null
var anims: Dictionary = {}
var fps := 12.0
var head_scale := 1.0
var current_role := ""
var _then := "idle"
var _acc := 0.0
## Índice de hueso -> escala (cabeza, manos...), aplicada en cada cuadro.
var _bone_scales: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _dead := false

## def = species.visual (ya validado por DataRegistry); tint = color
## multiplicador; eye = color de los ojos (y de la luz propia, si tiene).
func setup(def: Dictionary, tint: Color, eye: Color, variant_seed: int) -> void:
	_rng.seed = variant_seed
	var packed: PackedScene = load(String(def.model_path))
	var model: Node3D = packed.instantiate()
	add_child(model)
	model.scale = Vector3.ONE * float(def.get("scale", 1.0))
	anims = def.get("anims", {})
	fps = float(def.get("anim_fps", 12.0))
	head_scale = float(def.get("head_scale", 1.0))
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton:
		var scales: Dictionary = (def.get("bone_scale", {}) as Dictionary).duplicate()
		if head_scale != 1.0:
			scales["head"] = head_scale
		for bone_name: String in scales.keys():
			var idx := skeleton.find_bone(bone_name)
			if idx >= 0:
				_bone_scales[idx] = float(scales[bone_name])
		# El arma cuelga de la mano: se compensa la escala de la mano para
		# que el arma conserve su tamaño.
		_attach_weapon(def.get("weapon_r", ""), "handslot.r", 1.0 / float(scales.get("hand.r", 1.0)))
		_attach_weapon(def.get("weapon_l", ""), "handslot.l", 1.0 / float(scales.get("hand.l", 1.0)))
	_apply_materials(model, tint, eye)
	add_child(_make_blob_shadow(float(def.get("shadow", 0.9))))
	if anim:
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		anim.animation_finished.connect(_on_finished)
		for role: String in LOOPING:
			var n := _anim_name(role)
			if n != "" and anim.has_animation(n):
				anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if def.has("light"):
		var l: Dictionary = def.light
		light = FlickerLight.make(eye.lerp(l.get("color", eye), 0.5), float(l.get("energy", 1.0)), float(l.get("range", 3.0)), 1.0, 0.1, 8.0)
		light.position = Vector3(0, 1.4, 0.4)
		add_child(light)

func _attach_weapon(path: Variant, bone: String, counter_scale := 1.0) -> void:
	if typeof(path) != TYPE_STRING or String(path) == "" or skeleton.find_bone(bone) < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skeleton.add_child(att)
	var weapon: Node3D = (load(String(path)) as PackedScene).instantiate()
	weapon.scale = Vector3.ONE * counter_scale
	att.add_child(weapon)

## Mancha de sombra redonda con trama Bayer (recorte, sin mezcla alfa: no hay
## problemas de orden de dibujo, y es como lo hacía PS1).
static var _shadow_mat: PsxMaterial3D = null

static func _make_blob_shadow(diameter: float) -> MeshInstance3D:
	if _shadow_mat == null:
		const SIZE := 16
		const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		for y in SIZE:
			for x in SIZE:
				var d := Vector2(x + 0.5 - SIZE / 2.0, y + 0.5 - SIZE / 2.0).length() / (SIZE / 2.0)
				var a := clampf(1.0 - d, 0.0, 1.0) * 1.6
				var on := a > (BAYER[(x % 4) + (y % 4) * 4] + 0.5) / 16.0
				img.set_pixel(x, y, Color(0, 0, 0, 1.0 if on else 0.0))
		_shadow_mat = FloorBuilder.make_psx_material(Color(0.02, 0.02, 0.02), ImageTexture.create_from_image(img))
		_shadow_mat.transparency_mode = 1 # Cutout
		_shadow_mat.shading_mode = 0 # Unshaded
		_shadow_mat.refresh_shader()
	var quad := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(diameter, diameter)
	quad.mesh = plane
	quad.material_override = _shadow_mat
	quad.position.y = 0.02
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return quad

## Reemplaza materiales por PSX; los ojos ("*_Eyes") brillan con su color.
func _apply_materials(node: Node, tint: Color, eye: Color) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var glow := String(mi.name).ends_with("_Eyes")
		var n: int = mi.mesh.get_surface_count() if mi.mesh else 0
		for i in n:
			if glow:
				mi.set_surface_override_material(i, FloorBuilder.make_glow_material(eye, false))
				continue
			var original: Material = mi.mesh.surface_get_material(i)
			var tex: Texture2D = null
			if original is BaseMaterial3D:
				tex = (original as BaseMaterial3D).albedo_texture
			# Algo más claros que el entorno: se leen contra paredes oscuras.
			mi.set_surface_override_material(i, FloorBuilder.make_psx_material(tint * DataRegistry.bal_f("enemies.albedo_boost", 1.0), tex))
	for c in node.get_children():
		_apply_materials(c, tint, eye)

func _anim_name(role: String) -> String:
	var v: Variant = anims.get(role, "")
	if typeof(v) == TYPE_ARRAY:
		var arr: Array = v
		return String(arr[_rng.randi_range(0, arr.size() - 1)]) if not arr.is_empty() else ""
	return String(v)

func has_role(role: String) -> bool:
	return anims.has(role)

## Reproduce un rol. Los de una sola vez (attack, hit, spawn...) vuelven solos
## a `then` al terminar ("" = quedarse en el último cuadro, como la muerte).
## Los que se repiten arrancan en un cuadro al azar, para que dos esqueletos
## iguales no se muevan sincronizados. Devuelve la duración (0 = no existe).
func play_role(role: String, then := "idle") -> float:
	if anim == null or _dead:
		return 0.0
	var n := _anim_name(role)
	if n == "" or not anim.has_animation(n):
		return 0.0
	current_role = role
	_then = then
	anim.play(n, 0.0)
	var length := anim.get_animation(n).length
	if role in LOOPING:
		anim.seek(floorf(_rng.randf() * length * fps) / fps, true)
	else:
		anim.advance(0.0)
	_apply_bone_overrides()
	if role == "death":
		_dead = true
	return length

func is_dead() -> bool:
	return _dead

func _process(delta: float) -> void:
	if anim == null:
		return
	_acc += delta
	var step := 1.0 / fps
	if _acc < step:
		return
	# A pasos: se avanza de a cuadros enteros de 1/fps (sin interpolación visible).
	var frames := floorf(_acc / step)
	_acc -= frames * step
	anim.advance(frames * step)
	_apply_bone_overrides()

func _apply_bone_overrides() -> void:
	if skeleton == null:
		return
	for idx: int in _bone_scales.keys():
		skeleton.set_bone_pose_scale(idx, Vector3.ONE * float(_bone_scales[idx]))

func _on_finished(_name: StringName) -> void:
	var role := current_role
	if role in LOOPING:
		return
	finished_role.emit(role)
	if _then != "" and not _dead:
		play_role(_then)
