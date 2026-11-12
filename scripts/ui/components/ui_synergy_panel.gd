class_name UISynergyPanel
extends VBoxContainer
## Sinergias del héroe (Estado → Almas):
##   AFINIDADES
##   [ícono] Acero ·········· ●●○○
##      I · Afilado (+1 de daño en cada golpe)          ← alcanzado: en color
##      II · Maestro de armas (…)                       ← sin alcanzar: apagado
##   [ícono] Fortuna ········ ○○○                        ← sin almas: solo la fila
##   PACTOS
##   [pacto] Hemorragia (las activas aplican +100% de sangrado)
##   [pacto] Lluvia de acero · falta Lluvia de Huesos (Nigromante)
## Todas las afinidades a la vista (las que no lleva, apagadas): así se ve
## qué falta para el próximo nivel.

func _init(souls: Array) -> void:
	add_theme_constant_override("separation", UIStyle.SPACE)
	var counts := SoulBuild.affinity_counts(souls)
	add_child(UILabel.make(DataRegistry.t("synergy.affinities"), "HeadLabel"))
	add_child(UIDivider.new(240))
	for id in DataRegistry.affinity_ids():
		_affinity(id, int(counts.get(id, 0)))
	add_child(UILabel.make(DataRegistry.t("synergy.pacts"), "HeadLabel"))
	add_child(UIDivider.new(240))
	var any := false
	for pid in SoulBuild.active_pacts(souls):
		var p := DataRegistry.get_pact(pid)
		_row(UIIcon.make("pacto", "alma"), DataRegistry.t("synergy.pact_active", [p.nombre, SoulEffects.effects_text(p.efectos)]), UIStyle.SOUL_LIGHT)
		any = true
	for part: Dictionary in SoulBuild.partial_pacts(souls):
		var p := DataRegistry.get_pact(String(part.id))
		var o := DataRegistry.get_soul(String(part.missing))
		var o_species := String(DataRegistry.get_species(String(o.get("species", ""))).get("display_name", ""))
		_row(UIIcon.make("pacto", "apagado"), DataRegistry.t("synergy.pact_missing", [p.nombre, (o.get("active", {}) as Dictionary).get("name", ""), o_species]), UIStyle.TEXT_DIM)
		any = true
	if not any:
		add_child(UILabel.make(DataRegistry.t("synergy.no_pacts"), "DimLabel", true))

func _affinity(id: String, count: int) -> void:
	var af := DataRegistry.get_affinity(id)
	var levels: Array = af.get("niveles", [])
	var top := int((levels[levels.size() - 1] as Dictionary).cantidad) if not levels.is_empty() else 1
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	add_child(head)
	head.add_child(UIIcon.make(String(af.icono), String(af.rampa) if count > 0 else "apagado"))
	var l := UILabel.make(String(af.nombre), "SubtitleLabel")
	l.add_theme_color_override("font_color", UIStyle.ramp_color(String(af.rampa)) if count > 0 else UIStyle.TEXT_OFF)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(l)
	head.add_child(UIPips.new(mini(count, top), top))
	UITooltip.attach(head, String(af.descripcion))
	# Sin almas de esta afinidad: solo su fila (los niveles, en el tooltip).
	if count == 0:
		var first := int((levels[0] as Dictionary).cantidad) if not levels.is_empty() else 0
		UITooltip.attach(head, "%s\n%s" % [af.descripcion, DataRegistry.t("synergy.no_affinity", [af.nombre, first])])
		return
	var tier := SoulBuild.tier_reached(id, count)
	for i in levels.size():
		var lv: Dictionary = levels[i]
		var line := UILabel.make(DataRegistry.t("synergy.tier_line", [UIFormat.roman(i + 1), int(lv.cantidad), lv.nombre, SoulEffects.effects_text(lv.efectos)]), "DetailLabel", true)
		line.add_theme_color_override("font_color", UIStyle.ramp_color(String(af.rampa)) if i < tier else UIStyle.TEXT_OFF)
		var indent := MarginContainer.new()
		indent.add_theme_constant_override("margin_left", UIStyle.ICON_SIZE + UIStyle.SPACE * 2)
		indent.add_child(line)
		add_child(indent)

func _row(icon: Control, text: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	row.add_child(icon)
	var l := UILabel.make(text, "DetailLabel", true)
	l.add_theme_color_override("font_color", color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	add_child(row)
