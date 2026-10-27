class_name UISoulCard
extends PanelContainer
## Tarjeta de alma (placa con filete azul):
##   [llama] Nombre de la activa ........................ [rango]
##   [afinidad] Acero  [afinidad] Sangre
##   De: Esqueleto esbirro
##   Activa: 7 de daño y 3 de sangrado · Recarga: cada 2 turnos
##   Pasiva: Tablas de Pino (+20% de bloqueo al Defender)
##   Modificadores: ATK +1
##   Pacto: Hemorragia, con Flecha Envenenada (Esqueleto arquero)
## Con un CombatCore armado con las almas del héroe (y el índice de esta) las
## cifras son las reales de ese héroe; sin él, en % del poder. Los pactos
## completos se pintan de azul.

var soul: Dictionary = {}
var _box: VBoxContainer

func _init(p_soul: Dictionary = {}, compact := false, core: CombatCore = null, index := -1) -> void:
	theme_type_variation = "CardSoul"
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", UIStyle.SPACE)
	add_child(_box)
	if not p_soul.is_empty():
		set_soul(p_soul, compact, core, index)

func set_soul(p_soul: Dictionary, compact := false, core: CombatCore = null, index := -1) -> void:
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
	if soul.has("source_rank"):
		header.add_child(UIRankBadge.new(int(soul.source_rank)))

	_box.add_child(affinity_chips(soul.get("afinidades", [])))
	if soul.has("source_species"):
		_add_line(DataRegistry.t("soul.from", [soul.source_species]), "DetailLabel")

	var act := DataRegistry.t("soul.active", [SoulEffects.active_text(active, core, index), SoulEffects.recharge_text(active, core, index)])
	_add_line(act, "")

	var passive: Variant = soul.get("passive")
	if passive == null:
		if not compact:
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

	if compact:
		return
	var have := {}
	if core != null:
		for s: Dictionary in core.hero.get("souls", []):
			have[String(s.get("id", ""))] = true
	var sid := String(soul.get("id", ""))
	for pid in SoulBuild.pacts_with(sid):
		var pact := DataRegistry.get_pact(pid)
		var pair: Array = pact.almas
		var other := String(pair[1] if String(pair[0]) == sid else pair[0])
		var o := DataRegistry.get_soul(other)
		var o_species := String(DataRegistry.get_species(String(o.get("species", ""))).get("display_name", ""))
		var l := _add_line(DataRegistry.t("soul.pact", [pact.nombre, (o.get("active", {}) as Dictionary).get("name", other), o_species, SoulEffects.effects_text(pact.efectos)]), "")
		l.add_theme_color_override("font_color", UIStyle.SOUL_LIGHT if have.has(other) and have.has(sid) else UIStyle.TEXT_DIM)

## Fila de afinidades: [ícono] Nombre por cada una, en su color.
static func affinity_chips(ids: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for a: Variant in ids:
		var af := DataRegistry.get_affinity(String(a))
		if af.is_empty():
			continue
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 2)
		chip.add_child(UIIcon.make(String(af.icono), String(af.rampa)))
		var l := UILabel.make(String(af.nombre), "DetailLabel")
		l.add_theme_color_override("font_color", UIStyle.ramp_color(String(af.rampa)))
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_child(l)
		row.add_child(chip)
	return row

func _add_line(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != "":
		l.theme_type_variation = variation
	_box.add_child(l)
	return l
