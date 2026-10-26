extends CanvasLayer
## Cambio de escena con un fundido con trama Bayer (≤ 200 ms en total) y los
## sonidos de la UI. Todas las pantallas cambian por acá:
##   SceneRouter.goto(SceneRouter.HUB)
##   SceneRouter.play_ui("click")

const BOOT := "res://scenes/Boot.tscn"
const HUB := "res://scenes/Hub.tscn"
const RUN := "res://scenes/Run.tscn"
const SUMMARY := "res://scenes/RunSummary.tscn"
const UI_GALLERY := "res://scenes/ui/UIGallery.tscn"

const FADE_TIME := 0.1
const DITHER_SHADER := "res://ui/shaders/ui_dither.gdshader"

## Sonidos (Kenney, CC0; ver assets/audio/ui/README.md): kind → [archivo, dB, tono aleatorio].
const SFX := {
	"hover": ["ui_cursor_mover.ogg", -12.0, true],
	"click": ["ui_confirmar.ogg", -6.0, false],
	"cancel": ["ui_cancelar.ogg", -6.0, false],
	"open": ["ui_menu_abrir.ogg", -8.0, false],
	"close": ["ui_menu_cerrar.ogg", -8.0, false],
	"page": ["ui_pagina_cambiar.ogg", -8.0, false],
	"coin": ["ui_comprar_monedas.ogg", -6.0, true],
	"soul": ["ui_alma.ogg", -4.0, false],
	"error": ["ui_error.ogg", -8.0, false],
	"level_up": ["extra_subir_nivel.ogg", -4.0, false],
	"reward": ["extra_recompensa_grande.ogg", -4.0, false],
	"descend": ["extra_bajar_piso_puerta.ogg", -6.0, false],
	# Sala del jefe (sintetizados: tools/audio/make_boss_sfx.py).
	"gate": ["extra_jefe_reja.wav", -4.0, false],
	"brazier": ["extra_jefe_brasero.wav", -8.0, true],
	"boss": ["extra_jefe_entrada.wav", -3.0, false],
	"item": ["extra_equipar_objeto.ogg", -6.0, false],
}
const SFX_DIR := "res://assets/audio/ui/"
## El de monedas se repite en contadores: como mucho uno cada 60 ms.
const COIN_GAP_MS := 60

signal scene_changed(path: String)

var busy := false
var current_path := ""
var _rect: ColorRect
var _material: ShaderMaterial
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _rng := RandomNumberGenerator.new()
var _last_coin_ms := -1000

func _ready() -> void:
	layer = 120 # por encima de toda la UI, por debajo del post-proceso PSX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = load(DITHER_SHADER)
	_material.set_shader_parameter("color", UIStyle.BG_DEEP)
	_material.set_shader_parameter("mode", 0)
	_material.set_shader_parameter("progress", 0.0)
	_rect.material = _material
	add_child(_rect)
	# La escala de UI depende del tamaño de la ventana (píxel de arte entero).
	get_tree().root.size_changed.connect(func() -> void: GameSettings.apply_ui_scale(get_tree().root, MetaState.settings))

# --- Sonidos de UI ----------------------------------------------------------------

func play_ui(kind: String) -> void:
	if DisplayServer.get_name() == "headless" or not SFX.has(kind):
		return
	if kind == "coin":
		var now := Time.get_ticks_msec()
		if now - _last_coin_ms < COIN_GAP_MS:
			return
		_last_coin_ms = now
	if _players.is_empty():
		for i in 6:
			var p := AudioStreamPlayer.new()
			add_child(p)
			_players.append(p)
	var info: Array = SFX[kind]
	if not _streams.has(kind):
		_streams[kind] = load(SFX_DIR + String(info[0]))
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = _streams[kind]
	player.volume_db = float(info[1])
	player.pitch_scale = _rng.randf_range(0.95, 1.05) if bool(info[2]) else 1.0
	player.play()

# --- Cambio de escena -------------------------------------------------------------

## Tamaño en pantalla de un píxel de arte (la trama usa celdas de ese tamaño).
func _cell_px() -> float:
	var win := get_viewport().get_visible_rect().size
	var screen := Vector2(get_window().size)
	var stretch := screen.x / maxf(win.x, 1.0)
	return maxf(1.0, roundf(UIStyle.PIXEL_SCALE * stretch))

func _fade(to: float) -> void:
	_material.set_shader_parameter("cell_px", _cell_px())
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _material.set_shader_parameter("progress", v),
		1.0 - to, to, FADE_TIME)
	await tw.finished

func goto(path: String) -> void:
	if busy:
		return
	busy = true
	await _fade(1.0)
	get_tree().paused = false
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneRouter: no se pudo abrir %s (%s)" % [path, error_string(err)])
	# change_scene es diferido: la escena nueva entra al árbol el frame siguiente.
	await get_tree().process_frame
	await get_tree().process_frame
	current_path = path
	await _fade(0.0)
	busy = false
	scene_changed.emit(path)
