class_name UIFlameCursor
extends TextureRect
## Cursor del grimorio: una llama de vela de 4 cuadros a 8 fps (por pasos,
## como el resto del movimiento). flash() muestra un destello blanco al
## confirmar. Solo anima mientras está visible.

const FPS := 8.0
const FLASH_TIME := 0.066

var _frames: Array[Texture2D] = []
var _t := 0.0
var _flash := 0.0

func _init() -> void:
	for i in 5:
		var tex := UIIcon.kit_texture("cursor_%d" % i)
		if tex:
			_frames.append(tex)
	custom_minimum_size = Vector2(16, 24)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _frames.is_empty():
		texture = _frames[0]

func flash() -> void:
	_flash = FLASH_TIME

func _process(delta: float) -> void:
	if not is_visible_in_tree() or _frames.size() < 5:
		return
	if _flash > 0.0:
		_flash -= delta
		texture = _frames[4]
		return
	_t += delta
	texture = _frames[int(_t * FPS) % 4]
