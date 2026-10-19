extends CanvasLayer
## Cambio de escena con un fundido a negro corto (≤ 200 ms en total). Todas
## las pantallas cambian por acá: SceneRouter.goto(SceneRouter.HUB).

const BOOT := "res://scenes/Boot.tscn"
const HUB := "res://scenes/Hub.tscn"
const RUN := "res://scenes/Run.tscn"
const SUMMARY := "res://scenes/RunSummary.tscn"
const UI_GALLERY := "res://scenes/ui/UIGallery.tscn"

const FADE_TIME := 0.09

signal scene_changed(path: String)

var busy := false
var current_path := ""
var _rect: ColorRect

func _ready() -> void:
	layer = 120 # por encima de toda la UI, por debajo del post-proceso PSX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(UIStyle.BG_DEEP, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)

func goto(path: String) -> void:
	if busy:
		return
	busy = true
	var out := create_tween()
	out.tween_property(_rect, "color:a", 1.0, FADE_TIME)
	await out.finished
	get_tree().paused = false
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneRouter: no se pudo abrir %s (%s)" % [path, error_string(err)])
	# change_scene es diferido: la escena nueva entra al árbol el frame siguiente.
	await get_tree().process_frame
	await get_tree().process_frame
	current_path = path
	var back := create_tween()
	back.tween_property(_rect, "color:a", 0.0, FADE_TIME)
	await back.finished
	busy = false
	scene_changed.emit(path)
