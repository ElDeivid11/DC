class_name StatsScreen
extends UIScreen
## Estadísticas globales: runs, resultados, mejor piso, kills (también por
## especie), tiempo total, monedas, desbloqueos y especies descubiertas.

func _init() -> void:
	super(DataRegistry.t("stats.title"))

func _ready() -> void:
	super._ready()
	show_coins(MetaState.coins)
	var s := MetaState.stats
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	body.add_child(row)

	var general := UIPanel.new(DataRegistry.t("stats.general"), "PanelAlt")
	general.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(general)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UIStyle.SPACE * 6)
	general.body.add_child(grid)
	var seen := 0
	for id in DataRegistry.species_ids():
		if MetaState.bestiary_entry(id).seen:
			seen += 1
	var pairs: Array = [
		["stats.runs", UIFormat.number(int(s.runs))],
		["stats.wins", UIFormat.number(int(s.wins))],
		["stats.retreats", UIFormat.number(int(s.retreats))],
		["stats.deaths", UIFormat.number(int(s.deaths))],
		["stats.best_floor", str(int(s.best_floor))],
		["stats.kills", UIFormat.number(int(s.total_kills))],
		["stats.time", UIFormat.time(float(s.total_time_sec))],
		["stats.coins_total", UIFormat.coins(int(s.coins_earned_total))],
		["stats.unlocks", "%d/%d" % [MetaState.unlocked.size(), DataRegistry.unlocks.size()]],
		["stats.species", "%d/%d" % [seen, DataRegistry.species.size()]],
	]
	for p: Array in pairs:
		var k := Label.new()
		k.text = DataRegistry.t(String(p[0]))
		k.theme_type_variation = "DimLabel"
		grid.add_child(k)
		var v := Label.new()
		v.text = String(p[1])
		v.theme_type_variation = "AccentLabel"
		grid.add_child(v)

	var kills := UIPanel.new(DataRegistry.t("stats.kills_by_species"), "PanelAlt")
	kills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(kills)
	var any := false
	for id in DataRegistry.species_ids():
		var e := MetaState.bestiary_entry(id)
		if int(e.kills) <= 0:
			continue
		any = true
		var l := Label.new()
		l.text = DataRegistry.t("stats.species_kills", [DataRegistry.get_species(id).display_name, int(e.kills)])
		kills.body.add_child(l)
	if not any:
		var empty := Label.new()
		empty.theme_type_variation = "DimLabel"
		empty.text = DataRegistry.t("stats.no_kills")
		kills.body.add_child(empty)
	add_footer_button(DataRegistry.t("ui.back"), close)
	UIFocus.grab_first(footer)
