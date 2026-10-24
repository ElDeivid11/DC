class_name OptionsScreen
extends UIScreen
## Opciones: volumen, pantalla completa, escala de UI (Compacta / Normal /
## Grande, ver GameSettings.ui_factor), estilo de imagen (presets PS1, ver
## RetroView), balanceo de cámara, enemigos en pixel art o 3D e idioma.
## Se guardan y aplican al instante.
## A la derecha, pestañas de Controles (teclas en KeyCaps) y Créditos.
## Desde el Hub además: reiniciar guardado, y con build de debug la sala de
## pruebas y la galería de UI (al pie).

const LABEL_WIDTH := 220
const CONTROL_WIDTH := 260

var from_hub := false
var volume_value: Label

func _init(p_from_hub := false) -> void:
	super(DataRegistry.t("options.title"))
	from_hub = p_from_hub

func _ready() -> void:
	super._ready()
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	body.add_child(row)
	var vol := _build_general(row)
	_build_right(row)

	if from_hub and OS.is_debug_build():
		add_footer_button(DataRegistry.t("options.test_room"), _start_test_room)
		add_footer_button(DataRegistry.t("gallery.title"), func() -> void: SceneRouter.goto(SceneRouter.UI_GALLERY))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(spacer)
	add_footer_button(DataRegistry.t("ui.back"), close)
	vol.call_deferred("grab_focus")

func _build_general(parent: Control) -> HSlider:
	var general := UIPanel.new(DataRegistry.t("options.general"), "PanelAlt")
	general.custom_minimum_size.x = LABEL_WIDTH + CONTROL_WIDTH + 80
	general.body.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	parent.add_child(general)
	var s := MetaState.settings

	var vol := HSlider.new()
	vol.min_value = 0
	vol.max_value = 100
	vol.step = 5
	vol.value = roundf(float(s.get("master_volume", 0.8)) * 100.0)
	vol.focus_mode = Control.FOCUS_ALL
	vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume_value = UILabel.make("%d%%" % int(vol.value), "NumSmallLabel")
	volume_value.custom_minimum_size.x = 44
	volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vol.value_changed.connect(func(v: float) -> void:
		volume_value.text = "%d%%" % int(v)
		_apply_setting("master_volume", v / 100.0))
	var vol_box := HBoxContainer.new()
	vol_box.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	vol_box.add_child(vol)
	vol_box.add_child(volume_value)
	general.body.add_child(_row("options.volume", vol_box))

	var fs := CheckBox.new()
	fs.button_pressed = bool(s.get("fullscreen", false))
	fs.toggled.connect(func(on: bool) -> void: _apply_setting("fullscreen", on))
	general.body.add_child(_row("options.fullscreen", fs))

	var scale_opt := OptionButton.new()
	for key: String in ["options.ui_scale_compact", "options.ui_scale_normal", "options.ui_scale_large"]:
		scale_opt.add_item(DataRegistry.t(key))
	scale_opt.selected = GameSettings.UI_SCALE_STEPS.find(GameSettings.nearest_step(float(s.get("ui_scale", 1.0))))
	scale_opt.item_selected.connect(func(i: int) -> void: _apply_setting("ui_scale", GameSettings.UI_SCALE_STEPS[i]))
	UITooltip.attach(scale_opt, DataRegistry.t("options.ui_scale_tip"))
	general.body.add_child(_row("options.ui_scale", scale_opt))

	var image := OptionButton.new()
	for id in RetroView.PRESETS:
		image.add_item(DataRegistry.t("options.preset_" + id))
	image.selected = RetroView.PRESETS.find(RetroView.preset_id())
	image.item_selected.connect(func(i: int) -> void: _apply_setting("retro_preset", RetroView.PRESETS[i]))
	UITooltip.attach(image, DataRegistry.t("options.image_tip"))
	general.body.add_child(_row("options.image", image))

	var bob := CheckBox.new()
	bob.button_pressed = bool(s.get("head_bob", true))
	bob.toggled.connect(func(on: bool) -> void: _apply_setting("head_bob", on))
	UITooltip.attach(bob, DataRegistry.t("options.head_bob_tip"))
	general.body.add_child(_row("options.head_bob", bob))

	# Pixel art o modelo 3D (para comparar mientras el arte es de prueba).
	var enemies := OptionButton.new()
	for key: String in ["options.enemies_sprite", "options.enemies_model"]:
		enemies.add_item(DataRegistry.t(key))
	enemies.selected = 0 if String(s.get("enemy_style", "sprite")) == "sprite" else 1
	enemies.item_selected.connect(func(i: int) -> void: _apply_setting("enemy_style", "sprite" if i == 0 else "model"))
	UITooltip.attach(enemies, DataRegistry.t("options.enemies_tip"))
	general.body.add_child(_row("options.enemies", enemies))

	var lang := OptionButton.new()
	lang.add_item(DataRegistry.t("options.language_es"))
	lang.disabled = true
	general.body.add_child(_row("options.language", lang))
	return vol

## Fila de ajuste: etiqueta de ancho fijo + control.
func _row(label_key: String, control: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	var l := UILabel.make(DataRegistry.t(label_key))
	l.custom_minimum_size.x = LABEL_WIDTH
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(l)
	control.custom_minimum_size.x = CONTROL_WIDTH
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(control)
	return r

func _build_right(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	parent.add_child(col)
	var tabs := UITabs.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tabs)
	tabs.add_tab(DataRegistry.t("options.controls"), _controls_page(), "opciones")
	tabs.add_tab(DataRegistry.t("options.credits"), _credits_page(), "bestiario")
	if from_hub:
		var reset := UIButton.make(DataRegistry.t("options.reset_save"), _reset_save, "DangerButton")
		reset.size_flags_horizontal = Control.SIZE_SHRINK_END
		reset.custom_minimum_size.x = 220
		col.add_child(reset)

## Acción · [teclas] · [botones del mando], todo en KeyCaps.
func _controls_page() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UIStyle.SPACE * 4)
	grid.add_theme_constant_override("v_separation", UIStyle.SPACE * 2)
	for action in Controls.DISPLAY_ORDER:
		_controls_row(grid, DataRegistry.t("controls." + action), Controls.key_names(action), Controls.pad_names(action))
	# Menús: "↑↓ / Enter / Esc  ·  Cruceta / A / B" (teclado · mando).
	var parts := DataRegistry.t("controls.menus_keys").split("·")
	var keys: Array[String] = []
	var pads: Array[String] = []
	for k in parts[0].split("/"):
		keys.append(k.strip_edges())
	if parts.size() > 1:
		for b in parts[1].split("/"):
			pads.append(b.strip_edges())
	_controls_row(grid, DataRegistry.t("controls.menus"), keys, pads)
	return grid

func _controls_row(grid: GridContainer, text: String, keys: Array[String], pads: Array[String]) -> void:
	var l := UILabel.make(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(l)
	for names: Array[String] in [keys, pads]:
		var caps := HBoxContainer.new()
		caps.add_theme_constant_override("separation", UIStyle.SPACE)
		for n in names:
			caps.add_child(UITabs.make_keycap(n))
		grid.add_child(caps)

func _credits_page() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	for key: String in ["credits.fonts", "credits.icons", "credits.sounds", "credits.models"]:
		box.add_child(UILabel.make(DataRegistry.t(key), "DetailLabel", true))
	return box

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
