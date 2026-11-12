class_name EnemyVisual
extends EnemyBody
## Modelo 3D animado de un enemigo (esqueleto realista CC0 con el rig y las
## animaciones de Quaternius, armado por tools/assets/). Se configura con el
## bloque "visual" de data/species.json.
##
## Estilo PS1/Lunacid:
## - Animación a PASOS (12 fps): el AnimationPlayer va en modo manual y se
##   avanza de a 1/12 s, sin interpolar entre cuadros.
## - Material PSX (snapping, afín, niebla por vértice) con un tinte por tipo,
##   y ojos que brillan sin sombrear NI niebla (malla "*_Eyes"): dos puntos en
##   la oscuridad que se ven antes que el cuerpo.
## - Sombra "blob" con trama (recorte, sin transparencia) bajo los pies.
##
## Datos (visual):
## - bones: nombres de los huesos que usa el juego, {hand_r, hand_l, head}.
##   Por defecto los del rig de Quaternius (UAL): hand_r, hand_l, Head.
## - weapon_r / weapon_l: escena del arma, colgada de esa mano con
##   weapon_r_mount / weapon_l_mount = {pos: [x,y,z] (m, espacio del hueso),
##   rot: [x,y,z] (grados, como rotation_degrees), scale: n}.
## - head_scale / bone_scale {hueso: escala}: escala de huesos tras cada
##   cuadro (opcional; servía para achicar las cabezas "chibi").
##
## Roles de animación (visual.anims): idle, combat, walk, attack (lista),
## hit (lista), death, spawn, dormant, ability, taunt.

## Huesos por defecto (rig de UAL1/UAL2 de Quaternius, estilo Unreal).
const DEFAULT_BONES := {"hand_r": "hand_r", "hand_l": "hand_l", "head": "Head"}

var anim: AnimationPlayer
var skeleton: Skeleton3D
var anims: Dictionary = {}
var fps := 12.0
var head_scale := 1.0
## Velocidad por papel (visual.anim_speed), p. ej. levantarse más rápido.
var anim_speed: Dictionary = {}
var _speed := 1.0
var _then := "idle"
var _acc := 0.0
## Índice de hueso -> escala (cabeza, manos...), aplicada en cada cuadro.
var _bone_scales: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _dead := false

func setup(def: Dictionary, tint: Color, eye: Color, variant_seed: int) -> void:
	_rng.seed = variant_seed
	var packed: PackedScene = load(String(def.model_path))
	var model: Node3D = packed.instantiate()
	add_child(model)
	model.scale = Vector3.ONE * float(def.get("scale", 1.0))
	anims = def.get("anims", {})
	anim_speed = def.get("anim_speed", {})
	fps = float(def.get("anim_fps", 12.0))
	head_scale = float(def.get("head_scale", 1.0))
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton:
		var bones := DEFAULT_BONES.duplicate()
		var custom: Variant = def.get("bones", {})
		if typeof(custom) == TYPE_DICTIONARY:
			bones.merge(custom as Dictionary, true)
		var scales: Dictionary = (def.get("bone_scale", {}) as Dictionary).duplicate()
		if head_scale != 1.0:
			scales[String(bones.head)] = head_scale
		for bone_name: String in scales.keys():
			var idx := skeleton.find_bone(bone_name)
			if idx >= 0:
				_bone_scales[idx] = float(scales[bone_name])
		# El arma cuelga de la mano: se compensa la escala de la mano (si se
		# achicó) para que el arma conserve su tamaño.
		for side: String in ["r", "l"]:
			var bone := String(bones["hand_" + side])
			_attach_weapon(def.get("weapon_" + side, ""), bone, def.get("weapon_%s_mount" % side, {}), 1.0 / float(scales.get(bone, 1.0)))
	_apply_materials(model, tint, eye)
	add_child(_make_blob_shadow(float(def.get("shadow", 0.9))))
	if anim:
		_check_anims(String(def.model_path))
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		anim.animation_finished.connect(_on_finished)
		for role: String in LOOPING:
			var n := _anim_name(role)
			if n != "" and anim.has_animation(n):
				anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_add_own_light(def, eye)

## Cada animación nombrada en visual.anims tiene que existir en el modelo (ojo:
## el importador de Godot les saca el sufijo "_Loop"). Si falta, aviso: los
## tests y el smoke test lo toman como error.
func _check_anims(model_path: String) -> void:
	for role: String in anims.keys():
		var v: Variant = anims[role]
		var names: Array = v if typeof(v) == TYPE_ARRAY else [v]
		for n: Variant in names:
			if not anim.has_animation(String(n)):
				push_warning("EnemyVisual: %s no tiene la animación '%s' (papel %s)" % [model_path, n, role])

## `mount` = {pos, rot, scale} (ver el encabezado): ubica el arma en el puño.
func _attach_weapon(path: Variant, bone: String, mount: Variant, counter_scale := 1.0) -> void:
	if typeof(path) != TYPE_STRING or String(path) == "" or skeleton.find_bone(bone) < 0:
		return
	var m: Dictionary = mount if typeof(mount) == TYPE_DICTIONARY else {}
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skeleton.add_child(att)
	var weapon: Node3D = (load(String(path)) as PackedScene).instantiate()
	weapon.position = _vec3(m.get("pos", null))
	weapon.rotation_degrees = _vec3(m.get("rot", null))
	weapon.scale = Vector3.ONE * float(m.get("scale", 1.0)) * counter_scale
	att.add_child(weapon)

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
	_speed = float(anim_speed.get(role, 1.0))
	anim.play(n, 0.0)
	var length := anim.get_animation(n).length
	if role in LOOPING:
		anim.seek(floorf(_rng.randf() * length * fps) / fps, true)
	else:
		# play() del mismo clip que ya suena no lo reinicia: dos golpes
		# seguidos tienen que verse los dos.
		anim.seek(0.0, true)
	_apply_bone_overrides()
	if role == "death":
		_dead = true
	return length

## Cambia a qué papel vuelve el clip en curso cuando termina.
func set_then(role: String) -> void:
	_then = role

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
	anim.advance(frames * step * _speed)
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
