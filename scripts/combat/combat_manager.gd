extends CanvasLayer
## Combate por turnos — vista en primera persona estática: la cámara de
## exploración se queda congelada (GridPlayer.input_locked) y todo el combate
## se resuelve en UI encima, sin cambiar de escena.
##
## Control total del equipo: cada miembro actúa en su propio turno y solo ve
## las activas de las almas que ÉL/ELLA lleva puestas (las almas son por
## personaje, no del grupo).
##
## Autocontenido: recibe todo por propiedades ANTES de add_child(), trabaja
## sobre COPIAS (nunca toca GameState) y al terminar reporta por señal:
##   combat_ended(outcome, result)
##     outcome: "victory" | "defeat" | "fled"
##     result:  {hp: {member_id: hp}, items_used: [item_id...],
##               soul_pick: {member_id, soul, replace_index} | {}}
## RunController aplica eso al estado de la run.
##
## Flujo al ganar: resumen post-combate (monedas, bonus de primera kill) →
## [Continuar] → si soltó alma, se REVELA → recogerla (opcional) → a quién →
## si ese personaje está lleno: reemplazar una o descartar la nueva.

signal combat_ended(outcome: String, result: Dictionary)
## Para efectos en el mundo 3D (parpadeo y animaciones del modelo del enemigo).
signal enemy_hit(damage: int)
## El enemigo empieza su acción: "attack" | "ability" (habilidad de jefe).
## El daño llega combat.enemy_attack_windup segundos después (el golpe de la
## animación).
signal enemy_acting(action: String)
## El enemigo llegó a 0 HP (antes del resumen de victoria).
signal enemy_defeated

# --- Configuración (la pasa RunController antes de add_child) ---------------------
## {name, rank, hp, atk, ability_damage, ability_name, kind, species_id}
var enemy_data := {"name": "???", "rank": 10, "hp": 10, "atk": 1, "ability_damage": 1, "ability_name": "", "kind": "normal", "species_id": ""}
## Copia del equipo: [{id, name, hp, max_hp, atk, souls, soul_capacity}]
var party_roster: Array = []
## Copia del inventario (ids); se usan solo los que sirven en combate.
var inventory: Array[String] = []
## "surprise" (tú chocaste: turno gratis ×1.5) | "ambush" (te alcanzaron por
## la espalda/costado: el enemigo pega primero ×1.5) | "normal"
var start_mode := "normal"
var flee_chance := 0.5
## Alma ya sorteada al empezar ({} = no suelta nada). Se revela al ganar.
var soul_drop: Dictionary = {}
## Para el resumen post-combate: {coins, first_kill, first_kill_bonus}
var reward_preview := {"coins": 0, "first_kill": false, "first_kill_bonus": 0}
var god_mode := false
var one_hit := false
var rng: RandomNumberGenerator = null

# --- Estado ---------------------------------------------------------------------------
var party: Array = []
var enemy := {}
var current_index := 0
var round_n := 1
var enemy_turns := 0
var surprise_round := false
var ambush_pending := false
var busy := false
var finished := false
var items_used: Array[String] = []
var log_lines: Array[String] = []

# --- UI -------------------------------------------------------------------------------
var root: Control
var enemy_name_label: Label
var enemy_bar: UIStatBar
var enemy_badge: UIRankBadge
var enemy_panel: PanelContainer
var queue_label: Label
var member_cards: Array[UIPanel] = []
var member_bars: Array[UIStatBar] = []
var member_status: Array[Label] = []
var log_label: Label
var menu_panel: UIPanel
var menu_box: VBoxContainer
var float_layer: Control
var summary_panel: UIPanel

