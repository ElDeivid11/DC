class_name FlickerLight
extends OmniLight3D
## Luz de fuego con parpadeo ESCALONADO (estilo PS1): cambia de intensidad de
## golpe `hz` veces por segundo, sin interpolar. Antorchas de pared, la lámpara
## del equipo y el aura del jefe.

## Variación máxima de la intensidad (0.1 = ±10%).
var amount := 0.08
var hz := 10.0
var base_energy := 1.0
var _acc := 0.0
var _rng := RandomNumberGenerator.new()

static func make(color: Color, energy: float, light_range: float, attenuation := 1.0, p_amount := 0.08, p_hz := 10.0) -> FlickerLight:
	var l := FlickerLight.new()
	l.light_color = color
	l.base_energy = energy
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = attenuation
	l.amount = p_amount
	l.hz = p_hz
	l.shadow_enabled = false
	return l

func _ready() -> void:
	# Los sprites con luz pareja (EnemySprite) suman las luces de este grupo.
	add_to_group(EnemySprite.LIGHTS_GROUP)
	_rng.seed = hash(get_instance_id())
	_acc = _rng.randf() / maxf(hz, 0.1)

func _process(delta: float) -> void:
	if amount <= 0.0 or hz <= 0.0:
		return
	_acc += delta
	if _acc < 1.0 / hz:
		return
	_acc = 0.0
	light_energy = base_energy * (1.0 + _rng.randf_range(-amount, amount))
