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
## Flujo al ganar: resumen post-combate (monedas, EXP, bonus de primera kill)
## → [Continuar] → si soltó alma, se REVELA en una «carta sellada» azul con
## los héroes como opciones (recogerla es opcional: «Dejarla») → si ese
## personaje está lleno: reemplazar una o descartar la nueva.
##
## UI «Grimorio de la Cripta» (spec 8.5): nombre del enemigo en gótica arriba
## al centro con su barra y placa de rango; orden de turnos en una cinta;
## tarjetas de héroe abajo a la izquierda; registro en un inserto hundido;
## «Acciones» en una tapa de hierro abajo a la derecha. Se reacomoda sola si
## la ventana (o la escala de UI) deja poco ancho.

signal combat_ended(outcome: String, result: Dictionary)
## Para efectos en el mundo 3D (parpadeo y animaciones del modelo del enemigo).
signal enemy_hit(damage: int)
## El enemigo empieza su acción: "attack" | "ability" (habilidad de jefe).
## El daño llega combat.enemy_attack_windup segundos después (el golpe de la
## animación).
signal enemy_acting(action: String)
## El enemigo llegó a 0 HP (antes del resumen de victoria).
signal enemy_defeated

# --- Medidas de la UI (px de canvas, ventana base 1280×720) --------------------------
const EDGE := 16
const GAP := 12
const CARD_W := 272
## Con poco ancho (escala de UI grande) las tarjetas se angostan antes de
## pasar a otra fila.
const CARD_W_NARROW := 240
const ACTIONS_W := 300
const LOG_W := 392
const LOG_MIN_W := 300
const LOG_LINES := 3
## Registro: letras por segundo al escribirse la última línea.
const TYPE_CPS := 60.0
const ENEMY_BAR_W := 600
## Un cuadro de las animaciones por pasos (≈ 15 fps).
const STEP := 0.066

# --- Configuración (la pasa RunController antes de add_child) ---------------------
## {name, rank, hp, atk, ability_damage, ability_name, kind, species_id}
var enemy_data := {"name": "???", "rank": 10, "hp": 10, "atk": 1, "ability_damage": 1, "ability_name": "", "kind": "normal", "species_id": ""}
## Copia del equipo: [{id, name, hp, max_hp, atk, souls, soul_capacity,
## def, ability_bonus, crit_bonus, level, xp, level_win, soul_capacity_win}].
## def/ability_bonus/crit_bonus salen de los puntos de DEF, ESP y AGI;
## level_win y soul_capacity_win, de cómo queda si gana (la EXP de esta kill).
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
## Tipo de cada línea del registro (info | hit | taken | heal | soul | crit).
var log_kinds: Array[String] = []

# --- UI -------------------------------------------------------------------------------
var root: Control
var enemy_box: VBoxContainer
var enemy_name_label: UIGothicLabel
var enemy_bar: UIStatBar
var enemy_hp_label: Label
var enemy_badge: UIRankBadge
var queue_panel: PanelContainer
var queue_row: HBoxContainer
var bottom: BoxContainer
var cards_grid: GridContainer
var member_cards: Array[HeroCard] = []
var log_panel: PanelContainer
var log_labels: Array[Label] = []
var menu_panel: PanelContainer
var menu_title: Label
var breadcrumb: Label
var menu_box: VBoxContainer
## Línea de ayuda al pie de las acciones: qué hace la opción con el foco.
var menu_help: Label
var float_layer: Control
## Diálogo abierto al terminar (resumen, alma, reemplazo).
var dialog: CombatDialog
## Qué muestra el panel de acciones: "actions" | "sub" (submenú) | "wait".
var _menu_level := ""
var _enemy_acting := false
var _log_tween: Tween

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
	_log(DataRegistry.t("combat.start", [enemy.name, int(enemy_data.rank)]))
	if enemy.kind == RunRules.BOSS:
		_log(DataRegistry.t("combat.boss_intro").strip_edges(), "taken")
	match start_mode:
		"surprise":
			surprise_round = true
			_log(DataRegistry.t("combat.surprise"), "crit")
		"ambush":
			ambush_pending = true
			_log(DataRegistry.t("combat.ambush"), "taken")
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
			"def": int(m.get("def", 0)),
			"ability_bonus": int(m.get("ability_bonus", 0)),
			"crit_bonus": float(m.get("crit_bonus", 0.0)),
			"level": int(m.get("level", 1)),
			"xp": int(m.get("xp", 0)),
			"level_win": int(m.get("level_win", m.get("level", 1))),
		})

func _bal(path: String, default: float) -> float:
	return DataRegistry.bal_f("combat." + path, default)

# --- UI ---------------------------------------------------------------------------------

func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_enemy()
	_build_queue()
	_build_party_ui()
	_build_menu()
	float_layer = Control.new()
	float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(float_layer)
	_layout()
	get_viewport().size_changed.connect(_layout)

