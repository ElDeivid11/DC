class_name UISoulMotes
extends Control
## Motas de alma (spec 8.11): 12 puntitos de 2×2 px en ALMA_LUZ que suben de
## a 2 px cada 0,066 s desde el borde inferior y se apagan por pasos al
## acercarse arriba. Semilla fija: siempre el mismo dibujo. Va encima de la
## tarjeta del alma (hija de la UISoulCard: ocupa su interior).

const COUNT := 12
const STEP := 0.066
const SEED := 1307

var _motes: Array[Vector2] = []
var _t := 0.0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	resized.connect(_reset)
	_reset()

func _reset() -> void:
	_rng.seed = SEED
	_motes.clear()
	for i in COUNT:
		_motes.append(Vector2(_random_x(), _snap(size.y - _rng.randf_range(0.0, size.y))))
	queue_redraw()

func _random_x() -> float:
	return _snap(_rng.randf_range(4.0, maxf(size.x - 6.0, 4.0)))

static func _snap(v: float) -> float:
	return roundf(v / 2.0) * 2.0

func _process(delta: float) -> void:
	if not is_visible_in_tree() or size.y <= 0.0:
		return
	_t += delta
	if _t < STEP:
		return
	_t = fmod(_t, STEP)
	for i in _motes.size():
		var p := _motes[i]
		p.y -= 2.0
		if p.y < 0.0:
			p = Vector2(_random_x(), _snap(size.y - 2.0))
		_motes[i] = p
	queue_redraw()

func _draw() -> void:
	for p in _motes:
		# Tres escalones de opacidad: llena abajo, tenue arriba.
		var f := p.y / maxf(size.y, 1.0)
		var a := 1.0 if f > 0.66 else (0.66 if f > 0.33 else 0.33)
		draw_rect(Rect2(p, Vector2(2, 2)), Color(UIStyle.SOUL_LIGHT, a))
