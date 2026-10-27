class_name StatsScreen
extends UIScreen
## Estadísticas globales como libro de cuentas: runs, resultados, mejor piso,
## kills (también por especie), tiempo total, monedas, desbloqueos y especies
## descubiertas. Filas UILedgerRow con ícono.

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

	var general := _panel(row, "stats.general")
	var seen := 0
	for id in DataRegistry.species_ids():
		if MetaState.bestiary_entry(id).seen:
			seen += 1
	var unlocked := DataRegistry.unlocks.keys().filter(func(id: String) -> bool: return MetaState.is_unlocked(id)).size()
	# [clave, valor, variación del valor, ícono, rampa]
	var rows: Array = [
		["stats.runs", UIFormat.number(int(s.runs)), "NumLabel", "iniciar", "bronce"],
		["stats.wins", UIFormat.number(int(s.wins)), "NumLabel", "victoria", "moneda"],
		["stats.retreats", UIFormat.number(int(s.retreats)), "NumLabel", "retiro", "bronce"],
		["stats.deaths", UIFormat.number(int(s.deaths)), "NumLabel", "muerte", "sangre"],
		["stats.best_floor", UIFormat.roman(int(s.best_floor)), "NumLabel", "piso", "bronce"],
		["stats.time", UIFormat.time(float(s.total_time_sec)), "NumLabel", "tiempo", "bronce"],
		["stats.coins_total", UIFormat.number(int(s.coins_earned_total)), "CoinLabel", "monedas", "moneda"],
	]
	for r: Array in rows:
		general.body.add_child(UILedgerRow.new(DataRegistry.t(String(r[0])), String(r[1]), String(r[2]), String(r[3]), String(r[4])))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	row.add_child(right)
	var collection := _panel(right, "stats.collection")
	collection.body.add_child(UILedgerRow.new(DataRegistry.t("stats.unlocks"), "%d/%d" % [unlocked, DataRegistry.unlocks.size()], "NumLabel", "desbloqueos", "bronce"))
	collection.body.add_child(UILedgerRow.new(DataRegistry.t("stats.species"), "%d/%d" % [seen, DataRegistry.species_ids().size()], "NumLabel", "bestiario", "bronce"))

	var kills := _panel(right, "stats.kills_by_species")
	kills.size_flags_vertical = Control.SIZE_EXPAND_FILL
	kills.body.add_child(UILedgerRow.new(DataRegistry.t("stats.kills"), UIFormat.number(int(s.total_kills)), "NumLabel", "muerte", "bronce"))
	var any := false
	for id in DataRegistry.species_ids():
		var e := MetaState.bestiary_entry(id)
		if int(e.kills) <= 0:
			continue
		any = true
		var sp := DataRegistry.get_species(id)
		var line := UILedgerRow.new(String(sp.display_name), UIFormat.number(int(e.kills)), "NumLabel")
		line.add_child(UIRankBadge.new(int(sp.rank)))
		line.move_child(line.get_child(line.get_child_count() - 1), 0)
		kills.body.add_child(line)
	if not any:
		var empty := UIGothicLabel.new(DataRegistry.t("stats.no_kills"), "GothicQuote", UIStyle.TEXT_DIM, UIStyle.TEXT_DIM)
		kills.body.add_child(empty)
	add_footer_button(DataRegistry.t("ui.back"), close)
	UIFocus.grab_first(footer)

func _panel(parent: Control, title_key: String) -> UIPanel:
	var p := UIPanel.new(DataRegistry.t(title_key), "PanelAlt")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.body.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	parent.add_child(p)
	return p