func _ready() -> void:
	layer = 10
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	_build_party()
	enemy = {
		"name": enemy_data.name, "hp": int(enemy_data.hp), "max_hp": int(enemy_data.hp),
		"atk": int(enemy_data.atk), "kind": String(enemy_data.kind),
	}
	_build_ui()
	var kind_txt := ""
	if enemy.kind == RunRules.BOSS:
		kind_txt = DataRegistry.t("combat.boss_intro")
	_log(DataRegistry.t("combat.start", [enemy.name, int(enemy_data.rank)]) + kind_txt)
	match start_mode:
		"surprise":
			surprise_round = true
			_log(DataRegistry.t("combat.surprise"))
		"ambush":
			ambush_pending = true
			_log(DataRegistry.t("combat.ambush"))
	_refresh_ui()
	if ambush_pending:
		_enemy_turn()
	else:
		_start_turn()

func _build_party() -> void:
	for m: Dictionary in party_roster:
		party.append({
			"id": m.id, "name": m.name, "hp": int(m.hp), "max_hp": int(m.max_hp),
			"atk": int(m.atk), "defending": false, "souls": m.souls,
			"soul_capacity": int(m.get("soul_capacity", 1)),
		})

func _bal(path: String, default: float) -> float:
	return DataRegistry.bal_f("combat." + path, default)

# --- UI ---------------------------------------------------------------------------------

func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UIStyle.MARGIN_SCREEN)
	root.add_child(margin)
	var layout := VBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(layout)

	# Arriba: enemigo (izq.) y cola de turnos (der.)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(top)
	enemy_panel = PanelContainer.new()
	enemy_panel.theme_type_variation = "HudPanel"
	enemy_panel.custom_minimum_size.x = 380
	top.add_child(enemy_panel)
	var ebox := VBoxContainer.new()
	enemy_panel.add_child(ebox)
	var ehead := HBoxContainer.new()
	ebox.add_child(ehead)
	enemy_name_label = Label.new()
	enemy_name_label.theme_type_variation = "DangerLabel" if String(enemy_data.kind) == RunRules.BOSS else "SubtitleLabel"
	enemy_name_label.add_theme_font_size_override("font_size", UIStyle.FONT_SUBTITLE)
	enemy_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ehead.add_child(enemy_name_label)
	enemy_badge = UIRankBadge.new(int(enemy_data.rank))
	ehead.add_child(enemy_badge)
	enemy_bar = UIStatBar.new("", "hp", 260)
	ebox.add_child(enemy_bar)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	var qpanel := PanelContainer.new()
	qpanel.theme_type_variation = "HudPanel"
	qpanel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(qpanel)
	queue_label = Label.new()
	queue_label.theme_type_variation = "DimLabel"
	qpanel.add_child(queue_label)

	var mid := Control.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(mid)

	# Abajo: equipo | registro | acciones
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	layout.add_child(bottom)
	var party_col := VBoxContainer.new()
	party_col.custom_minimum_size.x = 330
	party_col.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(party_col)
	for m: Dictionary in party:
		var card := UIPanel.new("", "HudPanel")
		party_col.add_child(card)
		var head := HBoxContainer.new()
		card.body.add_child(head)
		var bar := UIStatBar.new(String(m.name), "hp", 140)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(bar)
		var st := Label.new()
		st.theme_type_variation = "DetailLabel"
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.body.add_child(st)
		member_cards.append(card)
		member_bars.append(bar)
		member_status.append(st)

	# Registro compacto abajo al centro: deja ver al enemigo.
	var log_panel := PanelContainer.new()
	log_panel.theme_type_variation = "HudPanel"
	log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(log_panel)
	log_label = Label.new()
	log_label.theme_type_variation = "DetailLabel"
	log_label.add_theme_color_override("font_color", UIStyle.TEXT)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	log_label.custom_minimum_size.y = 84
	log_panel.add_child(log_label)

	menu_panel = UIPanel.new(DataRegistry.t("combat.actions"), "HudPanel")
	menu_panel.custom_minimum_size.x = 240
	menu_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(menu_panel)
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", UIStyle.SPACE)
	menu_panel.body.add_child(menu_box)

	float_layer = Control.new()
	float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(float_layer)

