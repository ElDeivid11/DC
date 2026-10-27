class_name RetroView
extends SubViewportContainer
## Vista 3D con el "estilo de imagen" PS1 (Opciones → Imagen). Lo usan la run
## y el fondo del Hub:
## - El mundo se dibuja en un SubViewport a ~`lines` líneas y se escala sin
##   suavizar (stretch_shrink; con stretch = true el tamaño lo decide el
##   contenedor, no viewport.size).
## - La trama de 15 bits va DENTRO del SubViewport: cada celda de la trama es
##   un píxel del juego y la UI (que vive fuera) queda limpia.
## - Los globals del shader PSX (deformación afín, temblor de vértices) salen
##   del mismo preset.
## Presets: data/balance.json → render.presets (clasico, crujiente, limpio).

const DITHER_SHADER := preload("res://shaders/psx_viewport_dither.gdshader")
const PRESETS: Array[String] = ["clasico", "crujiente", "limpio"]

var viewport: SubViewport
var world: Node3D
var _dither: ColorRect

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # reescalado sin blur: el pixelado real
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var layer := CanvasLayer.new()
	viewport.add_child(layer)
	_dither = ColorRect.new()
	_dither.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dither.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = DITHER_SHADER
	_dither.material = mat
	layer.add_child(_dither)

func _ready() -> void:
	resized.connect(refresh)
	EventBus.settings_changed.connect(refresh)
	refresh()

## Preset elegido. Guardados viejos sin "retro_preset": pixelated = false → limpio.
static func preset_id() -> String:
	var id := String(MetaState.settings.get("retro_preset", ""))
	if PRESETS.has(id):
		return id
	if not bool(MetaState.settings.get("pixelated", true)):
		return "limpio"
	return String(DataRegistry.bal("render.preset_default", "clasico"))

static func preset() -> Dictionary:
	var all: Dictionary = DataRegistry.bal("render.presets", {})
	var p: Dictionary = all.get(preset_id(), {})
	return p

## Globals del shader PSX según el preset. El dither del addon (autoload a
## pantalla completa, sobre la UI) se apaga con psx_bit_depth = 0.
static func apply_globals() -> void:
	var p := preset()
	RenderingServer.global_shader_parameter_set(&"psx_affine_strength", float(p.get("affine", 0.0)))
	RenderingServer.global_shader_parameter_set(&"psx_precision_xy", float(p.get("precision_xy", 0.0)))
	RenderingServer.global_shader_parameter_set(&"psx_bit_depth", 0)

func refresh() -> void:
	apply_globals()
	var p := preset()
	var lines := int(p.get("lines", 0))
	stretch_shrink = maxi(1, roundi(size.y / float(lines))) if lines > 0 and size.y > 0 else 1
	var bits := int(p.get("dither_bits", 0))
	_dither.visible = bits > 0
	(_dither.material as ShaderMaterial).set_shader_parameter("bit_depth", clampi(bits, 1, 7))
