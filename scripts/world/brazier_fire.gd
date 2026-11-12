class_name BrazierFire
extends Node3D
## Fuego de un brasero de la sala del jefe: tres lenguas de llama sin sombrear
## que cambian de alto a saltos (como las antorchas PS1), brasas en el cuenco
## y una luz con parpadeo. Arranca apagado; light_up() lo enciende de golpe.

const FLAMES := [[0.0, 0.0, 0.34], [-0.1, 0.06, 0.22], [0.09, -0.07, 0.26]]

var light: FlickerLight
var energy := 2.0
var _flames: Array[MeshInstance3D] = []
var _coals: MeshInstance3D
var _acc := 0.0
var _rng := RandomNumberGenerator.new()

func setup(color: Color, flame_mat: Material, coal_mat: Material) -> void:
	energy = DataRegistry.bal_f("boss_room.brazier_energy", 2.0)
	_coals = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.27
	disc.bottom_radius = 0.27
	disc.height = 0.03
	disc.radial_segments = 8
	disc.rings = 1
	_coals.mesh = disc
	_coals.material_override = coal_mat
	_coals.visible = false
	add_child(_coals)
	for f: Array in FLAMES:
		var m := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.16, float(f[2]), 0.16)
		m.mesh = prism
		m.position = Vector3(float(f[0]), float(f[2]) / 2.0, float(f[1]))
		m.material_override = flame_mat
		m.visible = false
		add_child(m)
		_flames.append(m)
	light = FlickerLight.make(color, 0.0, DataRegistry.bal_f("boss_room.brazier_range", 6.0), 1.2, 0.15, 10.0)
	light.position.y = 0.4
	add_child(light)
	_rng.seed = hash(get_instance_id())
	set_process(false)

func is_lit() -> bool:
	return _coals != null and _coals.visible

## La llama sale alta y baja a su tamaño; la luz llega a pleno en dos pasos.
func light_up(animate := true) -> void:
	_coals.visible = true
	for m in _flames:
		m.visible = true
	set_process(true)
	if not animate:
		light.base_energy = energy
		return
	scale = Vector3(1.0, 1.8, 1.0)
	var tw := create_tween()
	tw.tween_callback(func() -> void: light.base_energy = energy * 1.6)
	tw.tween_interval(0.08)
	tw.tween_callback(func() -> void:
		scale = Vector3(1.0, 1.3, 1.0)
		light.base_energy = energy * 1.2)
	tw.tween_interval(0.08)
	tw.tween_callback(func() -> void:
		scale = Vector3.ONE
		light.base_energy = energy)

func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.11:
		return
	_acc = 0.0
	for m in _flames:
		m.scale.y = _rng.randf_range(0.75, 1.2)
