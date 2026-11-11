class_name ForgeScreen
extends UIScreen
## Forja de almas (un altar del piso): por cada alma del héroe, su tarjeta y
## lo que se puede hacer con ella:
##   Templar     paga monedas de la run y sube un rango (más poder), hasta el I
##   Fundir      con otra igual: queda una sola, dos rangos mejor, y se
##               libera un espacio
##   Sacrificar  la destruye a cambio de monedas (con confirmación)
## Las reglas, en GameState (temper_soul, fuse_souls, sacrifice_soul).

var list: VBoxContainer
var _busy := false

func _init() -> void:
	super(DataRegistry.t("forge.title"))

func _ready() -> void:
	super._ready()
	var intro := UILabel.make(DataRegistry.t("forge.intro"), "DimLabel", true)
	body.add_child(intro)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	scroll.add_child(list)
	add_footer_button(DataRegistry.t("ui.close"), close)
	_rebuild()

## Rearma la lista (después de cada cambio) y deja el foco en un botón.
func _rebuild() -> void:
	show_coins(GameState.run_coins())
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var souls: Array = GameState.hero().get("souls", [])
	if souls.is_empty():
		list.add_child(UILabel.make(DataRegistry.t("forge.empty"), "DimLabel", true))
		UIFocus.grab_first(footer)
		return
	var core := GameState.preview_core()
	var pairs := GameState.fusable_pairs()
	var buttons: Array = []
	for i in souls.size():
		var soul: Dictionary = souls[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UIStyle.SPACE * 3)
		list.add_child(row)
		var card := UISoulCard.new(soul, true, core, i)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		var col := VBoxContainer.new()
		col.custom_minimum_size.x = 300
		col.add_theme_constant_override("separation", UIStyle.SPACE)
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(col)
		var idx := i
		if GameState.can_temper(i):
			var cost := GameState.temper_cost(soul)
			var temper := UIButton.make(DataRegistry.t("forge.temper", [UIFormat.roman(int(soul.source_rank) - 1), cost]), func() -> void: _temper(idx))
			temper.disabled = cost > GameState.run_coins()
			UITooltip.attach(temper, DataRegistry.t("forge.temper_tip"))
			col.add_child(temper)
			buttons.append(temper)
		else:
			col.add_child(UILabel.make(DataRegistry.t("forge.max_rank"), "AccentLabel"))
		for pair: Array in pairs:
			if int(pair[0]) == i:
				var other := int(pair[1])
				var fuse := UIButton.make(DataRegistry.t("forge.fuse"), func() -> void: _fuse(idx, other))
				UITooltip.attach(fuse, DataRegistry.t("forge.fuse_tip", [DataRegistry.bal_i("eventos.forja_fundir_rangos", 2)]))
				col.add_child(fuse)
				buttons.append(fuse)
				break
		var sac := UIButton.make(DataRegistry.t("forge.sacrifice", [GameState.sacrifice_value(soul)]), func() -> void: _sacrifice(idx), "DangerButton")
		col.add_child(sac)
		buttons.append(sac)
	UIFocus.chain_vertical(buttons)
	var first: Control = null
	for b: Control in buttons:
		if not (b as UIButton).disabled:
			first = b
			break
	if first:
		first.call_deferred("grab_focus")
	else:
		UIFocus.grab_first(footer)

func _temper(i: int) -> void:
	if _busy:
		return
	if GameState.temper_soul(i):
		SceneRouter.play_ui("level_up")
		UIToast.show(get_tree(), DataRegistry.t("forge.tempered", [_soul_name(i)]), "soul")
	else:
		SceneRouter.play_ui("error")
	_rebuild()

func _fuse(i: int, j: int) -> void:
	if _busy:
		return
	var soul_name := _soul_name(i)
	if GameState.fuse_souls(i, j):
		SceneRouter.play_ui("soul")
		UIToast.show(get_tree(), DataRegistry.t("forge.fused", [soul_name]), "soul")
	_rebuild()

func _sacrifice(i: int) -> void:
	if _busy:
		return
	_busy = true
	var soul: Dictionary = GameState.hero().souls[i]
	var d := UIConfirmDialog.ask(self, DataRegistry.t("forge.sacrifice_title"), DataRegistry.t("forge.sacrifice_text", [_soul_name(i), GameState.sacrifice_value(soul)]), DataRegistry.t("forge.sacrifice_yes"), DataRegistry.t("ui.cancel"), true)
	var yes: bool = await d.answered
	_busy = false
	if yes:
		var value := GameState.sacrifice_soul(i)
		SceneRouter.play_ui("coin")
		UIToast.show(get_tree(), DataRegistry.t("forge.sacrificed", [value]), "coin")
	_rebuild()

static func _soul_name(i: int) -> String:
	var souls: Array = GameState.hero().get("souls", [])
	if i < 0 or i >= souls.size():
		return ""
	return String(((souls[i] as Dictionary).get("active", {}) as Dictionary).get("name", ""))
