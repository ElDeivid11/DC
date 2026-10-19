extends CanvasLayer
## Menú de estado del equipo: se abre/cierra con Tab durante la exploración
## (ver Main._unhandled_input). Muestra, por personaje, stats efectivas vs.
## base y el detalle de cada alma equipada (activa, pasiva, modificadores) —
## así se puede revisar el resultado del sistema de almas sin tener que estar
## en combate para verlo.

signal close_requested

var is_open := false
var content_vbox: VBoxContainer

func _ready() -> void:
	visible = false

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 420)
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Estado del equipo"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	content_vbox = VBoxContainer.new()
	vbox.add_child(content_vbox)

	var close_btn := Button.new()
	close_btn.text = "Cerrar (Tab)"
	close_btn.pressed.connect(func(): close_requested.emit())
	vbox.add_child(close_btn)

func set_open(open: bool) -> void:
	is_open = open
	visible = open

## Reconstruye el contenido a partir del roster persistente de Main.gd —
## se llama cada vez que se abre, así siempre refleja el estado actual
## (almas recién recogidas, etc.), no una foto vieja.
func refresh(party_roster: Array) -> void:
	for child in content_vbox.get_children():
		child.queue_free()

	for member in party_roster:
		var eff_hp: int = member.base_hp
		var eff_atk: int = member.base_atk
		for soul in member.souls:
			var mods: Dictionary = soul.get("stat_modifiers", {})
			eff_hp += int(mods.get("hp", 0)) + int(mods.get("max_hp", 0))
			eff_atk += int(mods.get("atk", 0))

		var name_lbl := Label.new()
		name_lbl.text = "%s — HP %d (base %d)   ATK %d (base %d)" % [
			member.name, eff_hp, member.base_hp, eff_atk, member.base_atk
		]
		content_vbox.add_child(name_lbl)

		if member.souls.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "   Sin alma equipada"
			content_vbox.add_child(empty_lbl)
		else:
			for soul in member.souls:
				content_vbox.add_child(_make_soul_label(soul))

		content_vbox.add_child(HSeparator.new())

func _make_soul_label(soul: Dictionary) -> Label:
	var species_txt: String = soul.get("source_species", "???")
	var rank_txt: int = soul.get("source_rank", 0)
	var active: Dictionary = soul.get("active", {})
	var active_name: String = active.get("name", "???")
	var active_dmg: int = active.get("damage", 0)
	var passive: Variant = soul.get("passive")
	var passive_txt: String = "sin pasiva" if passive == null else passive.name
	var mods: Dictionary = soul.get("stat_modifiers", {})
	var mods_txt := ""
	for k in mods.keys():
		mods_txt += " %s +%s" % [k, str(mods[k])]
	if mods_txt == "":
		mods_txt = " ninguno"

	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.text = "   Alma rango %d (%s) — Activa: %s (%d dmg) | Pasiva: %s | Modificadores:%s" % [
		rank_txt, species_txt, active_name, active_dmg, passive_txt, mods_txt
	]
	return lbl