func _refresh_ui() -> void:
	enemy_name_label.text = String(enemy.name)
	enemy_bar.animate_to(int(enemy.hp), int(enemy.max_hp))
	for i in party.size():
		var m: Dictionary = party[i]
		member_bars[i].animate_to(int(m.hp), int(m.max_hp))
		var acting: bool = i == current_index and int(m.hp) > 0 and not busy and not finished
		member_bars[i].set_name_text(("▶ " if acting else "") + String(m.name))
		member_status[i].text = _member_status_text(m)
		member_cards[i].modulate = Color(1, 1, 1, 0.45) if int(m.hp) <= 0 else Color.WHITE
	queue_label.text = DataRegistry.t("combat.queue", [_queue_text()])

func _member_status_text(m: Dictionary) -> String:
	if int(m.hp) <= 0:
		return DataRegistry.t("combat.fallen")
	var parts: Array[String] = []
	var souls: Array = m.souls
	if souls.is_empty():
		parts.append(DataRegistry.t("combat.no_soul"))
	for soul: Dictionary in souls:
		var passive: Variant = soul.get("passive")
		var txt := "%s %s" % [UIStyle.SOUL_SYMBOL, soul.active.name]
		if passive != null:
			txt += " · " + String((passive as Dictionary).name)
		parts.append(txt)
	if m.get("defending", false):
		parts.append(DataRegistry.t("combat.defending"))
	return "\n".join(parts)

func _queue_text() -> String:
	var names: Array[String] = []
	var alive := _alive_party_indices()
	var start := alive.find(current_index)
	if start == -1:
		start = 0
	for k in alive.size():
		var idx: int = alive[(start + k) % alive.size()]
		names.append(String(party[idx].name))
	names.append(String(enemy.name))
	return " › ".join(names)

func _log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 4:
		log_lines.pop_front()
	if log_label:
		log_label.text = "\n".join(log_lines)

## Número flotante que sube y se desvanece (daño, curación, crítico).
func _float_number(text: String, at: Vector2, variation: String, big := false) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", UIStyle.FONT_TITLE if big else UIStyle.FONT_SUBTITLE)
	l.position = at
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	float_layer.add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", at.y - 48.0, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)

func _enemy_float_pos() -> Vector2:
	var vp := root.get_viewport_rect().size
	return Vector2(vp.x * 0.5 - 16.0 + rng.randf_range(-30.0, 30.0), vp.y * 0.38)

func _member_float_pos(i: int) -> Vector2:
	var r := member_cards[i].get_global_rect()
	return Vector2(r.position.x + r.size.x * 0.6, r.position.y - 8.0)

func _flash(control: Control, color: Color) -> void:
	var tw := control.create_tween()
	tw.tween_property(control, "modulate", color, 0.06)
	tw.tween_property(control, "modulate", Color.WHITE, 0.18)

# --- Menús de acción ---------------------------------------------------------------------

## items: [[texto, callable, deshabilitado?, tooltip?], ...]
func _show_menu(title: String, items: Array, with_back := false) -> void:
	menu_panel.set_title(title)
	for c in menu_box.get_children():
		c.queue_free()
	var buttons: Array = []
	for it: Array in items:
		var b := UIButton.make(String(it[0]), it[1])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = it.size() > 2 and bool(it[2])
		if it.size() > 3:
			UITooltip.attach(b, String(it[3]))
		menu_box.add_child(b)
		buttons.append(b)
	if with_back:
		var back := UIButton.make(DataRegistry.t("ui.back"), _show_actions)
		back.alignment = HORIZONTAL_ALIGNMENT_LEFT
		menu_box.add_child(back)
		buttons.append(back)
	UIFocus.chain_vertical(buttons)
	UIFocus.grab_first(menu_box)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not busy and not finished and menu_panel.title_label.text != DataRegistry.t("combat.actions"):
		get_viewport().set_input_as_handled()
		_show_actions()

