class_name EnemyVisual
extends Node3D
## Modelo 3D animado de un enemigo (esqueletos KayKit adaptados, ver
## tools/assets/). Se configura con el bloque "visual" de data/species.json.
##
## Estilo PS1/Lunacid:
## - Animación a PASOS (12 fps): el AnimationPlayer va en modo manual y se
##   avanza de a 1/12 s, sin interpolar entre cuadros.
## - Cabeza más chica que el original "chibi" (bone pose scale tras animar).
## - Material PSX (snapping, afín, niebla por vértice) con un tinte por tipo,
##   y ojos que brillan sin sombrear (se ven en la oscuridad).
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
var _head_bone := -1
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
		_head_bone = skeleton.find_bone("head")
		_attach_weapon(def.get("weapon_r", ""), "handslot.r")
		_attach_weapon(def.get("weapon_l", ""), "handslot.l")
	_apply_materials(model, tint, eye)
	if anim:
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		anim.animation_finished.connect(_on_finished)
		for role: String in LOOPING:
			var n := _anim_name(role)
			if n != "" and anim.has_animation(n):
				anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if def.has("light"):
		var l: Dictionary = def.light
		light = OmniLight3D.new()
		light.light_color = eye.lerp(l.get("color", eye), 0.5)
		light.light_energy = float(l.get("energy", 1.0))
		light.omni_range = float(l.get("range", 3.0))
		light.position = Vector3(0, 1.4, 0.4)
		add_child(light)

func _attach_weapon(path: Variant, bone: String) -> void:
	if typeof(path) != TYPE_STRING or String(path) == "" or skeleton.find_bone(bone) < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skeleton.add_child(att)
	var weapon: Node3D = (load(String(path)) as PackedScene).instantiate()
	att.add_child(weapon)

## Reemplaza materiales por PSX; los ojos ("*_Eyes") brillan con su color.
func _apply_materials(node: Node, tint: Color, eye: Color) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var glow := String(mi.name).ends_with("_Eyes")
		var n: int = mi.mesh.get_surface_count() if mi.mesh else 0
		for i in n:
			if glow:
				mi.set_surface_override_material(i, FloorBuilder.make_glow_material(eye))
				continue
			var original: Material = mi.mesh.surface_get_material(i)
			var tex: Texture2D = null
			if original is BaseMaterial3D:
				tex = (original as BaseMaterial3D).albedo_texture
			mi.set_surface_override_material(i, FloorBuilder.make_psx_material(tint, tex))
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
	if skeleton and _head_bone >= 0 and head_scale != 1.0:
		skeleton.set_bone_pose_scale(_head_bone, Vector3.ONE * head_scale)

func _on_finished(_name: StringName) -> void:
	var role := current_role
	if role in LOOPING:
		return
	finished_role.emit(role)
	if _then != "" and not _dead:
		play_role(_then)
