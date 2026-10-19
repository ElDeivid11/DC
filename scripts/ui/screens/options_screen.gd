class_name OptionsScreen
extends UIScreen
## Opciones: volumen, pantalla completa, escala de UI (80–150%), estilo de
## imagen (presets PS1, ver RetroView), balanceo de cámara, controles (lista)
## e idioma. Se guardan y aplican al instante.
## Desde el Hub (con build de debug) además: sala de pruebas, galería de UI
## y reiniciar guardado.

var from_hub := false
var scale_value: Label

func _init(p_from_hub := false) -> void:
	super(DataRegistry.t("options.title"))
	from_hub = p_from_hub

func _ready() -> void:
	super._ready()
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	body.add_child(row)

	var general := UIPanel.new(DataRegistry.t("options.general"), "PanelAlt")
	general.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(general)
	var s := MetaState.settings

	general.body.add_child(_label(DataRegistry.t("options.volume")))
	var vol := HSlider.new()
	vol.min_value = 0
	vol.max_value = 100
	vol.step = 5
	vol.value = roundf(float(s.get("master_volume", 0.8)) * 100.0)
	vol.focus_mode = Control.FOCUS_ALL
	vol.value_changed.connect(func(v: float) -> void: _apply_setting("master_volume", v / 100.0))
	general.body.add_child(vol)

	var fs := CheckBox.new()
	fs.text = DataRegistry.t("options.fullscreen")
	fs.button_pressed = bool(s.get("fullscreen", false))
	fs.toggled.connect(func(on: bool) -> void: _apply_setting("fullscreen", on))
	general.body.add_child(fs)

	var image_label := _label(DataRegistry.t("options.image"))
	general.body.add_child(image_label)
	var image := OptionButton.new()
	for id in RetroView.PRESETS:
		image.add_item(DataRegistry.t("options.preset_" + id))
	image.selected = RetroView.PRESETS.find(RetroView.preset_id())
	image.item_selected.connect(func(i: int) -> void: _apply_setting("retro_preset", RetroView.PRESETS[i]))
	UITooltip.attach(image, DataRegistry.t("options.image_tip"))
	general.body.add_child(image)

	var bob := CheckBox.new()
	bob.text = DataRegistry.t("options.head_bob")
	bob.button_pressed = bool(s.get("head_bob", true))
	bob.toggled.connect(func(on: bool) -> void: _apply_setting("head_bob", on))
	UITooltip.attach(bob, DataRegistry.t("options.head_bob_tip"))
	general.body.add_child(bob)

	var scale_row := HBoxContainer.new()
	general.body.add_child(scale_row)
	var sl := _label(DataRegistry.t("options.ui_scale"))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(sl)
	scale_value = _label("")
	scale_value.theme_type_variation = "AccentLabel"
	scale_row.add_child(scale_value)
	var sc := HSlider.new()
	sc.min_value = GameSettings.UI_SCALE_MIN * 100.0
	sc.max_value = GameSettings.UI_SCALE_MAX * 100.0
	sc.step = 10
	sc.value = roundf(float(s.get("ui_scale", 1.0)) * 100.0)
	sc.focus_mode = Control.FOCUS_ALL
	scale_value.text = "%d%%" % int(sc.value)
	# La escala se aplica al soltar (cambiarla mientras se arrastra mueve el slider bajo el mouse).
	sc.value_changed.connect(func(v: float) -> void: scale_value.text = "%d%%" % int(v))
	sc.drag_ended.connect(func(_changed: bool) -> void: _apply_setting("ui_scale", sc.value / 100.0))
	sc.focus_exited.connect(func() -> void: _apply_setting("ui_scale", sc.value / 100.0))
	general.body.add_child(sc)

	general.body.add_child(_label(DataRegistry.t("options.language")))
	var lang := OptionButton.new()
	lang.add_item(DataRegistry.t("options.language_es"))
	lang.disabled = true
	general.body.add_child(lang)

	var controls := UIPanel.new(DataRegistry.t("options.controls"), "PanelAlt")
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(controls)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UIStyle.SPACE * 4)
	controls.body.add_child(grid)
	for action in Controls.DISPLAY_ORDER:
		grid.add_child(_label(DataRegistry.t("controls." + action)))
		var keys := _label(Controls.bindings_text(action))
		keys.theme_type_variation = "DimLabel"
		grid.add_child(keys)
	grid.add_child(_label(DataRegistry.t("controls.menus")))
	var menus := _label(DataRegistry.t("controls.menus_keys"))
	menus.theme_type_variation = "DimLabel"
	grid.add_child(menus)

	if from_hub and OS.is_debug_build():
		var dbg := UIPanel.new(DataRegistry.t("options.debug"), "PanelAlt")
		row.add_child(dbg)
		dbg.body.add_child(UIButton.make(DataRegistry.t("options.test_room"), _start_test_room))
		dbg.body.add_child(UIButton.make(DataRegistry.t("gallery.title"), func() -> void: SceneRouter.goto(SceneRouter.UI_GALLERY)))
		dbg.body.add_child(UIButton.make(DataRegistry.t("options.reset_save"), _reset_save, "DangerButton"))

	add_footer_button(DataRegistry.t("ui.back"), close)
	vol.call_deferred("grab_focus")

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func _apply_setting(key: String, value: Variant) -> void:
	MetaState.settings[key] = value
	GameSettings.apply(MetaState.settings, get_tree())
	SaveSystem.save_meta()
	EventBus.settings_changed.emit()

func _start_test_room() -> void:
	GameState.new_run(randi(), true)
	SceneRouter.goto(SceneRouter.RUN)

func _reset_save() -> void:
	var d := UIConfirmDialog.ask(self, DataRegistry.t("options.reset_title"), DataRegistry.t("options.reset_text"), DataRegistry.t("options.reset_yes"), DataRegistry.t("ui.cancel"), true)
	if await d.answered:
		SaveSystem.reset_save()
		UIToast.show(get_tree(), DataRegistry.t("options.reset_done"), "danger")
		close()