func _show_actions() -> void:
	if finished or busy:
		return
	var m: Dictionary = party[current_index]
	var has_abilities := not (m.souls as Array).is_empty()
	var usable := _combat_items()
	var is_boss: bool = enemy.kind == RunRules.BOSS
	_show_menu(DataRegistry.t("combat.actions"), [
		[DataRegistry.t("combat.attack"), _on_attack],
		[DataRegistry.t("combat.ability"), _show_abilities, not has_abilities, "" if has_abilities else DataRegistry.t("combat.ability_none")],
		[DataRegistry.t("combat.defend"), _on_defend, false, DataRegistry.t("combat.defend_tip")],
		[DataRegistry.t("combat.item"), _show_items, usable.is_empty(), "" if not usable.is_empty() else DataRegistry.t("combat.item_none")],
		[DataRegistry.t("combat.flee_pct", [UIFormat.pct(flee_chance)]) if not is_boss else DataRegistry.t("combat.flee"), _on_flee, is_boss, DataRegistry.t("combat.flee_boss") if is_boss else DataRegistry.t("combat.flee_tip")],
	])

func _show_abilities() -> void:
	var m: Dictionary = party[current_index]
	var items: Array = []
	for soul: Dictionary in m.souls:
		var active: Dictionary = soul.get("active", {})
		var dmg := int(active.get("damage", 1))
		var aname := String(active.get("name", "?"))
		items.append([DataRegistry.t("combat.ability_entry", [aname, dmg]), func() -> void: _on_ability(aname, dmg)])
	_show_menu(DataRegistry.t("combat.ability"), items, true)

func _combat_items() -> Array[int]:
	var out: Array[int] = []
	for i in inventory.size():
		var it := DataRegistry.get_item(inventory[i])
		if it.is_empty() or not bool(it.efecto.en_combate):
			continue
		out.append(i)
	return out

func _show_items() -> void:
	var items: Array = []
	for i in _combat_items():
		var it := DataRegistry.get_item(inventory[i])
		var idx := i
		var disabled: bool = it.efecto.tipo == "huida_garantizada" and enemy.kind == RunRules.BOSS
		items.append([String(it.nombre), func() -> void: _on_item(idx), disabled, String(it.descripcion)])
	_show_menu(DataRegistry.t("combat.item"), items, true)

# --- Turnos --------------------------------------------------------------------------------

func _alive_party_indices() -> Array[int]:
	var res: Array[int] = []
	for i in party.size():
		if int(party[i].hp) > 0:
			res.append(i)
	return res

func _start_turn() -> void:
	if finished:
		return
	var alive := _alive_party_indices()
	if alive.is_empty():
		_finish(false)
		return
	if not alive.has(current_index):
		current_index = alive[0]
	party[current_index]["defending"] = false
	busy = false
	_refresh_ui()
	_show_actions()

func _end_member_turn() -> void:
	busy = true
	_refresh_ui()
	if int(enemy.hp) <= 0:
		_finish(true)
		return
	var alive := _alive_party_indices()
	var pos := alive.find(current_index)
	if pos == -1 or pos == alive.size() - 1:
		if surprise_round and DataRegistry.bal("combat.surprise_free_turn", true):
			# Ataque sorpresa: el enemigo pierde su primer turno.
			surprise_round = false
			round_n += 1
			_log(DataRegistry.t("combat.enemy_stunned", [enemy.name]))
			current_index = alive[0]
			await get_tree().create_timer(_bal("enemy_turn_delay", 0.35)).timeout
			_start_turn()
			return
		surprise_round = false
		await get_tree().create_timer(_bal("enemy_turn_delay", 0.35)).timeout
		_enemy_turn()
	else:
		current_index = alive[pos + 1]
		_start_turn()

