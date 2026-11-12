class_name UISynergyDiff
extends VBoxContainer
## Qué cambia en las sinergias al tomar (o cambiar) un alma, una nota por
## línea (SoulBuild.diff_if_added):
##   [afinidad] Activa Acero II · Afilado (+1 de daño en cada golpe)
##   [pacto]    Pacto: Hemorragia (…)
##   [afinidad] Pierdes Hueso I · Armazón            (en rojo)
## Si no cambia nada y se pasa el alma nueva, cuenta cómo quedan sus
## afinidades («Acero 1/2 · Sangre 2/4»).

var _width := 440
## Breve: solo los nombres (sin los efectos), para columnas angostas.
var _brief := false

func _init(diff: Dictionary, soul_id := "", souls: Array = [], width := 440, brief := false) -> void:
	_width = width
	_brief = brief
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for g: Dictionary in diff.get("tiers", []):
		_tier_line(String(g.id), int(g.tier), true)
	for id: Variant in diff.get("pacts", []):
		var p := DataRegistry.get_pact(String(id))
		_line(UIIcon.make("pacto", "alma"), DataRegistry.t("synergy.pact_new_brief", [p.nombre]) if _brief else DataRegistry.t("synergy.pact_new", [p.nombre, SoulEffects.effects_text(p.efectos)]), UIStyle.SOUL_LIGHT)
	for g: Dictionary in diff.get("lost", []):
		_tier_line(String(g.id), int(g.tier), false)
	for id: Variant in diff.get("pacts_lost", []):
		var p := DataRegistry.get_pact(String(id))
		_line(UIIcon.make("pacto", "apagado"), DataRegistry.t("synergy.pact_lost", [p.nombre]), UIStyle.DANGER)
	if get_child_count() == 0 and soul_id != "":
		_progress(soul_id, souls)

func _tier_line(af_id: String, tier: int, gained: bool) -> void:
	var af := DataRegistry.get_affinity(af_id)
	var levels: Array = af.get("niveles", [])
	if tier < 1 or tier > levels.size():
		return
	var lv: Dictionary = levels[tier - 1]
	var tier_name := "%s %s" % [af.nombre, UIFormat.roman(tier)]
	if gained:
		var fx := "" if _brief else SoulEffects.effects_text(lv.efectos)
		_line(UIIcon.make(String(af.icono), String(af.rampa)), DataRegistry.t("synergy.tier_new", [tier_name, lv.nombre, fx]).strip_edges(), UIStyle.ramp_color(String(af.rampa)))
	else:
		_line(UIIcon.make(String(af.icono), "apagado"), DataRegistry.t("synergy.tier_lost", [tier_name, lv.nombre]), UIStyle.DANGER)

## Afinidades del alma nueva: cuántas quedarían y cuántas pide el próximo nivel.
func _progress(soul_id: String, souls: Array) -> void:
	var counts := SoulBuild.affinity_counts(souls)
	var parts: Array[String] = []
	for a: Variant in DataRegistry.get_soul(soul_id).get("afinidades", []):
		var af := DataRegistry.get_affinity(String(a))
		var n := int(counts.get(String(a), 0)) + 1
		var next := 0
		for lv: Dictionary in af.get("niveles", []):
			if n < int(lv.cantidad):
				next = int(lv.cantidad)
				break
		parts.append(DataRegistry.t("synergy.count", [af.nombre, n, next]) if next > 0 else DataRegistry.t("synergy.count_full", [af.nombre, n]))
	if not parts.is_empty():
		_line(UIIcon.make("almas", "alma"), DataRegistry.t("synergy.after", [" · ".join(parts)]), UIStyle.TEXT_DIM)

func _line(icon: Control, text: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(icon)
	var l := UILabel.make(text, "DetailLabel", true)
	l.add_theme_color_override("font_color", color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.custom_minimum_size.x = _width
	row.add_child(l)
	add_child(row)
