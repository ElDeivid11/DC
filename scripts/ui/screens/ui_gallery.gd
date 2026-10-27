extends UIScreen
## "UI Gallery": todos los componentes del design system en una sola pantalla,
## para revisar el diseño antes (y después) de armar menús. Se abre desde
## Opciones (en debug) o desde el panel de debug (F1).

func _ready() -> void:
	super._ready()
	title_label.text = DataRegistry.t("gallery.title")
	show_coins(1240)

	# El cuerpo de UIScreen ya se desplaza (sigue al foco).
	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	body.add_child(cols)

	var left := _column(cols)
	var mid := _column(cols)
	var right := _column(cols)

	# Botones y menú
	var buttons := UIPanel.new(DataRegistry.t("gallery.buttons"), "PanelAlt")
	left.add_child(buttons)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 0)
	buttons.body.add_child(menu)
	for pair: Array in [["hub.start", "iniciar", false], ["hub.upgrades", "mejoras", false], ["hub.quit", "salir", true]]:
		var item := UIMenuItem.make_item(DataRegistry.t(String(pair[0])), func() -> void: pass, String(pair[1]), bool(pair[2]))
		item.custom_minimum_size.x = 340
		menu.add_child(item)
	var list_row := UIListRow.new(DataRegistry.get_item("pocion_menor").get("nombre", ""), "", UIPortrait.item_texture("pocion_menor"))
	list_row.add_column(UIPips.new(2, 5))
	buttons.body.add_child(list_row)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UIStyle.SPACE * 2)
	row.add_theme_constant_override("v_separation", UIStyle.SPACE * 2)
	buttons.body.add_child(row)
	row.add_child(UIButton.make(DataRegistry.t("ui.accept"), func() -> void: pass))
	row.add_child(UIButton.make(DataRegistry.t("ui.danger_example"), func() -> void: pass, "DangerButton"))
	var disabled := UIButton.new(DataRegistry.t("ui.disabled_example"))
	disabled.disabled = true
	row.add_child(disabled)

	# Tipografía
	var labels := UIPanel.new(DataRegistry.t("gallery.labels"), "PanelAlt")
	left.add_child(labels)
	labels.body.add_child(UIGothicLabel.new(DataRegistry.t("summary.epitaph_retire"), "GothicTitle", UIStyle.HUESO, UIStyle.RUBRICA_CLARA))
	labels.body.add_child(UIGothicLabel.new(DataRegistry.t("app.subtitle"), "GothicQuote", UIStyle.TEXT_DIM))
	labels.body.add_child(UIDivider.new(280))
	for v: String in ["HeadLabel", "", "DimLabel", "DetailLabel", "AccentLabel", "SoulLabel", "GoodLabel", "DangerLabel", "NumLabel", "CoinLabel", "XpLabel"]:
		var l := Label.new()
		l.text = v if v != "" else "Label"
		if v != "":
			l.theme_type_variation = v
		labels.body.add_child(l)
	labels.body.add_child(UILedgerRow.new(DataRegistry.t("summary.kills_coins"), "+42", "CoinLabel", "muerte"))

	# Barras, rangos y progreso
	var bars := UIPanel.new(DataRegistry.t("gallery.bars"), "PanelAlt")
	mid.add_child(bars)
	var hp_full := UIStatBar.new("Bjorn")
	hp_full.set_values(18, 18)
	bars.body.add_child(hp_full)
	var hp_mid := UIStatBar.new("Bjorn")
	hp_mid.set_values(7, 16)
	bars.body.add_child(hp_mid)
	var hp_low := UIStatBar.new("Goblin")
	hp_low.set_values(2, 14)
	bars.body.add_child(hp_low)
	var soul_bar := UIStatBar.new(DataRegistry.t("gallery.soul"), "soul")
	soul_bar.set_values(3, 5)
	bars.body.add_child(soul_bar)
	var xp_bar := UIStatBar.new(DataRegistry.t("attr.xp"), "xp")
	xp_bar.set_values(30, 76)
	bars.body.add_child(xp_bar)
	var marks := HBoxContainer.new()
	marks.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	marks.add_child(UIPips.new(3, 5))
	marks.add_child(UIPips.new(2, 2, "vela"))
	marks.add_child(UISoulSlots.new(1, 3))
	marks.add_child(UITabs.make_keycap(DataRegistry.t("ui.key_q")))
	bars.body.add_child(marks)
	var badges := HFlowContainer.new()
	for r in range(10, 0, -1):
		badges.add_child(UIRankBadge.new(r))
	bars.body.add_child(badges)
	bars.body.add_child(UIProgressUnlock.new(DataRegistry.get_unlock("u_esqueletos").get("descripcion", ""), 9, 15))
	bars.body.add_child(UIProgressUnlock.new(DataRegistry.get_unlock("u_piso_3").get("descripcion", ""), 3, 3))

	# Almas
	var souls := UIPanel.new(DataRegistry.t("gallery.souls"), "PanelAlt")
	mid.add_child(souls)
	souls.body.add_child(UISoulCard.new(DataRegistry.make_soul("arquero_flecha", 8, "Esqueleto arquero")))
	souls.body.add_child(UISoulCard.new(DataRegistry.make_soul("guardian_hacha", 4, "Esqueleto guardián"), true))
	# Retratos y hexágono de estadísticas (contorno verde = reparto pendiente).
	var hero_row := HBoxContainer.new()
	hero_row.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	souls.body.add_child(hero_row)
	var pics := VBoxContainer.new()
	hero_row.add_child(pics)
	pics.add_child(UIPortrait.for_hero("bjorn", 56))
	var fallen := UIPortrait.for_hero("bjorn", 56)
	fallen.set_dimmed(true)
	pics.add_child(fallen)
	var radar := UIStatRadar.new(170)
	radar.set_values({"vit": 4, "atq": 3, "def": 1, "esp": 0, "agi": 2, "sue": 1}, {"esp": 2, "def": 1})
	hero_row.add_child(radar)

	# Objetos, tooltip, diálogo, toasts
	var items := UIPanel.new(DataRegistry.t("gallery.items"), "PanelAlt")
	right.add_child(items)
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", UIStyle.SPACE * 2)
	grid.add_theme_constant_override("v_separation", UIStyle.SPACE * 2)
	items.body.add_child(grid)
	for id: String in ["pocion_menor", "talisman_hueso", "bomba_humo", ""]:
		grid.add_child(UIItemSlot.new(id, true, true))
	items.body.add_child(UIItemSlot.type_plate("consumible"))

	# Íconos del kit (rampa bronce o la propia) y marcadores del mapa.
	var icons := UIPanel.new(DataRegistry.t("gallery.icons"), "PanelAlt")
	right.add_child(icons)
	var flow := HFlowContainer.new()
	icons.body.add_child(flow)
	for id in UIStyle.ICON_IDS:
		var icon := UIIcon.new(id, "bronce")
		if icon.texture == null:
			for ramp: String in ["vela", "alma", "moneda", "sangre", "amatista"]:
				if UIIcon.texture_for(id, ramp) != null:
					icon.set_ramp(ramp)
					break
		flow.add_child(icon)
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	for sprite: String in ["map_player", "map_enemy", "map_chest", "map_exit", "map_stairs", "seal_mini", "soul_full"]:
		map_row.add_child(UISprite.new(sprite))
	icons.body.add_child(map_row)

	var feedback := UIPanel.new(DataRegistry.t("gallery.feedback"), "PanelAlt")
	right.add_child(feedback)
	var tip := UIButton.new(DataRegistry.t("gallery.tooltip_button"))
	UITooltip.attach(tip, DataRegistry.t("gallery.tooltip_text"))
	feedback.body.add_child(tip)
	feedback.body.add_child(UIButton.make(DataRegistry.t("gallery.confirm_button"), _demo_confirm))
	feedback.body.add_child(UIButton.make(DataRegistry.t("gallery.boss_button"), _demo_boss_title))
	var toasts := HFlowContainer.new()
	feedback.body.add_child(toasts)
	for kind: String in ["info", "good", "danger", "coin", "soul", "level"]:
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
	for pair: Array in [["status.tab_party", "estado"], ["status.tab_souls", "almas"], ["status.tab_items", "inventario"]]:
		var l := Label.new()
		l.text = DataRegistry.t(String(pair[0]))
		tabs.add_tab(DataRegistry.t(String(pair[0])), l, String(pair[1]))
	inputs.body.add_child(tabs)

	add_footer_button(DataRegistry.t("ui.back"), close)
	focus_first()

func _column(parent: Container) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	parent.add_child(c)
	return c

## La presentación de un jefe: franjas de cine y su cartel.
func _demo_boss_title() -> void:
	var boss: Dictionary = DataRegistry.get_floor(1).get("boss", {})
	var cine := UICinematic.open(self)
	cine.show_title(DataRegistry.t("boss.card_floor", [UIFormat.roman(1)]), String(boss.get("display_name", "")),
		String(boss.get("epiteto", "")), 1.6)
	await cine.title_done
	cine.close()

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