## Arriba al centro: nombre en gótica, [calavera] barra ancha [rango] y el HP
## en cifras bajo el extremo derecho de la barra.
func _build_enemy() -> void:
	var boss := String(enemy_data.kind) == RunRules.BOSS
	enemy_box = VBoxContainer.new()
	enemy_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_box.add_theme_constant_override("separation", 4)
	enemy_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	enemy_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	enemy_box.offset_top = EDGE
	root.add_child(enemy_box)
	enemy_name_label = UIGothicLabel.new(String(enemy_data.name), "GothicTitle",
		UIStyle.DANGER if boss else UIStyle.TEXT, UIStyle.ACCENT if boss else UIStyle.CAPITAL)
	enemy_name_label.align = HORIZONTAL_ALIGNMENT_CENTER
	enemy_box.add_child(enemy_name_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	enemy_box.add_child(row)
	row.add_child(UIIcon.make("muerte", "sangre" if boss else "bronce"))
	enemy_bar = UIStatBar.new("", "enemy", ENEMY_BAR_W)
	enemy_bar.value_label.visible = false
	enemy_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(enemy_bar)
	enemy_badge = UIRankBadge.new(int(enemy_data.rank))
	row.add_child(enemy_badge)
	# Las cifras cuelgan de la barra (no ocupan lugar en la fila).
	enemy_hp_label = UILabel.make("", "NumSmallLabel")
	enemy_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	enemy_hp_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	enemy_hp_label.offset_left = -96
	enemy_hp_label.offset_right = 0
	enemy_hp_label.offset_top = 2
	enemy_hp_label.offset_bottom = 26
	enemy_bar.bar.add_child(enemy_hp_label)

## Arriba a la derecha: «BJORN › ELENA › ESQUELETO» en una cinta.
func _build_queue() -> void:
	queue_panel = PanelContainer.new()
	queue_panel.theme_type_variation = "ToastPanel"
	queue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_panel.custom_minimum_size.y = 36
	queue_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	queue_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	queue_panel.offset_left = -EDGE
	queue_panel.offset_right = -EDGE
	queue_panel.offset_top = EDGE
	root.add_child(queue_panel)
	queue_row = HBoxContainer.new()
	queue_row.add_theme_constant_override("separation", 6)
	queue_row.alignment = BoxContainer.ALIGNMENT_CENTER
	queue_panel.add_child(queue_row)

## Abajo a la izquierda: tarjetas de héroe + registro (al lado o encima,
## según el ancho; ver _layout).
func _build_party_ui() -> void:
	bottom = BoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", GAP)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bottom)
	cards_grid = GridContainer.new()
	cards_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards_grid.add_theme_constant_override("h_separation", GAP)
	cards_grid.add_theme_constant_override("v_separation", 8)
	cards_grid.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(cards_grid)
	for m: Dictionary in party:
		var card := HeroCard.new(m)
		cards_grid.add_child(card)
		member_cards.append(card)

	log_panel = PanelContainer.new()
	log_panel.theme_type_variation = "PanelAlt"
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(log_panel)
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 2)
	lbox.alignment = BoxContainer.ALIGNMENT_END
	log_panel.add_child(lbox)
	for i in LOG_LINES:
		var l := UILabel.make("", "DetailLabel", true)
		lbox.add_child(l)
		log_labels.append(l)

## Abajo a la derecha: tapa de hierro «Acciones» con los comandos.
func _build_menu() -> void:
	menu_panel = PanelContainer.new()
	menu_panel.custom_minimum_size.x = ACTIONS_W
	menu_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	menu_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	menu_panel.offset_left = -EDGE
	menu_panel.offset_right = -EDGE
	menu_panel.offset_top = -EDGE
	menu_panel.offset_bottom = -EDGE
	root.add_child(menu_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	menu_panel.add_child(v)
	menu_title = UILabel.make(DataRegistry.t("combat.actions"), "HeadLabel")
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(menu_title)
	v.add_child(UIDivider.new(200))
	breadcrumb = UILabel.make("", "NumSmallLabel")
	breadcrumb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	breadcrumb.visible = false
	v.add_child(breadcrumb)
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 4)
	v.add_child(menu_box)
	menu_help = UILabel.make("", "DetailLabel", true)
	menu_help.custom_minimum_size = Vector2(ACTIONS_W - 56, 40)
	menu_help.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	v.add_child(menu_help)

## Reparte el ancho: tarjetas (en 1+ columnas) y registro al lado si entra
## sin pisar las acciones; si no, el registro sube encima de las tarjetas.
func _layout() -> void:
	if root == null or not is_instance_valid(bottom):
		return
	var vp := root.get_viewport_rect().size
	var n := maxi(party.size(), 1)
	var avail := vp.x - 2.0 * EDGE - ACTIONS_W - GAP
	_layout_enemy(vp, avail)
	var card_w := CARD_W
	if n * CARD_W + (n - 1) * GAP > avail:
		card_w = CARD_W_NARROW
	var cols := clampi(int((avail + GAP) / float(card_w + GAP)), 1, n)
	cards_grid.columns = cols
	for c in member_cards:
		c.custom_minimum_size.x = card_w
	var cards_w := float(cols * card_w + (cols - 1) * GAP)
	var inline := avail - cards_w - GAP >= LOG_MIN_W
	bottom.vertical = not inline
	if inline:
		bottom.move_child(log_panel, 1)
		log_panel.custom_minimum_size = Vector2(minf(LOG_W, avail - cards_w - GAP), 0)
		log_panel.size_flags_vertical = Control.SIZE_FILL
		log_panel.size_flags_horizontal = Control.SIZE_FILL
	else:
		bottom.move_child(log_panel, 0)
		log_panel.custom_minimum_size = Vector2(minf(cards_w, 560.0), 100)
		log_panel.size_flags_vertical = Control.SIZE_SHRINK_END
		log_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Poca altura (escala de UI grande): el registro queda en una sola línea
	# para no tapar al enemigo.
	var compact_log := not inline and vp.y < 600.0
	if compact_log:
		log_panel.custom_minimum_size.y = 0
	for i in log_labels.size():
		log_labels[i].visible = not compact_log or i == log_labels.size() - 1
	# Rectángulo nulo en la esquina: crece hacia arriba y a la derecha.
	bottom.offset_left = EDGE
	bottom.offset_right = EDGE
	bottom.offset_top = -EDGE
	bottom.offset_bottom = -EDGE
	_check_queue_overlap.call_deferred()

