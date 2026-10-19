extends CanvasLayer
## Combate por turnos mínimo — vista en primera persona estática (opción elegida):
## la cámara de exploración se queda congelada donde estaba (ver GridPlayer.input_locked),
## y todo el combate se resuelve en un panel de UI encima, sin cambiar de escena.
##
## Control total del equipo: cada miembro actúa en su propio turno, y solo ve
## en pantalla las activas de las almas que ÉL/ELLA lleva puestas (las almas
## son por personaje, no del grupo).
##
## Números de prueba SIN CALIBRAR — esto es solo para validar que el flujo de
## turnos (y ahora el de recoger/asignar almas) se sienta bien, no el balance
## real (eso es tarea de la Fase 0 del roadmap).

signal combat_ended(victory: bool, soul_result: Dictionary)

# Configuración que le pasa Main.gd antes de add_child (por eso no son const):
var guarantee_soul := false # true = este combate garantiza la caída de un alma al ganar (solo para testing)
var enemy_data := {"name": "???", "rank": 10, "hp": 10, "atk": 1}
var soul_data := {} # {active:{name,damage}, passive:{name,description} o null, stat_modifiers:{}}
var party_roster: Array = [] # snapshot del roster persistente de Main.gd al iniciar el combate

var party := [] # copia de batalla: hp/atk EFECTIVOS (base + modificadores de almas equipadas)
var enemy := {}

var current_index := 0
var log_lines: Array[String] = []

var party_labels: Array[Label] = []
var enemy_label: Label
var log_label: Label
var action_box: HBoxContainer
var step_box: VBoxContainer # zona dinámica: seguir jugando / decisión de alma / a quién dársela

func _ready() -> void:
	_build_battle_party()
	enemy = {"name": enemy_data.name, "hp": enemy_data.hp, "max_hp": enemy_data.hp, "atk": enemy_data.atk}
	_build_ui()
	_log("¡Combate iniciado contra %s (Rango %d)!" % [enemy.name, enemy_data.rank])
	_start_turn()

## Arma la party de batalla a partir del roster persistente: hp/atk efectivos
## = base + suma de stat_modifiers de todas las almas que ese personaje lleva.
func _build_battle_party() -> void:
	for member in party_roster:
		var eff_hp: int = member.base_hp
		var eff_atk: int = member.base_atk
		for soul in member.souls:
			var mods: Dictionary = soul.get("stat_modifiers", {})
			eff_hp += int(mods.get("hp", 0)) + int(mods.get("max_hp", 0))
			eff_atk += int(mods.get("atk", 0))
		party.append({
			"id": member.id, "name": member.name, "hp": eff_hp, "max_hp": eff_hp,
			"atk": eff_atk, "defending": false, "souls": member.souls,
		})

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 380)
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	enemy_label = Label.new()
	enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(enemy_label)
	vbox.add_child(HSeparator.new())

	var party_title := Label.new()
	party_title.text = "Tu equipo"
	vbox.add_child(party_title)

	for member in party:
		var lbl := Label.new()
		vbox.add_child(lbl)
		party_labels.append(lbl)
	vbox.add_child(HSeparator.new())

	log_label = Label.new()
	log_label.custom_minimum_size = Vector2(0, 90)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(log_label)

	action_box = HBoxContainer.new()
	vbox.add_child(action_box)

	step_box = VBoxContainer.new()
	vbox.add_child(step_box)

	_refresh_ui()

func _refresh_ui() -> void:
	enemy_label.text = "%s (Rango %d) — HP %d/%d" % [enemy.name, enemy_data.rank, max(enemy.hp, 0), enemy.max_hp]
	for i in party.size():
		var m: Dictionary = party[i]
		var marker := "▶ " if i == current_index and m.hp > 0 else "   "
		var status := "" if m.hp > 0 else " (caído)"
		var passive_tags := ""
		for soul in m.souls:
			var passive: Variant = soul.get("passive")
			if passive != null:
				var hint := _passive_effect_hint(passive.get("effect", {}))
				passive_tags += " [pasiva: %s%s]" % [passive.name, hint]
		party_labels[i].text = "%s%s — HP %d/%d%s%s" % [marker, m.name, max(m.hp, 0), m.max_hp, status, passive_tags]

func _log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 5:
		log_lines.pop_front()
	log_label.text = "\n".join(log_lines)

func _alive_party_indices() -> Array:
	var res := []
	for i in party.size():
		if party[i].hp > 0:
			res.append(i)
	return res

func _clear_step_box() -> void:
	for child in step_box.get_children():
		child.queue_free()

