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

# --- Sonidos de UI de prueba ---------------------------------------------------
# Blips cortos generados por código (sin archivos de audio): "hover" al mover
# el foco, "click" al confirmar, "error" al no poder. Reemplazables más
# adelante por sonidos reales sin tocar a quien los usa.

var _sfx: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0

func play_ui(kind: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _sfx.is_empty():
		_sfx = {
			"hover": _blip(880.0, 0.025, 0.12),
			"click": _blip(520.0, 0.05, 0.2),
			"error": _blip(160.0, 0.12, 0.25),
			"coin": _blip(1320.0, 0.06, 0.15),
		}
		for i in 4:
			var p := AudioStreamPlayer.new()
			add_child(p)
			_players.append(p)
	if not _sfx.has(kind):
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = _sfx[kind]
	player.play()

static func _blip(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := 1.0 - float(i) / n
		var square := 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0
		data.encode_s16(i * 2, int(square * env * volume * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav

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