## Ventana ancha: el enemigo arriba al centro con la barra de 600 px. Angosta
## (escala de UI grande): ocupa el ancho a la izquierda de las acciones, así
## la cinta de turnos y el panel de acciones no lo pisan.
func _layout_enemy(vp: Vector2, avail: float) -> void:
	var stack := enemy_bar.bar.get_parent() as Control
	if vp.x >= 1100.0:
		enemy_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
		enemy_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
		enemy_box.offset_left = 0
		enemy_box.offset_right = 0
		stack.custom_minimum_size.x = ENEMY_BAR_W
	else:
		enemy_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
		enemy_box.grow_horizontal = Control.GROW_DIRECTION_END
		enemy_box.offset_left = EDGE
		enemy_box.offset_right = EDGE + avail
		# Calavera (32) + rango (~44) + separaciones.
		stack.custom_minimum_size.x = maxf(avail - 100.0, 160.0)
	enemy_box.offset_top = EDGE

## Si la cinta de turnos pisa el nombre o la barra del enemigo (nombres
## largos, tres héroes) baja debajo de la barra; si ahí pisa las acciones, se
## oculta: la tarjeta encendida ya dice a quién le toca.
func _check_queue_overlap() -> void:
	if not is_instance_valid(queue_panel) or not is_instance_valid(enemy_box):
		return
	var enemy_rect := enemy_box.get_global_rect()
	# Las cifras de HP cuelgan 26 px bajo la barra.
	enemy_rect.size.y += 28.0
	queue_panel.offset_top = EDGE
	queue_panel.offset_bottom = EDGE
	var r := Rect2(queue_panel.get_global_rect().position.x, EDGE, queue_panel.get_combined_minimum_size().x, queue_panel.get_combined_minimum_size().y).grow(4)
	if r.intersects(enemy_rect):
		var top := roundf((enemy_rect.end.y + 4.0) / 2.0) * 2.0
		queue_panel.offset_top = top
		queue_panel.offset_bottom = top
		r.position.y = top - 4.0
	queue_panel.visible = not finished and not r.intersects(enemy_rect) and not r.intersects(menu_panel.get_global_rect())

func _refresh_ui() -> void:
	enemy_bar.animate_to(int(enemy.hp), int(enemy.max_hp))
	enemy_hp_label.text = "%d/%d" % [maxi(int(enemy.hp), 0), int(enemy.max_hp)]
	for i in party.size():
		var m: Dictionary = party[i]
		var acting: bool = i == current_index and int(m.hp) > 0 and not busy and not finished
		member_cards[i].refresh(m, acting)
	_refresh_queue()
	_check_queue_overlap()

## Orden de turnos: quien actúa ahora en vela, el resto en ceniza.
func _refresh_queue() -> void:
	if queue_row == null:
		return
	for c in queue_row.get_children():
		queue_row.remove_child(c)
		c.queue_free()
	var names: Array[String] = []
	var alive := _alive_party_indices()
	var start := alive.find(current_index)
	if start == -1:
		start = 0
	if _enemy_acting:
		names.append(String(enemy.name))
		start = 0
	for k in alive.size():
		var idx: int = alive[(start + k) % alive.size()]
		names.append(String(party[idx].name))
	if not _enemy_acting:
		names.append(String(enemy.name))
	for k in names.size():
		if k > 0:
			var sep := UILabel.make("›", "NumSmallLabel")
			sep.add_theme_color_override("font_color", UIStyle.TEXT_OFF)
			queue_row.add_child(sep)
		var l := UILabel.make(names[k].to_upper(), "NumSmallLabel")
		if k == 0 and not finished:
			l.add_theme_color_override("font_color", UIStyle.ACCENT)
		queue_row.add_child(l)

## Registro: kind info | hit | taken | heal | soul | crit (color de cada línea).
func _log(text: String, kind := "info") -> void:
	log_lines.append(text)
	log_kinds.append(kind)
	while log_lines.size() > LOG_LINES:
		log_lines.pop_front()
		log_kinds.pop_front()
	_render_log()

static func _log_color(kind: String) -> Color:
	match kind:
		"taken":
			return UIStyle.DANGER
		"heal":
			return UIStyle.GOOD
		"soul":
			return UIStyle.SOUL
		"crit":
			return UIStyle.ACCENT
	return UIStyle.TEXT

## Las líneas viejas suben; la nueva se escribe a 60 letras por segundo.
func _render_log() -> void:
	if log_labels.is_empty():
		return
	var first_line := LOG_LINES - log_lines.size()
	for i in LOG_LINES:
		var l := log_labels[i]
		var k := i - first_line
		l.visible_characters = -1
		if k < 0:
			l.text = ""
			continue
		l.text = log_lines[k]
		l.add_theme_color_override("font_color", _log_color(log_kinds[k]))
	if _log_tween:
		_log_tween.kill()
	var last := log_labels[LOG_LINES - 1]
	if last.text == "":
		return
	last.visible_characters = 0
	_log_tween = last.create_tween()
	_log_tween.tween_property(last, "visible_characters", last.text.length(), last.text.length() / TYPE_CPS)

## Número flotante (daño, curación, crítico): sube 16 px en 8 pasos de 2 px
## en medio segundo y desaparece.
func _float_number(text: String, at: Vector2, variation: String, color := Color.TRANSPARENT) -> void:
	var l := UILabel.make(text, variation)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	l.position = (at / 2.0).round() * 2.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	float_layer.add_child(l)
	var tw := l.create_tween()
	for i in 8:
		tw.tween_interval(0.5 / 8.0)
		tw.tween_callback(func() -> void: l.position.y -= 2.0)
	tw.tween_interval(0.2)
	tw.tween_callback(l.queue_free)

