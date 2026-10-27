class_name BestiaryScreen
extends ListDetailScreen
## Bestiario persistente: especies vistas / no vistas (???), rango, stats, y
## el alma que dan (revelada solo si alguna vez se recogió una). La primera
## kill de cada especie da un bonus de monedas una sola vez.

var ids: Array[String] = []

func _init() -> void:
	super(DataRegistry.t("bestiary.title"))

func _ready() -> void:
	ids = DataRegistry.species_ids()
	super._ready()
	var seen := 0
	for id in ids:
		if MetaState.bestiary_entry(id).seen:
			seen += 1
	show_count("%d/%d" % [seen, ids.size()])
	add_footer_button(DataRegistry.t("ui.back"), close)

func _fill_list() -> void:
	for id in ids:
		var sp := DataRegistry.get_species(id)
		var e := MetaState.bestiary_entry(id)
		var columns: Array = []
		if e.seen:
			var kills := HBoxContainer.new()
			kills.add_theme_constant_override("separation", 4)
			kills.add_child(UIIcon.make("muerte", "bronce"))
			var n := col(DataRegistry.t("bestiary.kills_short", [int(e.kills)]), "NumLabel", 56)
			n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			kills.add_child(n)
			columns.append(kills)
			var seal := UISprite.new("seal_mini") if int(e.kills) > 0 else Control.new()
			seal.custom_minimum_size = Vector2(18, 18)
			columns.append(seal)
		columns.append(UIRankBadge.new(int(sp.rank)))
		add_row(String(sp.display_name) if e.seen else "???", columns, not e.seen, "bestiario")

func _show_detail(index: int) -> void:
	var id := ids[index]
	var sp := DataRegistry.get_species(id)
	var e := MetaState.bestiary_entry(id)
	var info := detail_header(String(sp.display_name) if e.seen else "???", null, "muerte", "bronce" if e.seen else "apagado")
	var plate_row := HBoxContainer.new()
	plate_row.add_theme_constant_override("separation", 12)
	info.add_child(plate_row)
	plate_row.add_child(UIRankBadge.new(int(sp.rank)))
	if not e.seen:
		detail_line(DataRegistry.t("bestiary.unseen"), "DimLabel")
		return
	var stats := DataRegistry.stats_for_rank(int(sp.rank))
	var stat_label := UILabel.make(DataRegistry.t("bestiary.stats", [stats.hp, stats.atk]).to_upper(), "NumSmallLabel")
	stat_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate_row.add_child(stat_label)
	detail_line(String(sp.description))
	detail_box.add_child(UILedgerRow.new(DataRegistry.t("bestiary.kills_label"), "%d" % int(e.kills), "NumLabel", "muerte", "bronce"))
	if int(e.kills) == 0:
		detail_line(DataRegistry.t("bestiary.first_kill_pending", [UIFormat.coins(RunRules.first_kill_bonus(int(sp.rank)))]), "AccentLabel")
	else:
		detail_line(DataRegistry.t("bestiary.first_kill_done", [int(e.first_kill_run)]), "DetailLabel")
	detail_line(DataRegistry.t("bestiary.soul"), "SoulLabel")
	if String(sp.get("tier", "")) == "jefe":
		_show_boss_souls(id)
	elif int(e.souls_taken) > 0:
		# Ya absorbiste alguna: se ven todas las que puede soltar (para planear).
		var souls: Array = sp.get("almas", [])
		detail_line(DataRegistry.t("bestiary.souls_count", [souls.size()]), "DetailLabel")
		for sid: Variant in souls:
			var soul := DataRegistry.make_soul(String(sid), int(sp.rank), String(sp.display_name))
			soul.erase("source_rank")
			detail_box.add_child(UISoulCard.new(soul))
	else:
		detail_line(DataRegistry.t("bestiary.soul_unknown"), "DimLabel")

## Los jefes cambian piso a piso (nombre, rango y alma propios, ver
## floors.json): se muestra el alma de cada jefe de esta especie ya vencido.
func _show_boss_souls(species_id: String) -> void:
	var defeated: Dictionary = MetaState.progress.get("bosses_defeated", {})
	for n in range(1, DataRegistry.floor_count() + 1):
		var b: Dictionary = DataRegistry.get_floor(n).get("boss", {})
		if String(b.get("species", "")) != species_id:
			continue
		if defeated.has(str(n)):
			detail_line(DataRegistry.t("bestiary.boss_soul", [n, b.display_name]), "DetailLabel")
			detail_box.add_child(UISoulCard.new(DataRegistry.make_soul(String(b.soul_id), int(b.rank), String(b.display_name))))
		else:
			detail_line(DataRegistry.t("bestiary.boss_soul_unknown", [n]), "DimLabel")
