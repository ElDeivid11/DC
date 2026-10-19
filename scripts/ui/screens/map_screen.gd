class_name MapScreen
extends UIScreen
## Mapa completo del piso (M / Select): solo lo descubierto, con leyenda.

var run: Node

func _init(p_run: Node = null) -> void:
	super(DataRegistry.t("map.title"))
	run = p_run

func _ready() -> void:
	super._ready()
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var map := UIMinimap.new(true)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(map)
	if run:
		map.update_view(run.get("fd"), GameState.visited, run.get("player").get("grid_pos"), int(run.get("player").get("facing")), run.call("map_markers"))
	var legend := UIPanel.new(DataRegistry.t("map.legend"), "PanelAlt")
	legend.custom_minimum_size.x = 260
	row.add_child(legend)
	for pair: Array in [["map.you", "AccentLabel"], ["map.enemy", "DangerLabel"], ["map.chest", "CoinLabel"], ["map.item", "AccentLabel"], ["map.exit", "SoulLabel"]]:
		var l := Label.new()
		l.text = DataRegistry.t(String(pair[0]))
		l.theme_type_variation = String(pair[1])
		legend.body.add_child(l)
	var floor_info := Label.new()
	floor_info.theme_type_variation = "DimLabel"
	floor_info.text = DataRegistry.t("hud.floor", [GameState.floor_n, DataRegistry.bal_i("floors_per_run", 5)])
	legend.body.add_child(floor_info)
	add_footer_button(DataRegistry.t("ui.close"), close)
	UIFocus.grab_first(footer)
