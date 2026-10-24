class_name GameSettings
extends RefCounted
## Aplica los ajustes guardados en MetaState.settings al motor (audio,
## ventana, escala de UI). Se llama al arrancar (Boot) y cada vez que se
## cambia algo en Opciones.

## Escala de la interfaz: Compacta / Normal / Grande. El factor final se
## redondea para que un píxel de arte del kit (UIStyle.PIXEL_SCALE px de UI)
## mida un número entero de píxeles de pantalla en cualquier ventana.
const UI_SCALE_STEPS: Array[float] = [0.8, 1.0, 1.25]
const BASE_SIZE := Vector2(1280, 720)

static func defaults() -> Dictionary:
	return {
		"master_volume": 0.8,
		"fullscreen": false,
		"ui_scale": 1.0,
		"language": "es",
		"retro_preset": "clasico",
		"head_bob": true,
		"enemy_style": String(DataRegistry.bal("render.enemy_style_default", "sprite")),
	}

static func apply(settings: Dictionary, tree: SceneTree) -> void:
	var vol := clampf(float(settings.get("master_volume", 0.8)), 0.0, 1.0)
	AudioServer.set_bus_mute(0, vol <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.0001)))

	# En headless (tests, verificación) no hay ventana real que tocar.
	if DisplayServer.get_name() != "headless":
		var want_fs := bool(settings.get("fullscreen", false))
		var is_fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if want_fs != is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)

	apply_ui_scale(tree.root, settings)

## Factor de content_scale para una ventana `win` y un paso de escala.
static func ui_factor(win: Vector2, ui_scale: float) -> float:
	var stretch := minf(win.x / BASE_SIZE.x, win.y / BASE_SIZE.y)
	if stretch <= 0.0:
		return ui_scale
	var art := maxf(1.0, roundf(stretch * ui_scale * UIStyle.PIXEL_SCALE))
	return art / (UIStyle.PIXEL_SCALE * stretch)

## Paso de la lista más cercano (guardados viejos tenían 0,8–1,5 libre).
static func nearest_step(ui_scale: float) -> float:
	var best := UI_SCALE_STEPS[0]
	for step in UI_SCALE_STEPS:
		if absf(step - ui_scale) < absf(best - ui_scale):
			best = step
	return best

## Se llama también cuando cambia el tamaño de la ventana (SceneRouter).
static func apply_ui_scale(root: Window, settings: Dictionary) -> void:
	var step := nearest_step(float(settings.get("ui_scale", 1.0)))
	# En headless (tests) la ventana no es real: el paso tal cual.
	var f := step if DisplayServer.get_name() == "headless" else ui_factor(Vector2(root.size), step)
	if not is_equal_approx(root.content_scale_factor, f):
		root.content_scale_factor = f