## Busca entre las almas de un personaje si alguna pasiva tiene un efecto del
## tipo pedido, y devuelve ese efecto (con el nombre de la pasiva incluido,
## para poder loguearlo). Devuelve {} si no tiene ninguna que aplique.
## Sistema genérico por "tipo de efecto" — sumar un tipo nuevo es agregar un
## caso más donde se usa esta función, sin tocar la estructura de datos.
func _get_passive_effect(member: Dictionary, effect_type: String) -> Dictionary:
	for soul in member.souls:
		var passive: Variant = soul.get("passive")
		if passive == null:
			continue
		var effect: Dictionary = passive.get("effect", {})
		if effect.get("type", "") == effect_type:
			var result: Dictionary = effect.duplicate()
			result["_passive_name"] = passive.name
			return result
	return {}

## Texto corto para mostrar en la UI qué hace mecánicamente una pasiva
## (además de su nombre), para que se pueda verificar a simple vista que el
## efecto real está conectado y no es solo la etiqueta descriptiva.
func _passive_effect_hint(effect: Dictionary) -> String:
	match effect.get("type", ""):
		"damage_reduction_flat":
			return " (-%d daño recibido)" % int(effect.get("value", 0))
		"defend_bonus_multiplier":
			return " (+%d%% bloqueo al Defender)" % int(float(effect.get("value", 0)) * 100)
		"damage_bonus_flat":
			return " (+%d daño en cada golpe)" % int(effect.get("value", 0))
		_:
			return ""

# --- Turnos --------------------------------------------------------------

func _start_turn() -> void:
	var alive := _alive_party_indices()
	if alive.is_empty():
		_finish_combat(false)
		return
	if not alive.has(current_index):
		current_index = alive[0]
	action_box.visible = true
	_refresh_actions()
	_refresh_ui()

## Se reconstruye en CADA turno porque las activas disponibles dependen de
## quién está actuando (solo las almas que ESE personaje lleva puestas).
func _refresh_actions() -> void:
	for child in action_box.get_children():
		child.queue_free()

	var attack_btn := Button.new()
	attack_btn.text = "Atacar"
	attack_btn.pressed.connect(_on_attack_pressed)
	action_box.add_child(attack_btn)

	var defend_btn := Button.new()
	defend_btn.text = "Defender"
	defend_btn.pressed.connect(_on_defend_pressed)
	action_box.add_child(defend_btn)

	for soul in party[current_index].souls:
		var active: Dictionary = soul.get("active", {})
		if active.is_empty():
			continue
		var ab_btn := Button.new()
		ab_btn.text = active.name
		var dmg: int = active.get("damage", 1)
		ab_btn.pressed.connect(func(): _on_ability_pressed(active.name, dmg))
		action_box.add_child(ab_btn)

func _on_attack_pressed() -> void:
	var dmg: int = max(party[current_index].atk + randi_range(-1, 1), 1)
	dmg += _outgoing_damage_bonus(party[current_index])
	enemy.hp -= dmg
	_log("%s ataca por %d de daño." % [party[current_index].name, dmg])
	_refresh_ui()
	if enemy.hp <= 0:
		_finish_combat(true)
		return
	_advance_turn()

func _on_defend_pressed() -> void:
	_log("%s se pone en guardia." % party[current_index].name)
	party[current_index]["defending"] = true
	_advance_turn()

func _on_ability_pressed(ability_name: String, base_dmg: int) -> void:
	var dmg: int = base_dmg + _outgoing_damage_bonus(party[current_index])
	enemy.hp -= dmg
	_log("%s usa %s por %d de daño." % [party[current_index].name, ability_name, dmg])
	_refresh_ui()
	if enemy.hp <= 0:
		_finish_combat(true)
		return
	_advance_turn()

## Pasiva "Puntería Letal" (damage_bonus_flat): suma daño plano extra a
## CUALQUIER golpe que dé ese personaje, sea ataque normal o activa de alma.
func _outgoing_damage_bonus(member: Dictionary) -> int:
	var effect := _get_passive_effect(member, "damage_bonus_flat")
	if effect.is_empty():
		return 0
	return int(effect.value)

func _advance_turn() -> void:
	var alive := _alive_party_indices()
	var pos := alive.find(current_index)
	if pos == -1 or pos == alive.size() - 1:
		_enemy_turn()
	else:
		current_index = alive[pos + 1]
		_start_turn()

