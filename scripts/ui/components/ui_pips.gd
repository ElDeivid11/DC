class_name UIPips
extends HBoxContainer
## Fila de pips del grimorio: niveles de mejora, pisos alcanzados, puntos sin
## repartir. kind "coin" (dorado) o "vela" (puntos pendientes: laten).

var _kind := "coin"
var _icons: Array[TextureRect] = []
var _t := 0.0

func _init(filled := 0, total := 5, kind := "coin") -> void:
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	setup(filled, total, kind)

func setup(filled: int, total: int, kind := "coin") -> void:
	_kind = kind
	for c in get_children():
		c.queue_free()
	_icons.clear()
	for i in total:
		var r := TextureRect.new()
		r.texture = UIIcon.kit_texture(("pip_vela" if kind == "vela" else "pip_full") if i < filled else "pip_empty")
		r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		if i < filled:
			_icons.append(r)
	set_process(kind == "vela" and not _icons.is_empty())

## Los puntos pendientes laten en dos pasos cada 0,5 s.
func _process(delta: float) -> void:
	_t += delta
	var a := 1.0 if fmod(_t, 1.0) < 0.5 else 0.6
	for r in _icons:
		r.modulate.a = a