func _enemy_float_pos() -> Vector2:
	var vp := root.get_viewport_rect().size
	return Vector2(vp.x * 0.5 - 16.0 + rng.randf_range(-30.0, 30.0), vp.y * 0.26)

func _member_float_pos(i: int) -> Vector2:
	var r := member_cards[i].get_global_rect()
	return Vector2(r.position.x + r.size.x * 0.55, r.position.y - 52.0)

## Destello de un cuadro (por pasos, sin fundido).
func _flash(control: Control, color: Color) -> void:
	control.modulate = color
	var tw := control.create_tween()
	tw.tween_interval(STEP * 2.0)
	tw.tween_callback(func() -> void: control.modulate = Color.WHITE)

# --- Menús de acción ---------------------------------------------------------------------

## entries: [{text, on, disabled?, tip?, icon? (id del kit), picture? (Texture2D),
## value? (cifra a la derecha)}]. Con with_back es un submenú: muestra la miga
## «ACCIONES › TÍTULO» y un botón Volver al final.
func _show_menu(title: String, entries: Array, with_back := false) -> void:
	_menu_level = "sub" if with_back else "actions"
	breadcrumb.visible = with_back
	breadcrumb.text = DataRegistry.t("combat.breadcrumb", [title]).to_upper()
	breadcrumb.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_clear_menu()
	menu_help.text = ""
	var buttons: Array = []
	for e: Dictionary in entries:
		buttons.append(_menu_button(e))
	if with_back:
		buttons.append(_menu_button({"text": DataRegistry.t("ui.back"), "on": _back_to_actions}))
	UIFocus.chain_vertical(buttons)
	UIFocus.grab_first(menu_box)
	_fit_menu()

func _clear_menu() -> void:
	for c in menu_box.get_children():
		menu_box.remove_child(c)
		c.queue_free()

## Botón de piedra con ícono del kit (bronce → vela con el foco; apagado si
## está deshabilitado), retrato de objeto o cifra a la derecha.
func _menu_button(e: Dictionary) -> UIButton:
	var on: Callable = e.get("on", Callable())
	var b := UIButton.make(String(e.get("text", "")), on) if on.is_valid() else UIButton.new(String(e.get("text", "")))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = bool(e.get("disabled", false))
	menu_box.add_child(b)
	# La ayuda va al pie del panel (no tapa los botones); los deshabilitados
	# no toman foco: su motivo sale en un tooltip al pasar el mouse.
	var tip := String(e.get("tip", ""))
	if b.disabled:
		if tip != "":
			UITooltip.attach(b, tip)
	else:
		b.focus_entered.connect(func() -> void: menu_help.text = tip)
	var icon_id := String(e.get("icon", ""))
	var picture: Variant = e.get("picture")
	if icon_id != "":
		b.icon = UIIcon.texture_for(icon_id, "apagado" if b.disabled else "bronce")
		b.add_theme_color_override("icon_disabled_color", Color.WHITE)
		if not b.disabled:
			b.focus_entered.connect(func() -> void: b.icon = UIIcon.texture_for(icon_id, "vela"))
			b.focus_exited.connect(func() -> void: b.icon = UIIcon.texture_for(icon_id, "bronce"))
	elif picture is Texture2D:
		b.icon = picture
	var value := String(e.get("value", ""))
	if value != "":
		var v := UILabel.make(value, "NumSmallLabel")
		v.add_theme_color_override("font_color", UIStyle.DANGER)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		v.offset_left = -60
		v.offset_right = -12
		b.add_child(v)
		# Que el nombre no se monte sobre la cifra.
		var font := b.get_theme_font("font")
		var text_w := font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
		b.custom_minimum_size.x = ceilf(text_w + 24.0 + 12.0 + v.get_minimum_size().x)
	return b

## Rectángulo nulo en la esquina: el panel toma su tamaño mínimo y crece
## hacia arriba y a la izquierda (se ajusta solo a cada menú).
func _fit_menu() -> void:
	menu_panel.offset_left = -EDGE
	menu_panel.offset_right = -EDGE
	menu_panel.offset_top = -EDGE
	menu_panel.offset_bottom = -EDGE

func _back_to_actions() -> void:
	SceneRouter.play_ui("cancel")
	_show_actions()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not busy and not finished and _menu_level == "sub":
		get_viewport().set_input_as_handled()
		_back_to_actions()

func _show_actions() -> void:
	if finished or busy:
		return
	_enemy_acting = false
	var m: Dictionary = party[current_index]
	var has_abilities := not (m.souls as Array).is_empty()
	var usable := _combat_items()
	var is_boss: bool = enemy.kind == RunRules.BOSS
	_show_menu(DataRegistry.t("combat.actions"), [
		{"text": DataRegistry.t("combat.attack"), "on": _on_attack, "icon": "atacar", "tip": DataRegistry.t("combat.attack_tip", [int(m.atk)])},
		{"text": DataRegistry.t("combat.ability"), "on": _show_abilities, "icon": "habilidad", "disabled": not has_abilities,
			"tip": DataRegistry.t("combat.ability_tip") if has_abilities else DataRegistry.t("combat.ability_none")},
		{"text": DataRegistry.t("combat.defend"), "on": _on_defend, "icon": "stat_def", "tip": DataRegistry.t("combat.defend_tip")},
		{"text": DataRegistry.t("combat.item"), "on": _show_items, "icon": "objeto", "disabled": usable.is_empty(),
			"tip": DataRegistry.t("combat.item_tip") if not usable.is_empty() else DataRegistry.t("combat.item_none")},
		{"text": DataRegistry.t("combat.flee_pct", [UIFormat.pct(flee_chance)]) if not is_boss else DataRegistry.t("combat.flee"),
			"on": _on_flee, "icon": "huir", "disabled": is_boss,
			"tip": DataRegistry.t("combat.flee_boss") if is_boss else DataRegistry.t("combat.flee_tip")},
	])
	_refresh_queue()
	_check_queue_overlap()