func _enemy_turn() -> void:
	action_box.visible = false
	var alive := _alive_party_indices()
	if alive.is_empty():
		_finish_combat(false)
		return
	var target_i: int = alive[randi() % alive.size()]
	var target: Dictionary = party[target_i]
	var dmg: int = enemy.atk + randi_range(-1, 1)

	if target.get("defending", false):
		# Bloqueo base al Defender: 50%. La pasiva "Guardia Inquebrantable"
		# (defend_bonus_multiplier) sube ese porcentaje de bloqueo.
		var defend_effect := _get_passive_effect(target, "defend_bonus_multiplier")
		var block_ratio := 0.5
		if not defend_effect.is_empty():
			block_ratio = clamp(0.5 + float(defend_effect.value), 0.0, 0.9)
		dmg = int(dmg * (1.0 - block_ratio))
		target["defending"] = false

	# Pasiva "Piel Curtida" (damage_reduction_flat): resta daño plano después
	# del bloqueo, sin importar si estaba defendiendo o no.
	var reduction_effect := _get_passive_effect(target, "damage_reduction_flat")
	if not reduction_effect.is_empty():
		var before := dmg
		dmg = max(dmg - int(reduction_effect.value), 0)
		if dmg < before:
			_log("La pasiva %s de %s absorbe parte del golpe." % [reduction_effect._passive_name, target.name])

	dmg = max(dmg, 0) # con pasivas, un golpe SÍ puede quedar en 0 — ya no hay piso de 1 forzado
	target.hp -= dmg
	_log("%s ataca a %s por %d de daño." % [enemy.name, target.name, dmg])
	_refresh_ui()
	if _alive_party_indices().is_empty():
		_finish_combat(false)
		return
	current_index = _alive_party_indices()[0]
	_start_turn()

# --- Fin de combate y flujo de alma ---------------------------------------

func _finish_combat(victory: bool) -> void:
	action_box.visible = false
	if victory:
		_log("¡Victoria!")
	else:
		_log("El equipo cayó derrotado.")
	_show_continue_step()

func _show_continue_step() -> void:
	_clear_step_box()
	var btn := Button.new()
	btn.text = "Continuar"
	btn.pressed.connect(_on_continue_pressed)
	step_box.add_child(btn)

func _on_continue_pressed() -> void:
	var victory: bool = enemy.hp <= 0
	if victory and guarantee_soul:
		_show_soul_offer()
	else:
		combat_ended.emit(victory, {})

## Primer paso del hallazgo: revela el alma y pregunta si se quiere recoger.
## Rechazarla es una opción real (no hay obligación de quedarse con todo).
func _show_soul_offer() -> void:
	_clear_step_box()

	var reveal := Label.new()
	reveal.autowrap_mode = TextServer.AUTOWRAP_WORD
	var passive_txt: String = "sin pasiva" if soul_data.passive == null else ("pasiva: " + str(soul_data.passive.name))
	reveal.text = "✦ ¡Alma de rango %d (%s) obtenida! Activa: %s (%s). ¿La recoges?" % [
		enemy_data.rank, enemy_data.name, soul_data.active.name, passive_txt
	]
	step_box.add_child(reveal)

	var row := HBoxContainer.new()
	step_box.add_child(row)

	var yes_btn := Button.new()
	yes_btn.text = "Sí, recogerla"
	yes_btn.pressed.connect(_show_member_select)
	row.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "No, dejarla"
	no_btn.pressed.connect(func(): combat_ended.emit(true, {}))
	row.add_child(no_btn)

## Segundo paso: a quién del equipo se le da. Las almas son por personaje,
## no del grupo — hay que elegir. Por ahora, capacidad de 1 alma por
## personaje (nivel 1 = 1 alma equipable, según el diseño).
func _show_member_select() -> void:
	_clear_step_box()

	var eligible: Array = party_roster.filter(func(m): return m.souls.is_empty())

	if eligible.is_empty():
		var full_label := Label.new()
		full_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		full_label.text = "Todo tu equipo ya tiene un alma equipada (capacidad de nivel 1). No se puede recoger."
		step_box.add_child(full_label)
		var ok_btn := Button.new()
		ok_btn.text = "Continuar"
		ok_btn.pressed.connect(func(): combat_ended.emit(true, {}))
		step_box.add_child(ok_btn)
		return

	var prompt := Label.new()
	prompt.text = "¿A quién se la das?"
	step_box.add_child(prompt)

	var row := HBoxContainer.new()
	step_box.add_child(row)
	for member in eligible:
		var btn := Button.new()
		btn.text = member.name
		var member_id: String = member.id
		btn.pressed.connect(func():
			combat_ended.emit(true, {"picked_up": true, "member_id": member_id, "soul": soul_data})
		)
		row.add_child(btn)