## Daño que hace un personaje: base + pasivas (bonus plano, crítico) y el
## ×1.5 de la ronda sorpresa. Devuelve [daño, fue_crítico].
func _outgoing(member: Dictionary, base: int) -> Array:
	var dmg := base + int(SoulEffects.total(member, "damage_bonus_flat"))
	if surprise_round:
		dmg = roundi(dmg * _bal("surprise_damage_mult", 1.5))
	var crit := rng.randf() < SoulEffects.total(member, "crit_chance")
	if crit:
		dmg = roundi(dmg * _bal("crit_mult", 2.0))
	if one_hit:
		dmg = maxi(dmg, int(enemy.hp))
	return [maxi(dmg, 1), crit]

func _hit_enemy(member: Dictionary, dmg: int, crit: bool) -> void:
	enemy["hp"] = int(enemy.hp) - dmg
	enemy_hit.emit(dmg)
	_flash(enemy_panel, UIStyle.DANGER)
	_float_number(("%d!" if crit else "%d") % dmg, _enemy_float_pos(), "AccentLabel", crit)
	# Pasiva de robo de vida: cura una parte del daño hecho.
	var steal := SoulEffects.total(member, "lifesteal_pct")
	if steal > 0.0 and int(member.hp) > 0:
		var heal := mini(roundi(dmg * steal), int(member.max_hp) - int(member.hp))
		if heal > 0:
			member["hp"] = int(member.hp) + heal
			_float_number("+%d" % heal, _member_float_pos(party.find(member)), "GoodLabel")
	SceneRouter.play_ui("click")

func _on_attack() -> void:
	if busy:
		return
	var m: Dictionary = party[current_index]
	var variance := int(_bal("damage_variance", 1))
	var r := _outgoing(m, maxi(int(m.atk) + rng.randi_range(-variance, variance), 1))
	_hit_enemy(m, r[0], r[1])
	_log(DataRegistry.t("combat.log_attack_crit" if r[1] else "combat.log_attack", [m.name, r[0]]))
	_end_member_turn()

func _on_ability(ability_name: String, base_dmg: int) -> void:
	if busy:
		return
	var m: Dictionary = party[current_index]
	var r := _outgoing(m, base_dmg)
	_hit_enemy(m, r[0], r[1])
	_log(DataRegistry.t("combat.log_ability", [m.name, ability_name, r[0]]))
	_end_member_turn()

func _on_defend() -> void:
	if busy:
		return
	var m: Dictionary = party[current_index]
	m["defending"] = true
	_log(DataRegistry.t("combat.log_defend", [m.name]))
	_end_member_turn()

func _on_flee() -> void:
	if busy:
		return
	if rng.randf() < flee_chance:
		_log(DataRegistry.t("combat.log_flee_ok"))
		_finish_fled()
	else:
		_log(DataRegistry.t("combat.log_flee_fail"))
		_end_member_turn()

func _on_item(index: int) -> void:
	if busy or index >= inventory.size():
		return
	var it := DataRegistry.get_item(inventory[index])
	match String(it.efecto.tipo):
		"curar":
			var targets: Array = []
			for i in _alive_party_indices():
				var member: Dictionary = party[i]
				var idx := i
				targets.append([DataRegistry.t("combat.heal_target", [member.name, member.hp, member.max_hp]), func() -> void: _use_heal(index, idx), int(member.hp) >= int(member.max_hp)])
			_show_menu(String(it.nombre), targets, true)
		"huida_garantizada":
			_consume(index)
			_log(DataRegistry.t("combat.log_smoke"))
			_finish_fled()

func _consume(index: int) -> void:
	items_used.append(inventory[index])
	inventory.remove_at(index)

func _use_heal(index: int, target_i: int) -> void:
	# El menú de objetivos sigue en pantalla durante la espera del turno
	# enemigo: una segunda pulsación no debe gastar otra poción.
	if busy or index >= inventory.size():
		return
	var it := DataRegistry.get_item(inventory[index])
	var m: Dictionary = party[target_i]
	var heal := mini(int(it.efecto.valor), int(m.max_hp) - int(m.hp))
	m["hp"] = int(m.hp) + heal
	_consume(index)
	_float_number("+%d" % heal, _member_float_pos(target_i), "GoodLabel")
	_log(DataRegistry.t("combat.log_heal", [party[current_index].name, it.nombre, m.name, heal]))
	_end_member_turn()

