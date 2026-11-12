extends Control
## Escena de arranque (run/main_scene). Si los datos de data/*.json tienen
## errores, los muestra en pantalla en vez de arrancar con datos rotos. Si no,
## aplica los ajustes guardados y va al Hub.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	FloorBuilder.ensure_psx_shader_globals()
	GameSettings.apply(MetaState.settings, get_tree())
	if not DataRegistry.errors.is_empty():
		_show_errors()
		return
	SceneRouter.goto.call_deferred(SceneRouter.HUB)

func _show_errors() -> void:
	var screen := UIScreen.new(DataRegistry.t("boot.data_errors"))
	screen.closable = false
	add_child(screen)
	var info := Label.new()
	info.text = DataRegistry.t("boot.data_errors_text")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	screen.body.add_child(info)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.body.add_child(scroll)
	var list := Label.new()
	list.theme_type_variation = "DangerLabel"
	list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.text = "\n".join(DataRegistry.errors)
	scroll.add_child(list)
	screen.add_footer_button(DataRegistry.t("hub.quit"), func() -> void: get_tree().quit(1))
	UIFocus.grab_first(screen.footer)
