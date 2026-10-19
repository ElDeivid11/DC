class_name UpgradesScreen
extends ListDetailScreen
## Mejoras de meta compradas con monedas, con TOPE por mejora (data/upgrades.json).
## Fila: nombre · ■■■□□ · efecto por nivel · siguiente coste. Comprar es
## instantáneo y se autoguarda.

var ids: Array[String] = []

func _init() -> void:
	super(DataRegistry.t("upgrades.title"))

func _ready() -> void:
	ids.assign(DataRegistry.upgrades.keys())
	ids.sort_custom(func(a: String, b: String) -> bool: return int(DataRegistry.get_upgrade(a).coste_base) < int(DataRegistry.get_upgrade(b).coste_base))
	super._ready()
	show_coins(MetaState.coins)
	add_footer_button(DataRegistry.t("ui.back"), close)

static func pips(level: int, max_level: int) -> String:
	return "■".repeat(level) + "□".repeat(maxi(max_level - level, 0))

static func effect_text(up: Dictionary, levels: int) -> String:
	var e: Dictionary = up.efecto
	return DataRegistry.t("upgrade.effect." + String(e.tipo), [roundi(float(e.valor) * levels)])

func _fill_list() -> void:
	for id in ids:
		var up := DataRegistry.get_upgrade(id)
		var lvl := MetaState.upgrade_level(id)
		var cost := MetaState.upgrade_cost(id)
		var cost_txt := UIFormat.coins(cost) if cost >= 0 else DataRegistry.t("upgrades.maxed")
		var cost_var := "CoinLabel" if cost >= 0 and MetaState.coins >= cost else "DimLabel"
		add_row(String(up.nombre), [
			[pips(lvl, int(up.max_nivel)), "AccentLabel", 90],
			[cost_txt, cost_var, 80],
		])

func _show_detail(index: int) -> void:
	var id := ids[index]
	var up := DataRegistry.get_upgrade(id)
	var lvl := MetaState.upgrade_level(id)
	var max_lvl := int(up.max_nivel)
	var cost := MetaState.upgrade_cost(id)
	detail.set_title(String(up.nombre))
	detail_line(String(up.descripcion))
	detail_line(DataRegistry.t("upgrades.level", [lvl, max_lvl, pips(lvl, max_lvl)]), "AccentLabel")
	detail_line(DataRegistry.t("upgrades.at_max", [effect_text(up, max_lvl)]), "DetailLabel")
	detail_line(DataRegistry.t("upgrades.now", [effect_text(up, lvl) if lvl > 0 else DataRegistry.t("ui.none")]))
	if cost >= 0:
		detail_line(DataRegistry.t("upgrades.next", [effect_text(up, lvl + 1)]), "GoodLabel")
		detail_line(DataRegistry.t("upgrades.cost", [UIFormat.coins(cost)]), "CoinLabel")
	else:
		detail_line(DataRegistry.t("upgrades.maxed_text"), "DimLabel")
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_box.add_child(spacer)
	var buy := UIButton.make(DataRegistry.t("upgrades.buy"), func() -> void: _activate(index))
	buy.disabled = not MetaState.can_buy(id)
	detail_box.add_child(buy)
	if cost >= 0 and MetaState.coins < cost:
		detail_line(DataRegistry.t("upgrades.missing", [UIFormat.coins(cost - MetaState.coins)]), "DangerLabel")

func _activate(index: int) -> void:
	var id := ids[index]
	if MetaState.buy(id):
		SaveSystem.save_meta()
		SceneRouter.play_ui("coin")
		UIToast.show(get_tree(), DataRegistry.t("upgrades.bought", [DataRegistry.get_upgrade(id).nombre, MetaState.upgrade_level(id)]), "good")
		show_coins(MetaState.coins)
		rebuild()
	else:
		SceneRouter.play_ui("error")
		var reason := DataRegistry.t("upgrades.maxed_text") if MetaState.upgrade_cost(id) < 0 else DataRegistry.t("upgrades.not_enough")
		UIToast.show(get_tree(), reason, "danger")