func _enemy_turn() -> void:
	if finished:
		return
	busy = true
	_show_menu(DataRegistry.t("combat.enemy_turn"), [])
	enemy_turns += 1
	var alive := _alive_party_indices()
	if alive.is_empty():
		_finish(false)
		return
	var mult := 1.0
	if ambush_pending:
		mult = _bal("ambush_damage_mult", 1.5)
		ambush_pending = false
	var every := int(_bal("boss_ability_every", 3))
	var boss_ability: bool = enemy.kind == RunRules.BOSS and every > 0 and enemy_turns % every == 0
	enemy_acting.emit("ability" if boss_ability else "attack")
	var windup := _bal("enemy_attack_windup", 0.3)
	if windup > 0.0:
		await get_tree().create_timer(windup).timeout
		if finished:
			return
	if boss_ability:
		# Habilidad de jefe: golpea a todo el equipo.
		var aoe := maxi(roundi(int(enemy.atk) * _bal("boss_ability_mult", 0.7) * mult), 1)
		_log(DataRegistry.t("combat.log_boss_ability", [enemy.name, String(enemy_data.ability_name)]))
		for i in alive:
			_damage_member(i, aoe)
	else:
		var target_i: int = alive[rng.randi_range(0, alive.size() - 1)]
		var variance := int(_bal("damage_variance", 1))
		var dmg := roundi((int(enemy.atk) + rng.randi_range(-variance, variance)) * mult)
		_damage_member(target_i, dmg)
	_refresh_ui()
	if int(enemy.hp) <= 0:
		_finish(true)
		return
	if _alive_party_indices().is_empty():
		_finish(false)
		return
	round_n += 1
	current_index = _alive_party_indices()[0]
	await get_tree().create_timer(0.15).timeout
	_start_turn()

## Golpe del enemigo a un miembro: Defender bloquea un % (más con Guardia
## Inquebrantable), Piel Curtida resta plano, Espinas devuelve daño.
func _damage_member(i: int, raw: int) -> void:
	var target: Dictionary = party[i]
	var dmg := raw
	if target.get("defending", false):
		var block := _bal("defend_block", 0.5)
		var bonus := SoulEffects.total(target, "defend_bonus_multiplier")
		if bonus > 0.0:
			block = clampf(block + bonus, 0.0, _bal("defend_block_max", 0.9))
		dmg = int(dmg * (1.0 - block))
	var reduction := int(SoulEffects.total(target, "damage_reduction_flat"))
	if reduction > 0 and dmg > 0:
		var before := dmg
		dmg = maxi(dmg - reduction, 0)
		if dmg < before:
			var eff := SoulEffects.get_passive_effect(target, "damage_reduction_flat")
			_log(DataRegistry.t("combat.log_absorb", [eff._passive_name, target.name]))
	dmg = maxi(dmg, 0) # con pasivas un golpe SÍ puede quedar en 0
	if god_mode:
		dmg = 0
	target["hp"] = int(target.hp) - dmg
	_log(DataRegistry.t("combat.log_enemy_hit", [enemy.name, target.name, dmg]))
	_float_number("-%d" % dmg, _member_float_pos(i), "DangerLabel")
	_flash(member_cards[i], UIStyle.DANGER)
	var thorns := int(SoulEffects.total(target, "thorns_flat"))
	if thorns > 0 and dmg > 0:
		enemy["hp"] = int(enemy.hp) - thorns
		enemy_hit.emit(thorns)
		_float_number("%d" % thorns, _enemy_float_pos(), "AccentLabel")
		_log(DataRegistry.t("combat.log_thorns", [target.name, thorns]))
	if int(target.hp) <= 0:
		target["hp"] = 0
		_log(DataRegistry.t("combat.log_fallen", [target.name]))

