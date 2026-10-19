class_name PauseMenu
extends UIScreen
## Pausa (Esc / Start): continuar, estado, inventario, mapa, opciones y
## abandonar la expedición (con confirmación). El árbol queda en pausa
## mientras está abierta (el reloj de la run se frena).

var run: Node

func _init(p_run: Node = null) -> void:
	super(DataRegistry.t("pause.title"))
	run = p_run

func _ready() -> void:
	super._ready()
	toggle_action = "pause"
	show_coins(GameState.run_coins())
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 0)
	menu.custom_minimum_size.x = 360
	center.add_child(menu)
	var items: Array = [
		UIMenuItem.make_item(DataRegistry.t("pause.continue"), close),
		UIMenuItem.make_item(DataRegistry.t("pause.status"), func() -> void: _open(StatusScreen.new())),
		UIMenuItem.make_item(DataRegistry.t("pause.inventory"), func() -> void: _open(InventoryScreen.new(run))),
		UIMenuItem.make_item(DataRegistry.t("pause.map"), func() -> void: _open(MapScreen.new(run))),
		UIMenuItem.make_item(DataRegistry.t("pause.options"), func() -> void: _open(OptionsScreen.new(false))),
		UIMenuItem.make_item(DataRegistry.t("pause.abandon"), _abandon),
	]
	for it: Control in items:
		menu.add_child(it)
	UIFocus.chain_vertical(items)
	var seed_label := Label.new()
	seed_label.theme_type_variation = "DetailLabel"
	seed_label.text = DataRegistry.t("pause.run_info", [UIFormat.time(GameState.elapsed_sec), GameState.kills_total, GameState.run_seed])
	seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(seed_label)
	focus_first()

func _open(screen: UIScreen) -> void:
	add_child(screen)
	screen.closed.connect(focus_first)

func _abandon() -> void:
	var d := UIConfirmDialog.ask(self, DataRegistry.t("pause.abandon_title"), DataRegistry.t("pause.abandon_text", [UIFormat.pct(RunRules.keep_fraction("abandono"))]), DataRegistry.t("pause.abandon_yes"), DataRegistry.t("ui.cancel"), true)
	if await d.answered and run:
		run.call("end_run", "abandono", DataRegistry.t("pause.abandon_cause"))
