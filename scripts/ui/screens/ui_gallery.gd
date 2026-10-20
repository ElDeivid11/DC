extends UIScreen
## "UI Gallery": todos los componentes del design system en una sola pantalla,
## para revisar el diseño antes (y después) de armar menús. Se abre desde
## Opciones (en debug) o desde el panel de debug (F1).

func _ready() -> void:
	super._ready()
	title_label.text = DataRegistry.t("gallery.title")
	show_coins(1240)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	scroll.add_child(cols)

	var left := _column(cols)
	var mid := _column(cols)
	var right := _column(cols)

	# Botones y menú
	var buttons := UIPanel.new(DataRegistry.t("gallery.buttons"), "PanelAlt")
	left.add_child(buttons)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 0)
	buttons.body.add_child(menu)
	for key: String in ["hub.start", "hub.upgrades", "hub.unlocks"]:
		menu.add_child(UIMenuItem.make_item(DataRegistry.t(key), func() -> void: pass))
	var row := HBoxContainer.new()
	buttons.body.add_child(row)
	row.add_child(UIButton.make(DataRegistry.t("ui.accept"), func() -> void: pass))
	row.add_child(UIButton.make(DataRegistry.t("ui.danger_example"), func() -> void: pass, "DangerButton"))
	var disabled := UIButton.new(DataRegistry.t("ui.disabled_example"))
	disabled.disabled = true
	row.add_child(disabled)

	# Tipografía
	var labels := UIPanel.new(DataRegistry.t("gallery.labels"), "PanelAlt")
	left.add_child(labels)
	for v: String in ["TitleLabel", "SubtitleLabel", "", "DimLabel", "DetailLabel", "AccentLabel", "CoinLabel", "SoulLabel", "GoodLabel", "DangerLabel"]:
		var l := Label.new()
		l.text = v if v != "" else "Label"
		if v != "":
			l.theme_type_variation = v
		labels.body.add_child(l)

	# Barras, rangos y progreso
	var bars := UIPanel.new(DataRegistry.t("gallery.bars"), "PanelAlt")
	mid.add_child(bars)
	var hp_full := UIStatBar.new("Bjorn")
	hp_full.set_values(18, 18)
	bars.body.add_child(hp_full)
	var hp_mid := UIStatBar.new("Elena")
	hp_mid.set_values(7, 16)
	bars.body.add_child(hp_mid)
	var hp_low := UIStatBar.new("Goblin")
	hp_low.set_values(2, 14)
	bars.body.add_child(hp_low)
	var soul_bar := UIStatBar.new(DataRegistry.t("gallery.soul"), "soul")
	soul_bar.set_values(3, 5)
	bars.body.add_child(soul_bar)
	var badges := HBoxContainer.new()
	for r in range(10, 0, -1):
		badges.add_child(UIRankBadge.new(r))
	bars.body.add_child(badges)
	bars.body.add_child(UIProgressUnlock.new(DataRegistry.get_unlock("u_esqueletos").get("descripcion", ""), 9, 15))
	bars.body.add_child(UIProgressUnlock.new(DataRegistry.get_unlock("u_piso_3").get("descripcion", ""), 3, 3))

	# Almas
	var souls := UIPanel.new(DataRegistry.t("gallery.souls"), "PanelAlt")
	mid.add_child(souls)
	souls.body.add_child(UISoulCard.new(DataRegistry.make_soul("esqueleto_picaro", 8, "Esqueleto ballestero")))
	souls.body.add_child(UISoulCard.new(DataRegistry.make_soul("esqueleto_guardian", 4, "Esqueleto guardián"), true))
	# Retratos y hexágono de estadísticas (contorno verde = reparto pendiente).
	var hero_row := HBoxContainer.new()
	hero_row.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	souls.body.add_child(hero_row)
	var pics := VBoxContainer.new()
	hero_row.add_child(pics)
	pics.add_child(UIPortrait.for_hero("bjorn", 56))
	var fallen := UIPortrait.for_hero("elena", 56)
	fallen.set_dimmed(true)
	pics.add_child(fallen)
	var radar := UIStatRadar.new(170)
	radar.set_values({"vit": 4, "atq": 3, "def": 1, "esp": 0, "agi": 2, "sue": 1}, {"esp": 2, "def": 1})
	hero_row.add_child(radar)

	# Objetos, tooltip, diálogo, toasts
	var items := UIPanel.new(DataRegistry.t("gallery.items"), "PanelAlt")
	right.add_child(items)
	var grid := GridContainer.new()
	grid.columns = 1
	items.body.add_child(grid)
	for id: String in ["pocion_menor", "talisman_hueso", "bomba_humo", ""]:
		var slot := UIItemSlot.new(id)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(slot)

	var feedback := UIPanel.new(DataRegistry.t("gallery.feedback"), "PanelAlt")
	right.add_child(feedback)
	var tip := UIButton.new(DataRegistry.t("gallery.tooltip_button"))
	UITooltip.attach(tip, DataRegistry.t("gallery.tooltip_text"))
	feedback.body.add_child(tip)
	feedback.body.add_child(UIButton.make(DataRegistry.t("gallery.confirm_button"), _demo_confirm))
	var toasts := HFlowContainer.new()
	feedback.body.add_child(toasts)
	for kind: String in ["info", "good", "danger", "coin", "soul"]:
		toasts.add_child(UIButton.make(kind, func() -> void: UIToast.show(get_tree(), DataRegistry.t("gallery.toast_text", [kind]), kind)))

	# Entradas y pestañas
	var inputs := UIPanel.new(DataRegistry.t("gallery.inputs"), "PanelAlt")
	right.add_child(inputs)
	var check := CheckBox.new()
	check.text = DataRegistry.t("options.fullscreen")
	inputs.body.add_child(check)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.value = 80
	slider.focus_mode = Control.FOCUS_ALL
	inputs.body.add_child(slider)
	var option := OptionButton.new()
	option.add_item("Español")
	inputs.body.add_child(option)
	var edit := LineEdit.new()
	edit.placeholder_text = DataRegistry.t("debug.seed_placeholder")
	inputs.body.add_child(edit)
	var tabs := UITabs.new()
	tabs.custom_minimum_size.y = 90
	for key: String in ["status.tab_party", "status.tab_souls", "status.tab_items"]:
		var l := Label.new()
		l.text = DataRegistry.t(key)
		tabs.add_tab(DataRegistry.t(key), l)
	inputs.body.add_child(tabs)

	add_footer_button(DataRegistry.t("ui.back"), close)
	focus_first()

func _column(parent: Container) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	parent.add_child(c)
	return c

func _demo_confirm() -> void:
	var d := UIConfirmDialog.ask(self, DataRegistry.t("gallery.confirm_title"), DataRegistry.t("gallery.confirm_text"), DataRegistry.t("ui.yes"), DataRegistry.t("ui.no"), true)
	var yes: bool = await d.answered
	UIToast.show(get_tree(), DataRegistry.t("ui.yes") if yes else DataRegistry.t("ui.no"), "good" if yes else "info")

## Abierta como escena propia → volver al Hub; como overlay → cerrarse.
func close() -> void:
	if get_tree().current_scene == self:
		SceneRouter.goto(SceneRouter.HUB)
	else:
		super.close()