# --- Fin de combate y flujo de alma -----------------------------------------------------

func _result(soul_pick: Dictionary = {}) -> Dictionary:
	var hp := {}
	for m: Dictionary in party:
		hp[m.id] = maxi(int(m.hp), 0)
	return {"hp": hp, "items_used": items_used.duplicate(), "soul_pick": soul_pick}

func _finish_fled() -> void:
	finished = true
	busy = true
	_refresh_ui()
	var on_fled := func() -> void: combat_ended.emit("fled", _result())
	_show_summary(DataRegistry.t("combat.fled_title"), [DataRegistry.t("combat.fled_text")], on_fled)

func _finish(victory: bool) -> void:
	if finished:
		return
	finished = true
	busy = true
	_refresh_ui()
	if not victory:
		_log(DataRegistry.t("combat.log_defeat"))
		var on_defeat := func() -> void: combat_ended.emit("defeat", _result())
		_show_summary(DataRegistry.t("combat.defeat_title"), [DataRegistry.t("combat.defeat_text")], on_defeat, "DangerLabel")
		return
	_log(DataRegistry.t("combat.log_victory"))
	enemy_defeated.emit()
	var lines: Array[String] = [DataRegistry.t("combat.coins_gained", [UIFormat.coins(int(reward_preview.coins))])]
	if reward_preview.get("first_kill", false):
		lines.append(DataRegistry.t("combat.first_kill", [String(reward_preview.get("species_name", enemy.name)), UIFormat.coins(int(reward_preview.first_kill_bonus))]))
	if not soul_drop.is_empty():
		lines.append(DataRegistry.t("combat.soul_hint"))
	_show_summary(DataRegistry.t("combat.victory_title"), lines, _after_victory_summary, "TitleLabel")

## Resumen post-combate: reemplaza la UI de combate por un panel centrado.
func _show_summary(title: String, lines: Array, on_continue: Callable, title_variation := "TitleLabel") -> void:
	for c in menu_box.get_children():
		c.queue_free()
	menu_panel.visible = false
	if summary_panel:
		summary_panel.queue_free()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	summary_panel = UIPanel.new(title, "", title_variation)
	summary_panel.custom_minimum_size.x = 460
	center.add_child(summary_panel)
	for line: Variant in lines:
		var l := Label.new()
		l.text = String(line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if String(line).begins_with(UIStyle.COIN_SYMBOL) or String(line).contains(UIStyle.COIN_SYMBOL):
			l.theme_type_variation = "CoinLabel"
		if String(line).begins_with("★"):
			l.theme_type_variation = "AccentLabel"
		if String(line) == DataRegistry.t("combat.soul_hint"):
			l.theme_type_variation = "SoulLabel"
		summary_panel.body.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	summary_panel.body.add_child(row)
	row.add_child(UIButton.make(DataRegistry.t("ui.continue"), on_continue))
	summary_panel.modulate.a = 0.0
	summary_panel.create_tween().tween_property(summary_panel, "modulate:a", 1.0, UIStyle.TRANSITION)
	UIFocus.grab_first(summary_panel)

func _after_victory_summary() -> void:
	if soul_drop.is_empty():
		combat_ended.emit("victory", _result())
		return
	_reveal_soul()

## Revelación del alma (al pulsar Continuar): la tarjeta aparece con un
## pequeño "pop". Recogerla es opcional.
func _reveal_soul() -> void:
	_clear_summary_body(DataRegistry.t("combat.soul_title"), "SoulLabel")
	var card := UISoulCard.new(soul_drop)
	card.custom_minimum_size.x = 420
	summary_panel.body.add_child(card)
	card.pivot_offset = Vector2(210, 60)
	card.scale = Vector2(0.6, 0.6)
	card.modulate.a = 0.0
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "scale", Vector2.ONE, 0.18)
	tw.tween_property(card, "modulate:a", 1.0, 0.18)
	var q := Label.new()
	q.text = DataRegistry.t("combat.soul_question")
	summary_panel.body.add_child(q)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	summary_panel.body.add_child(row)
	row.add_child(UIButton.make(DataRegistry.t("combat.soul_leave"), func() -> void: combat_ended.emit("victory", _result())))
	var take := UIButton.make(DataRegistry.t("combat.soul_take"), _choose_member)
	row.add_child(take)
	take.call_deferred("grab_focus")