## Turno del enemigo: los comandos quedan a la vista pero apagados, con la
## miga «TURNO ENEMIGO» en rojo.
func _show_waiting() -> void:
	_menu_level = "wait"
	_enemy_acting = true
	breadcrumb.visible = true
	breadcrumb.text = DataRegistry.t("combat.enemy_turn").to_upper()
	breadcrumb.add_theme_color_override("font_color", UIStyle.DANGER)
	_clear_menu()
	menu_help.text = ""
	for pair: Array in [["combat.attack", "atacar"], ["combat.ability", "habilidad"], ["combat.defend", "stat_def"], ["combat.item", "objeto"], ["combat.flee", "huir"]]:
		_menu_button({"text": DataRegistry.t(String(pair[0])), "icon": String(pair[1]), "disabled": true})
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and menu_panel.is_ancestor_of(focused):
		focused.release_focus()
	_fit_menu()
	_refresh_queue()

func _show_abilities() -> void:
	var m: Dictionary = party[current_index]
	var entries: Array = []
	for soul: Dictionary in m.souls:
		var active: Dictionary = soul.get("active", {})
		var dmg := int(active.get("damage", 1)) + int(m.get("ability_bonus", 0))
		var aname := String(active.get("name", "?"))
		entries.append({"text": aname, "value": str(dmg), "tip": DataRegistry.t("combat.ability_entry", [aname, dmg]),
			"on": func() -> void: _on_ability(aname, dmg)})
	_show_menu(DataRegistry.t("combat.ability"), entries, true)

func _combat_items() -> Array[int]:
	var out: Array[int] = []
	for i in inventory.size():
		var it := DataRegistry.get_item(inventory[i])
		if it.is_empty() or not bool(it.efecto.en_combate):
			continue
		out.append(i)
	return out

func _show_items() -> void:
	var entries: Array = []
	for i in _combat_items():
		var it := DataRegistry.get_item(inventory[i])
		var idx := i
		var disabled: bool = it.efecto.tipo == "huida_garantizada" and enemy.kind == RunRules.BOSS
		entries.append({"text": String(it.nombre), "on": func() -> void: _on_item(idx), "disabled": disabled,
			"tip": String(it.descripcion), "picture": UIPortrait.item_texture(inventory[i])})
	_show_menu(DataRegistry.t("combat.item"), entries, true)

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
	_enemy_acting = false
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
	var crit := rng.randf() < SoulEffects.total(member, "crit_chance") + float(member.get("crit_bonus", 0.0))
	if crit:
		dmg = roundi(dmg * _bal("crit_mult", 2.0))
	if one_hit:
		dmg = maxi(dmg, int(enemy.hp))
	return [maxi(dmg, 1), crit]

func _hit_enemy(member: Dictionary, dmg: int, crit: bool) -> void:
	enemy["hp"] = int(enemy.hp) - dmg
	enemy_hit.emit(dmg)
	_flash(enemy_box, UIStyle.DANGER)
	_float_number(("-%d!" if crit else "-%d") % dmg, _enemy_float_pos(), "DamageLabel", UIStyle.ACCENT if crit else Color.TRANSPARENT)
	# Pasiva de robo de vida: cura una parte del daño hecho.
	var steal := SoulEffects.total(member, "lifesteal_pct")
	if steal > 0.0 and int(member.hp) > 0:
		var heal := mini(roundi(dmg * steal), int(member.max_hp) - int(member.hp))
		if heal > 0:
			member["hp"] = int(member.hp) + heal
			_float_number("+%d" % heal, _member_float_pos(party.find(member)), "HealLabel")
	SceneRouter.play_ui("click")

func _on_attack() -> void:
	if busy:
		return
	var m: Dictionary = party[current_index]
	var variance := int(_bal("damage_variance", 1))
	var r := _outgoing(m, maxi(int(m.atk) + rng.randi_range(-variance, variance), 1))
	_hit_enemy(m, r[0], r[1])
	_log(DataRegistry.t("combat.log_attack_crit" if r[1] else "combat.log_attack", [m.name, r[0]]), "crit" if r[1] else "hit")
	_end_member_turn()

func _on_ability(ability_name: String, base_dmg: int) -> void:
	if busy:
		return
	var m: Dictionary = party[current_index]
	var r := _outgoing(m, base_dmg)
	_hit_enemy(m, r[0], r[1])
	_log(DataRegistry.t("combat.log_ability", [m.name, ability_name, r[0]]), "crit" if r[1] else "hit")
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
		_log(DataRegistry.t("combat.log_flee_fail"), "taken")
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
				targets.append({"text": DataRegistry.t("combat.heal_target", [member.name, member.hp, member.max_hp]),
					"on": func() -> void: _use_heal(index, idx), "disabled": int(member.hp) >= int(member.max_hp),
					"picture": UIPortrait.hero_texture(String(member.id))})
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
	SceneRouter.play_ui("item")
	_float_number("+%d" % heal, _member_float_pos(target_i), "HealLabel")
	_log(DataRegistry.t("combat.log_heal", [party[current_index].name, it.nombre, m.name, heal]), "heal")
	_end_member_turn()

