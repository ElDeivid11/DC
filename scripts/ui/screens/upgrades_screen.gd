class_name UpgradesScreen
extends ListDetailScreen
## Mejoras de meta compradas con monedas, con TOPE por mejora (data/upgrades.json).
## Fila: [ícono] nombre · pips de nivel · costo. Comprar es instantáneo y se
## autoguarda.

## Ícono de cada mejora (game-icons.net, ver tools/ui/src/icons.json).
const ICONS := {
	"vitalidad": "stat_vit", "fuerza": "stat_atq", "botin": "monedas",
	"provisiones": "objeto", "sabiduria": "almas",
}

var ids: Array[String] = []

func _init() -> void:
	super(DataRegistry.t("upgrades.title"))

func _ready() -> void:
	ids.assign(DataRegistry.upgrades.keys())
	ids.sort_custom(func(a: String, b: String) -> bool: return int(DataRegistry.get_upgrade(a).coste_base) < int(DataRegistry.get_upgrade(b).coste_base))
	super._ready()
	show_coins(MetaState.coins)
	add_footer_button(DataRegistry.t("ui.back"), close)

## Ícono de la mejora en una rampa que exista (las de stats no tienen moneda).
static func icon_for(id: String) -> String:
	return String(ICONS.get(id, "mejoras"))

static func effect_text(up: Dictionary, levels: int) -> String:
	var e: Dictionary = up.efecto
	return DataRegistry.t("upgrade.effect." + String(e.tipo), [roundi(float(e.valor) * levels)])

func _fill_list() -> void:
	for id in ids:
		var up := DataRegistry.get_upgrade(id)
		var lvl := MetaState.upgrade_level(id)
		var cost := MetaState.upgrade_cost(id)
		var price: Control
		if cost >= 0:
			price = coin_cost(cost, MetaState.coins >= cost)
		else:
			price = col(DataRegistry.t("upgrades.maxed"), "DimLabel", 94)
		var icon := icon_for(id)
		add_row(String(up.nombre), [UIPips.new(lvl, int(up.max_nivel)), price], false, icon if UIIcon.texture_for(icon, "bronce") else "mejoras")

func _show_detail(index: int) -> void:
	var id := ids[index]
	var up := DataRegistry.get_upgrade(id)
	var lvl := MetaState.upgrade_level(id)
	var max_lvl := int(up.max_nivel)
	var cost := MetaState.upgrade_cost(id)
	var icon := icon_for(id)
	var info := detail_header(String(up.nombre), null, icon if UIIcon.texture_for(icon, "vela") else "mejoras")
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 12)
	info.add_child(level_row)
	level_row.add_child(UIPips.new(lvl, max_lvl))
	var lvl_label := UILabel.make(DataRegistry.t("upgrades.level_num", [lvl, max_lvl]).to_upper(), "NumSmallLabel")
	lvl_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_row.add_child(lvl_label)
	detail_line(String(up.descripcion))
	detail_line(DataRegistry.t("upgrades.now", [effect_text(up, lvl) if lvl > 0 else DataRegistry.t("ui.none")]))
	if cost >= 0:
		detail_line(DataRegistry.t("upgrades.next", [effect_text(up, lvl + 1)]), "GoodLabel")
	else:
		detail_line(DataRegistry.t("upgrades.maxed_text"), "DimLabel")
	detail_line(DataRegistry.t("upgrades.at_max", [effect_text(up, max_lvl)]), "DetailLabel")
	detail_spacer()
	if cost >= 0 and MetaState.coins < cost:
		detail_line(DataRegistry.t("upgrades.missing", [UIFormat.coins(cost - MetaState.coins)]), "DangerLabel")
	var label := DataRegistry.t("upgrades.buy_cost", [UIFormat.number(cost)]) if cost >= 0 else DataRegistry.t("upgrades.maxed")
	var buy := UIButton.make(label, func() -> void: _activate(index))
	if cost >= 0:
		buy.icon = UIIcon.texture_for("monedas", "moneda")
	buy.disabled = not MetaState.can_buy(id)
	detail_box.add_child(buy)

func _activate(index: int) -> void:
	var id := ids[index]
	if MetaState.buy(id):
		SaveSystem.save_meta()
		SceneRouter.play_ui("coin")
		UIToast.show(get_tree(), DataRegistry.t("upgrades.bought", [DataRegistry.get_upgrade(id).nombre, MetaState.upgrade_level(id)]), "coin")
		show_coins(MetaState.coins)
		rebuild()
	else:
		SceneRouter.play_ui("error")
		var reason := DataRegistry.t("upgrades.maxed_text") if MetaState.upgrade_cost(id) < 0 else DataRegistry.t("upgrades.not_enough")
		UIToast.show(get_tree(), reason, "danger")