func _clear_summary_body(title: String, variation: String) -> void:
	summary_panel.set_title(title)
	summary_panel.title_label.theme_type_variation = variation
	for c in summary_panel.body.get_children():
		c.queue_free()

## A quién se la das: las almas son por personaje. Los llenos se pueden
## elegir igual: lleva al diálogo de reemplazo.
func _choose_member() -> void:
	_clear_summary_body(DataRegistry.t("combat.soul_who"), "SoulLabel")
	var buttons: Array = []
	for m: Dictionary in party_roster:
		var souls: Array = m.souls
		var cap := int(m.get("soul_capacity", 1))
		var full := souls.size() >= cap
		var label := DataRegistry.t("combat.soul_member", [m.name, souls.size(), cap])
		if full:
			label += "  " + DataRegistry.t("combat.soul_full")
		var mid := String(m.id)
		var on_pick := func() -> void:
			if full:
				_choose_replacement(mid)
			else:
				combat_ended.emit("victory", _result({"member_id": mid, "soul": soul_drop, "replace_index": -1}))
		var b := UIButton.make(label, on_pick)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		summary_panel.body.add_child(b)
		buttons.append(b)
	var back := UIButton.make(DataRegistry.t("ui.back"), _reveal_soul)
	summary_panel.body.add_child(back)
	buttons.append(back)
	UIFocus.chain_vertical(buttons)
	(buttons[0] as Control).call_deferred("grab_focus")

## Personaje lleno: reemplazar una de sus almas (se pierde) o descartar la nueva.
func _choose_replacement(member_id: String) -> void:
	var member: Dictionary = {}
	for m: Dictionary in party_roster:
		if m.id == member_id:
			member = m
	_clear_summary_body(DataRegistry.t("combat.replace_title", [member.get("name", "")]), "AccentLabel")
	var info := Label.new()
	info.text = DataRegistry.t("combat.replace_text")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_panel.body.add_child(info)
	var buttons: Array = []
	var souls: Array = member.get("souls", [])
	for i in souls.size():
		var old: Dictionary = souls[i]
		summary_panel.body.add_child(UISoulCard.new(old, true))
		var idx := i
		var on_replace := func() -> void:
			combat_ended.emit("victory", _result({"member_id": member_id, "soul": soul_drop, "replace_index": idx}))
		var b := UIButton.make(DataRegistry.t("combat.replace_btn", [old.active.name]), on_replace, "DangerButton")
		summary_panel.body.add_child(b)
		buttons.append(b)
	var discard := UIButton.make(DataRegistry.t("combat.discard_new"), func() -> void: combat_ended.emit("victory", _result()))
	summary_panel.body.add_child(discard)
	buttons.append(discard)
	var back := UIButton.make(DataRegistry.t("ui.back"), _choose_member)
	summary_panel.body.add_child(back)
	buttons.append(back)
	UIFocus.chain_vertical(buttons)
	discard.call_deferred("grab_focus")

# --- Debug -------------------------------------------------------------------------------

## Panel de debug / smoke test: gana el combate en el acto.
func debug_win() -> void:
	if finished:
		return
	enemy["hp"] = 0
	_finish(true)

func debug_lose() -> void:
	if finished:
		return
	for m: Dictionary in party:
		m["hp"] = 0
	_finish(false)
