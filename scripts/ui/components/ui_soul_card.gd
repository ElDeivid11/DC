class_name UISoulCard
extends PanelContainer
## Tarjeta de alma (placa con filete azul): llama de alma + nombre de la activa + placa de rango,
## especie de origen, activa con su daño, pasiva (o "sin pasiva") con su
## efecto mecánico, y modificadores de stats.

var soul: Dictionary = {}
var _box: VBoxContainer

func _init(p_soul: Dictionary = {}, compact := false) -> void:
	theme_type_variation = "CardSoul"
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", UIStyle.SPACE)
	add_child(_box)
	if not p_soul.is_empty():
		set_soul(p_soul, compact)

func set_soul(p_soul: Dictionary, compact := false) -> void:
	soul = p_soul
	for c in _box.get_children():
		c.queue_free()

	var active: Dictionary = soul.get("active", {})
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_box.add_child(header)
	header.add_child(UISprite.new("soul_full"))
	var title := Label.new()
	title.theme_type_variation = "HeadLabel"
	title.add_theme_color_override("font_color", UIStyle.SOUL)
	title.text = String(active.get("name", "???"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(UIRankBadge.new(int(soul.get("source_rank", 10))))

	if soul.has("source_species"):
		_add_line(DataRegistry.t("soul.from", [soul.source_species]), "DetailLabel")

	_add_line(DataRegistry.t("soul.active", [active.get("name", "???"), int(active.get("damage", 0))]), "")

	var passive: Variant = soul.get("passive")
	if passive == null:
		_add_line(DataRegistry.t("soul.no_passive"), "DimLabel")
	else:
		var p: Dictionary = passive
		var txt := DataRegistry.t("soul.passive", [p.name, SoulEffects.effect_hint(p.get("effect", {}))])
		if not compact:
			txt += "\n" + String(p.get("description", ""))
		_add_line(txt, "AccentLabel")

	var mods := SoulEffects.modifiers_text(soul.get("stat_modifiers", {}))
	if mods != "":
		_add_line(DataRegistry.t("soul.modifiers", [mods]), "GoodLabel")

func _add_line(text: String, variation: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != "":
		l.theme_type_variation = variation
	_box.add_child(l)
