class_name MapScreen
extends UIScreen
## Mapa completo del piso (M / Select): solo lo descubierto, con leyenda que
## usa los mismos marcadores del kit que el mapa.

const LEGEND: Array = [
	["map_player", "map.you"], ["map_enemy", "map.enemy"], ["map_chest", "map.chest"],
	["map_exit", "map.exit"], ["map_stairs", "map.exit_open"],
]

var run: Node

func _init(p_run: Node = null) -> void:
	super(DataRegistry.t("map.title"))
	run = p_run

func _ready() -> void:
	super._ready()
	toggle_action = "open_map"
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	body.add_child(row)
	var map_panel := PanelContainer.new()
	map_panel.theme_type_variation = "PanelAlt"
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(map_panel)
	var map := UIMinimap.new(true)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.add_child(map)
	if run:
		map.update_view(run.get("fd"), GameState.visited, run.get("player").get("grid_pos"), int(run.get("player").get("facing")), run.call("map_markers"))

	var legend := UIPanel.new(DataRegistry.t("map.legend"), "PanelAlt")
	legend.custom_minimum_size.x = 280
	legend.body.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	row.add_child(legend)
	var floors := DataRegistry.bal_i("floors_per_run", 5)
	var floor_row := HBoxContainer.new()
	floor_row.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	floor_row.add_child(UIIcon.make("piso", "bronce"))
	var floor_label := UILabel.make(DataRegistry.t("hub.last_floor_of", [UIFormat.roman(GameState.floor_n), UIFormat.roman(floors)]).to_upper(), "NumLabel")
	floor_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	floor_row.add_child(floor_label)
	legend.body.add_child(floor_row)
	legend.body.add_child(UIPips.new(GameState.floor_n, floors))
	legend.body.add_child(UIDivider.new(240))
	for pair: Array in LEGEND:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", UIStyle.SPACE * 3)
		var box := CenterContainer.new()
		box.custom_minimum_size = Vector2(20, 32)
		var mark := TextureRect.new()
		mark.texture = UIIcon.kit_texture(String(pair[0]))
		mark.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		box.add_child(mark)
		line.add_child(box)
		var l := UILabel.make(DataRegistry.t(String(pair[1])))
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(l)
		legend.body.add_child(line)
	add_footer_button(DataRegistry.t("ui.close"), close)
	UIFocus.grab_first(footer)
