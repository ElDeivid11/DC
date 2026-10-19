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
	title_label.text = DataRegistry.t("bestiary.title_count", [seen, ids.size()])
	add_footer_button(DataRegistry.t("ui.back"), close)

func _fill_list() -> void:
	for id in ids:
		var sp := DataRegistry.get_species(id)
		var e := MetaState.bestiary_entry(id)
		if not e.seen:
			add_row("???", [["", "DimLabel", 90], [DataRegistry.t("ui.rank_short", [int(sp.rank)]), "DimLabel", 50]], true)
		else:
			add_row(String(sp.display_name), [
				[DataRegistry.t("bestiary.kills_short", [int(e.kills)]), "DimLabel", 90],
				[DataRegistry.t("ui.rank_short", [int(sp.rank)]), "AccentLabel", 50],
			])

func _show_detail(index: int) -> void:
	var id := ids[index]
	var sp := DataRegistry.get_species(id)
	var e := MetaState.bestiary_entry(id)
	if not e.seen:
		detail.set_title("???")
		detail_line(DataRegistry.t("bestiary.unseen"), "DimLabel")
		detail_box.add_child(UIRankBadge.new(int(sp.rank)))
		return
	detail.set_title(String(sp.display_name))
	var head := HBoxContainer.new()
	detail_box.add_child(head)
	head.add_child(UIRankBadge.new(int(sp.rank)))
	var desc := Label.new()
	desc.text = String(sp.description)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(desc)
	var stats := DataRegistry.stats_for_rank(int(sp.rank))
	detail_line(DataRegistry.t("bestiary.stats", [stats.hp, stats.atk]), "")
	detail_line(DataRegistry.t("bestiary.kills", [int(e.kills)]), "DimLabel")
	if int(e.kills) == 0:
		detail_line(DataRegistry.t("bestiary.first_kill_pending", [UIFormat.coins(RunRules.first_kill_bonus(int(sp.rank)))]), "CoinLabel")
	else:
		detail_line(DataRegistry.t("bestiary.first_kill_done", [int(e.first_kill_run)]), "DetailLabel")
	detail_line(DataRegistry.t("bestiary.soul"), "SoulLabel")
	if int(e.souls_taken) > 0:
		detail_box.add_child(UISoulCard.new(DataRegistry.make_soul(String(sp.soul_id), int(sp.rank), String(sp.display_name))))
	else:
		detail_line(DataRegistry.t("bestiary.soul_unknown"), "DimLabel")