func _enemy_turn() -> void:
	if finished:
		return
	busy = true
	_show_waiting()
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
		_log(DataRegistry.t("combat.log_boss_ability", [enemy.name, String(enemy_data.ability_name)]), "taken")
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
			_log(DataRegistry.t("combat.log_absorb", [eff._passive_name, target.name]), "soul")
	# DEF (puntos de estadística) resta daño, pero solo no deja un golpe en 0.
	var def := int(target.get("def", 0))
	if def > 0 and dmg > 1:
		dmg = maxi(dmg - def, 1)
	dmg = maxi(dmg, 0) # con pasivas un golpe SÍ puede quedar en 0
	if god_mode:
		dmg = 0
	target["hp"] = int(target.hp) - dmg
	_log(DataRegistry.t("combat.log_enemy_hit", [enemy.name, target.name, dmg]), "taken")
	_float_number("-%d" % dmg, _member_float_pos(i), "DamageLabel")
	_flash(member_cards[i], UIStyle.DANGER)
	var thorns := int(SoulEffects.total(target, "thorns_flat"))
	if thorns > 0 and dmg > 0:
		enemy["hp"] = int(enemy.hp) - thorns
		enemy_hit.emit(thorns)
		_float_number("-%d" % thorns, _enemy_float_pos(), "DamageLabel")
		_log(DataRegistry.t("combat.log_thorns", [target.name, thorns]), "soul")
	if int(target.hp) <= 0:
		target["hp"] = 0
		_log(DataRegistry.t("combat.log_fallen", [target.name]), "taken")

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
	var d := _open_dialog(DataRegistry.t("combat.fled_title"), DataRegistry.t("combat.fled_text"), "normal", "close")
	d.add_button(DataRegistry.t("ui.continue"), on_fled).call_deferred("grab_focus")

func _finish(victory: bool) -> void:
	if finished:
		return
	finished = true
	busy = true
	_refresh_ui()
	if not victory:
		_log(DataRegistry.t("combat.log_defeat"), "taken")
		var on_defeat := func() -> void: combat_ended.emit("defeat", _result())
		var dd := _open_dialog(DataRegistry.t("combat.defeat_title"), DataRegistry.t("combat.defeat_text"), "danger")
		dd.add_button(DataRegistry.t("ui.continue"), on_defeat).call_deferred("grab_focus")
		return
	_log(DataRegistry.t("combat.log_victory"), "crit")
	enemy_defeated.emit()
	_show_victory()

## Resumen de victoria: libro de cuentas con monedas y EXP, subidas de nivel,
## primera muerte de la especie (con sello) y el aviso del alma.
func _show_victory() -> void:
	var d := _open_dialog(DataRegistry.t("combat.victory_title"), "", "normal", "reward")
	d.title_label.set_colors(UIStyle.BRONZE_LIGHT, UIStyle.CAPITAL)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	rows.custom_minimum_size.x = 480
	rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	d.add_content(rows)
	rows.add_child(UILedgerRow.new(DataRegistry.t("combat.ledger_coins"), DataRegistry.t("combat.ledger_value", [int(reward_preview.coins)]), "CoinLabel", "monedas", "moneda"))
	if int(reward_preview.get("xp", 0)) > 0:
		var xp_row := UILedgerRow.new(DataRegistry.t("combat.ledger_xp"), DataRegistry.t("combat.ledger_value", [int(reward_preview.xp)]), "NumLabel", "exp", "amatista")
		xp_row.value_label.add_theme_color_override("font_color", UIStyle.XP)
		UITooltip.attach(xp_row, DataRegistry.t("combat.xp_gained", [int(reward_preview.xp)]))
		rows.add_child(xp_row)
		for p: Dictionary in party:
			if int(p.hp) > 0 and int(p.level_win) > int(p.level):
				rows.add_child(_note_row(UIIcon.make("exp", "amatista"), DataRegistry.t("combat.level_up_line", [p.name, int(p.level_win)]), UIStyle.XP))
	if reward_preview.get("first_kill", false):
		rows.add_child(_note_row(UISprite.new("seal_mini"), DataRegistry.t("combat.first_kill", [String(reward_preview.get("species_name", enemy.name)), UIFormat.coins(int(reward_preview.first_kill_bonus))]), UIStyle.ACCENT))
	if not soul_drop.is_empty():
		rows.add_child(_note_row(UIIcon.make("almas", "alma"), DataRegistry.t("combat.soul_hint"), UIStyle.SOUL))
	d.add_button(DataRegistry.t("ui.continue"), _after_victory_summary).call_deferred("grab_focus")

