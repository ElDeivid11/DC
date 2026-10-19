class_name GameSettings
extends RefCounted
## Aplica los ajustes guardados en MetaState.settings al motor (audio,
## ventana, escala de UI). Se llama al arrancar (Boot) y cada vez que se
## cambia algo en Opciones.

const UI_SCALE_MIN := 0.8
const UI_SCALE_MAX := 1.5

static func defaults() -> Dictionary:
	return {
		"master_volume": 0.8,
		"fullscreen": false,
		"ui_scale": 1.0,
		"language": "es",
		"retro_preset": "clasico",
		"head_bob": true,
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

	tree.root.content_scale_factor = clampf(float(settings.get("ui_scale", 1.0)), UI_SCALE_MIN, UI_SCALE_MAX)
