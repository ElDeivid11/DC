class_name PauseMenu
extends UIScreen
## Pausa (Esc / Start): continuar, estado, inventario, mapa, opciones y
## abandonar la expedición (con confirmación). El árbol queda en pausa
## mientras está abierta (el reloj de la run se frena).

var run: Node

func _init(p_run: Node = null) -> void:
	super(DataRegistry.t("pause.title"), true)
	run = p_run

func _ready() -> void:
	super._ready()
	toggle_action = "pause"
	var center := CenterContainer.new()
	body.add_child(center)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", UIStyle.SPACE)
	center.add_child(menu)
	var items: Array = [
		UIMenuItem.make_item(DataRegistry.t("pause.continue"), close, "continuar"),
		UIMenuItem.make_item(DataRegistry.t("pause.status"), func() -> void: _open(StatusScreen.new()), "estado"),
		UIMenuItem.make_item(DataRegistry.t("pause.inventory"), func() -> void: _open(InventoryScreen.new(run)), "inventario"),
		UIMenuItem.make_item(DataRegistry.t("pause.map"), func() -> void: _open(MapScreen.new(run)), "mapa"),
		UIMenuItem.make_item(DataRegistry.t("pause.options"), func() -> void: _open(OptionsScreen.new(false)), "opciones"),
		UIMenuItem.make_item(DataRegistry.t("pause.abandon"), _abandon, "retiro", true),
	]
	for it: Control in items:
		menu.add_child(it)
	UIFocus.chain_vertical(items)
	var divider := UIDivider.new(360)
	divider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(divider)
	var info := UILabel.make(DataRegistry.t("pause.run_info", [UIFormat.time(GameState.elapsed_sec), GameState.kills_total, GameState.run_seed]), "DetailLabel")
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(info)
	focus_first()

func _open(screen: UIScreen) -> void:
	add_child(screen)
	screen.closed.connect(focus_first)

func _abandon() -> void:
	var d := UIConfirmDialog.ask(self, DataRegistry.t("pause.abandon_title"), DataRegistry.t("pause.abandon_text", [UIFormat.pct(RunRules.keep_fraction("abandono"))]), DataRegistry.t("pause.abandon_yes"), DataRegistry.t("ui.cancel"), true)
	if await d.answered and run:
		run.call("end_run", "abandono", DataRegistry.t("pause.abandon_cause"))