## Fila de nota: [ícono 32] texto que se parte en líneas.
func _note_row(icon: Control, text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	icon.custom_minimum_size.x = maxf(icon.custom_minimum_size.x, UIStyle.ICON_SIZE)
	row.add_child(icon)
	var l := UILabel.make(text, "", true)
	l.add_theme_color_override("font_color", color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return row

## Abre un diálogo (y cierra el anterior). Oculta la UI de combate: queda el
## 3D detrás del velo.
func _open_dialog(title: String, text: String, tone: String, sound := "", width := 600, vertical := false) -> CombatDialog:
	_dismiss_dialog()
	for c: Control in [enemy_box, queue_panel, bottom, menu_panel]:
		if is_instance_valid(c):
			c.visible = false
	var d := CombatDialog.new()
	d.setup(title, text, tone, width, vertical, sound)
	add_child(d)
	dialog = d
	return d

func _dismiss_dialog() -> void:
	if is_instance_valid(dialog):
		dialog.queue_free()
	dialog = null

func _after_victory_summary() -> void:
	if soul_drop.is_empty():
		combat_ended.emit("victory", _result())
		return
	_reveal_soul()

## Revelación del alma (spec 8.11): carta azul con la tarjeta del alma, motas
## que suben, «¿Quién la lleva?» y un botón por héroe (o Dejarla). El foco
## arranca en el héroe sugerido: el vivo con lugar y menos almas.
func _reveal_soul() -> void:
	var vertical := party_roster.size() > 2
	var d := _open_dialog(DataRegistry.t("combat.soul_title"), "", "soul", "soul", 760, vertical)
	var card := UISoulCard.new(soul_drop)
	card.custom_minimum_size.x = 480
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_child(UISoulMotes.new())
	d.add_content(card)
	_pop_in(card)
	var quote := UIGothicLabel.new(DataRegistry.t("combat.soul_who"), "GothicQuote", UIStyle.TEXT_DIM, UIStyle.SOUL)
	quote.align = HORIZONTAL_ALIGNMENT_CENTER
	d.add_content(quote)

	var buttons: Array = []
	buttons.append(d.add_button(DataRegistry.t("combat.soul_leave"), func() -> void: combat_ended.emit("victory", _result())))
	var suggested: UIButton = null
	var best := 1 << 30
	for m: Dictionary in party_roster:
		var souls: Array = m.souls
		var cap := _capacity_after_win(m)
		var full := souls.size() >= cap
		var mid := String(m.id)
		var on_pick := func() -> void:
			if full:
				_choose_replacement(mid)
			else:
				SceneRouter.play_ui("soul")
				combat_ended.emit("victory", _result({"member_id": mid, "soul": soul_drop, "replace_index": -1}))
		var b := d.add_button(DataRegistry.t("combat.soul_member", [m.name, souls.size(), cap]), on_pick)
		b.icon = UIIcon.kit_texture("soul_empty" if full else "soul_full")
		if full:
			UITooltip.attach(b, DataRegistry.t("combat.soul_full"))
		buttons.append(b)
		if not full and _member_alive(mid) and souls.size() < best:
			best = souls.size()
			suggested = b
	if vertical:
		UIFocus.chain_vertical(buttons)
	if suggested == null:
		suggested = buttons[mini(1, buttons.size() - 1)]
	suggested.call_deferred("grab_focus")

## La tarjeta aparece con un «pop» en dos cuadros (80% → 100%).
func _pop_in(c: Control) -> void:
	c.scale = Vector2(0.8, 0.8)
	var tw := c.create_tween()
	tw.tween_interval(STEP)
	tw.tween_callback(func() -> void:
		c.pivot_offset = (c.size / 4.0).round() * 2.0
		c.scale = Vector2(0.9, 0.9))
	tw.tween_interval(STEP)
	tw.tween_callback(func() -> void: c.scale = Vector2.ONE)

func _member_alive(member_id: String) -> bool:
	for p: Dictionary in party:
		if String(p.id) == member_id:
			return int(p.hp) > 0
	return false

## Capacidad de almas con la que queda al ganar: quien sigue en pie recibe la
## EXP de esta kill y, si llega a un nivel par, tiene un espacio más.
func _capacity_after_win(m: Dictionary) -> int:
	var cap := int(m.get("soul_capacity", 1))
	for p: Dictionary in party:
		if String(p.id) == String(m.id) and int(p.hp) > 0:
			cap = int(m.get("soul_capacity_win", cap))
	return cap

## Personaje lleno: reemplazar una de sus almas (se pierde) o descartar la
## nueva. Variante de peligro de la carta; Esc vuelve a elegir héroe.
func _choose_replacement(member_id: String) -> void:
	var member: Dictionary = {}
	for m: Dictionary in party_roster:
		if m.id == member_id:
			member = m
	var d := _open_dialog(DataRegistry.t("combat.replace_title", [member.get("name", "")]), DataRegistry.t("combat.replace_text"), "danger", "", 760)
	d.on_cancel = _reveal_soul
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	var replace_buttons: Array = []
	var souls: Array = member.get("souls", [])
	for i in souls.size():
		var old: Dictionary = souls[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", GAP)
		list.add_child(row)
		var card := UISoulCard.new(old, true)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		var idx := i
		var on_replace := func() -> void:
			SceneRouter.play_ui("soul")
			combat_ended.emit("victory", _result({"member_id": member_id, "soul": soul_drop, "replace_index": idx}))
		var b := UIButton.make(DataRegistry.t("combat.replace_short"), on_replace, "DangerButton")
		b.custom_minimum_size.x = 160
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UITooltip.attach(b, DataRegistry.t("combat.replace_btn", [(old.get("active", {}) as Dictionary).get("name", "")]))
		row.add_child(b)
		replace_buttons.append(b)
	if souls.size() > 2:
		# Muchas almas: la lista se desplaza (la carta no se sale de la ventana).
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		scroll.custom_minimum_size.y = 260
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		d.add_content(scroll)
	else:
		d.add_content(list)
	var back := d.add_button(DataRegistry.t("ui.back"), _reveal_soul)
	var discard := d.add_button(DataRegistry.t("combat.discard_new"), func() -> void: combat_ended.emit("victory", _result()))
	var chain: Array = replace_buttons.duplicate()
	chain.append(discard)
	UIFocus.chain_vertical(chain, false)
	if not replace_buttons.is_empty():
		back.focus_neighbor_top = back.get_path_to(replace_buttons[replace_buttons.size() - 1] as Control)
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


## Tarjeta de héroe (spec 8.5): [retrato] Nombre ······ 20/20
##                                         ▮▮▮▮▮▮ HP ▮▮▮▮▮▮
##                                         🔥▯ Golpe Bárbaro
##                              NV 3 ▮▮▮▮▮▮ EXP ▮▮▮▮▮▮▮▮▮▮▮▮
## La que actúa: placa encendida, retrato con marco de brasa y la llama del
## cursor sobre el borde. Caído: retrato apagado con calavera, cifras apagadas.
class HeroCard extends PanelContainer:
	var portrait: UIPortrait
	var name_label: Label
	var guard: UIIcon
	var hp_label: Label
	var bar: UIStatBar
	var souls: UISoulSlots
	var soul_label: Label
	var level_label: Label
	var xp_bar: UIStatBar
	var flame: UIFlameCursor
	var _souls_key := ""

	func _init(m: Dictionary) -> void:
		theme_type_variation = "Card"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_END
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		add_child(box)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		box.add_child(top)
		portrait = UIPortrait.for_hero(String(m.get("id", "")), 44)
		top.add_child(portrait)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(col)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		col.add_child(head)
		name_label = UILabel.make(String(m.get("name", "")), "SubtitleLabel")
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(name_label)
		guard = UIIcon.make("stat_def", "vela")
		guard.visible = false
		guard.tooltip_text = DataRegistry.t("combat.defending")
		head.add_child(guard)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(spacer)
		hp_label = UILabel.make("", "NumLabel")
		hp_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(hp_label)
		bar = UIStatBar.new("", "hp", 120)
		bar.value_label.visible = false
		col.add_child(bar)
		var soul_row := HBoxContainer.new()
		soul_row.add_theme_constant_override("separation", 6)
		col.add_child(soul_row)
		souls = UISoulSlots.new(0, 1)
		soul_row.add_child(souls)
		soul_label = UILabel.make("", "SoulLabel")
		soul_label.add_theme_font_size_override("font_size", UIStyle.FONT_DETAIL)
		soul_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		soul_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		soul_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		soul_label.clip_text = true
		soul_row.add_child(soul_label)
		var xp_row := HBoxContainer.new()
		xp_row.add_theme_constant_override("separation", 8)
		box.add_child(xp_row)
		level_label = UILabel.make("", "XpLabel")
		level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		xp_row.add_child(level_label)
		xp_bar = UIStatBar.new("", "xp_thin", 60)
		xp_bar.value_label.visible = false
		xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		xp_row.add_child(xp_bar)
		# Llama del turno: cuelga sobre el borde superior, encima del retrato.
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(holder)
		flame = UIFlameCursor.new()
		flame.position = Vector2(22, -28)
		flame.size = flame.custom_minimum_size
		flame.visible = false
		holder.add_child(flame)

	func refresh(m: Dictionary, acting: bool) -> void:
		var hp := int(m.hp)
		var max_hp := int(m.max_hp)
		var fallen := hp <= 0
		bar.animate_to(hp, max_hp)
		hp_label.text = "%d/%d" % [maxi(hp, 0), max_hp]
		theme_type_variation = "CardFocus" if acting else "Card"
		portrait.set_active(acting)
		portrait.set_fallen(fallen)
		flame.visible = acting
		guard.visible = bool(m.get("defending", false)) and not fallen
		var soul_list: Array = m.get("souls", [])
		var cap := int(m.get("soul_capacity", 1))
		var key := "%d/%d" % [soul_list.size(), cap]
		if key != _souls_key:
			_souls_key = key
			souls.setup(soul_list.size(), maxi(cap, soul_list.size()))
		if fallen:
			soul_label.text = DataRegistry.t("combat.fallen")
			soul_label.add_theme_color_override("font_color", UIStyle.TEXT_OFF)
		elif soul_list.is_empty():
			soul_label.text = DataRegistry.t("combat.no_soul")
			soul_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		else:
			var first: Dictionary = soul_list[0]
			var txt := String((first.get("active", {}) as Dictionary).get("name", ""))
			if soul_list.size() > 1:
				txt += " +%d" % (soul_list.size() - 1)
			soul_label.text = txt
			soul_label.add_theme_color_override("font_color", UIStyle.SOUL)
		var level := int(m.get("level", 1))
		level_label.text = DataRegistry.t("hud.level", [level]).to_upper()
		var need := RunRules.xp_to_next(level)
		xp_bar.set_values(int(m.get("xp", 0)) if need > 0 else 1, need if need > 0 else 1)
		name_label.add_theme_color_override("font_color", UIStyle.TEXT_OFF if fallen else (UIStyle.ACCENT if acting else UIStyle.TEXT))
		hp_label.add_theme_color_override("font_color", UIStyle.TEXT_OFF if fallen else UIStyle.TEXT)
		level_label.add_theme_color_override("font_color", UIStyle.TEXT_OFF if fallen else UIStyle.XP)


## Carta sellada del combate (resumen, alma, reemplazo): la de UIDialog con
## su propio sonido de apertura y, si se pide, Esc para volver atrás.
class CombatDialog extends UIDialog:
	var sound := ""
	var on_cancel := Callable()

	func setup(title: String, text: String, p_tone: String, width: int, vertical: bool, p_sound: String) -> void:
		sound = p_sound
		_build_frame(title, text, p_tone, width, vertical)

	func _ready() -> void:
		if sound == "":
			super._ready()
		else:
			SceneRouter.play_ui(sound)

	func _unhandled_input(event: InputEvent) -> void:
		if on_cancel.is_valid() and event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			SceneRouter.play_ui("cancel")
			on_cancel.call()
