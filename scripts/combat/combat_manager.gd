extends CanvasLayer
## Combate por turnos — vista en primera persona estática: la cámara de
## exploración se queda congelada (GridPlayer.input_locked) y todo el combate
## se resuelve en UI encima, sin cambiar de escena.
##
## Uno contra uno: el héroe contra un enemigo. Las reglas están en
## CombatCore (sin UI, las mismas que juega el simulador de balance); acá se
## presentan sus eventos: registro, números que flotan, destellos y señales
## para animar al enemigo en el mundo 3D.
##
## Autocontenido: recibe todo por propiedades ANTES de add_child(), trabaja
## sobre COPIAS (nunca toca GameState) y al terminar reporta por señal:
##   combat_ended(outcome, result)
##     outcome: "victory" | "defeat" | "fled"
##     result:  {hp: {member_id: hp}, items_used: [item_id...], coins: n,
##               soul_pick: {member_id, soul, replace_index} | {}}
## RunController aplica eso al estado de la run.
##
## Flujo al ganar: resumen post-combate (monedas, EXP, bonus de primera kill)
## → [Continuar] → si soltó alma, se REVELA en una «carta sellada» azul con
## lo que activaría (afinidades, pactos) → Tomarla / Dejarla; sin lugar:
## reemplazar una o dejar la nueva.
##
## UI «Grimorio de la Cripta»: nombre del enemigo en gótica arriba al centro
## con su barra, placa de rango y sus estados (sangrado, aturdido, marca,
## debilitado, carga); la tarjeta del héroe y el registro abajo a la
## izquierda; «Acciones» en una tapa de hierro abajo a la derecha.

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
const CARD_W := 300
const ACTIONS_W := 300
const LOG_W := 420
const LOG_MIN_W := 300
const LOG_LINES := 3
## Registro: letras por segundo al escribirse la última línea.
const TYPE_CPS := 60.0
const ENEMY_BAR_W := 600
## Un cuadro de las animaciones por pasos (≈ 15 fps).
const STEP := 0.066
## Estados del enemigo: ícono del kit y rampa.
const STATUS_ICONS := {
	"sangrado": ["afin_sangre", "sangre"], "aturdido": ["estado_aturdido", "vela"],
	"marca": ["estado_marca", "sangre"], "debil": ["estado_debil", "amatista"], "carga": ["muerte", "sangre"],
}

# --- Configuración (la pasa RunController antes de add_child) ---------------------
## {name, rank, hp, atk, ability_name, kind, species_id}
var enemy_data := {"name": "???", "rank": 10, "hp": 10, "atk": 1, "ability_name": "", "kind": "normal", "species_id": ""}
## El héroe (GameState.combat_hero) + {soul_capacity, level, xp, level_win,
## soul_capacity_win}: level_win y soul_capacity_win, cómo queda si gana.
var hero_data := {}
## Copia del inventario (ids); se usan solo los que sirven en combate.
var inventory: Array[String] = []
## "surprise" (tú chocaste: turno gratis ×1.5) | "ambush" (te alcanzaron por
## la espalda/costado: el enemigo pega primero ×1.5) | "normal" | "boss"
## (después de la presentación del jefe: el héroe golpea primero, como en
## "surprise" —el balance cuenta con eso—, y el cartel entra con su barra)
var start_mode := "normal"
var flee_chance := 0.5
## Alma ya sorteada al empezar ({} = no suelta nada). Se revela al ganar.
var soul_drop: Dictionary = {}
## Para el resumen post-combate: {coins, xp, first_kill, first_kill_bonus, species_name}
var reward_preview := {"coins": 0, "first_kill": false, "first_kill_bonus": 0}
var god_mode := false
var one_hit := false
var rng: RandomNumberGenerator = null

# --- Estado ---------------------------------------------------------------------------
var core: CombatCore
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
var status_row: HBoxContainer
var bottom: BoxContainer
var hero_card: HeroCard
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
var _log_tween: Tween
var _status_key := ""

func _ready() -> void:
	layer = 10
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	core = CombatCore.new(rng)
	core.god_mode = god_mode
	core.one_hit = one_hit
	var start_events := core.setup(hero_data, enemy_data, start_mode)
	_build_ui()
	_log(DataRegistry.t("combat.start", [enemy_data.name, int(enemy_data.rank)]))
	if String(enemy_data.kind) == RunRules.BOSS:
		_log(DataRegistry.t("combat.boss_intro").strip_edges(), "taken")
	match start_mode:
		"surprise":
			_log(DataRegistry.t("combat.surprise"), "crit")
		"boss":
			_log(DataRegistry.t("combat.boss_initiative"), "crit")
		"ambush":
			_log(DataRegistry.t("combat.ambush"), "taken")
	_present(start_events)
	_refresh_ui()
	if start_mode == "boss":
		await _boss_entrance()
	if core.ambush_pending:
		_enemy_turn()
	else:
		_start_turn()

## Entrada de jefe: primero solo su cartel (nombre y la barra de vida que se
## llena de a tramos, con el registro), y después entran el héroe y las
## acciones. Todo a saltos, como el resto de la UI.
func _boss_entrance() -> void:
	busy = true
	var rest: Array[Control] = [bottom, menu_panel]
	for c in rest:
		c.modulate.a = 0.0
	var max_hp := int(core.enemy.max_hp)
	enemy_bar.set_values(0, max_hp)
	enemy_hp_label.text = "0/%d" % max_hp
	enemy_box.modulate.a = 0.0
	var tw := create_tween()
	for a: float in [0.5, 1.0]:
		var alpha := a
		tw.tween_callback(func() -> void: enemy_box.modulate.a = alpha)
		tw.tween_interval(0.05)
	tw.tween_callback(func() -> void: SceneRouter.play_ui("open"))
	var steps := 12
	for i in range(1, steps + 1):
		var hp := roundi(max_hp * float(i) / steps)
		tw.tween_callback(func() -> void:
			enemy_bar.set_values(hp, max_hp)
			enemy_hp_label.text = "%d/%d" % [hp, max_hp])
		tw.tween_interval(0.05)
	tw.tween_interval(0.2)
	for a: float in [0.5, 1.0]:
		var alpha := a
		tw.tween_callback(func() -> void:
			for c in rest:
				c.modulate.a = alpha)
		tw.tween_interval(0.05)
	await tw.finished
	busy = false

func _bal(path: String, default: float) -> float:
	return DataRegistry.bal_f("combat." + path, default)

# --- UI ---------------------------------------------------------------------------------

func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_enemy()
	_build_hero_ui()
	_build_menu()
	float_layer = Control.new()
	float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(float_layer)
	_layout()
	get_viewport().size_changed.connect(_layout)

## Arriba al centro: nombre en gótica, [calavera] barra ancha [rango], el HP
## en cifras bajo el extremo derecho de la barra y los estados debajo.
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
	# Estados: [ícono] cifra, centrados bajo la barra.
	status_row = HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 12)
	status_row.custom_minimum_size.y = UIStyle.ICON_SIZE
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_box.add_child(status_row)

## Abajo a la izquierda: la tarjeta del héroe + el registro (al lado o
## encima, según el ancho; ver _layout).
func _build_hero_ui() -> void:
	bottom = BoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", GAP)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bottom)
	hero_card = HeroCard.new(hero_data)
	bottom.add_child(hero_card)

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
	root.add_child(menu_panel)
	_fit_menu()
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

## Reparte el ancho: la tarjeta y el registro al lado si entra sin pisar las
## acciones; si no, el registro sube encima de la tarjeta.
func _layout() -> void:
	if root == null or not is_instance_valid(bottom):
		return
	var vp := root.get_viewport_rect().size
	var avail := vp.x - 2.0 * EDGE - ACTIONS_W - GAP
	_layout_enemy(vp, avail)
	var card_w := minf(CARD_W, avail)
	hero_card.custom_minimum_size.x = card_w
	var inline := avail - card_w - GAP >= LOG_MIN_W
	bottom.vertical = not inline
	if inline:
		bottom.move_child(log_panel, 1)
		log_panel.custom_minimum_size = Vector2(minf(LOG_W, avail - card_w - GAP), 0)
		log_panel.size_flags_vertical = Control.SIZE_FILL
		log_panel.size_flags_horizontal = Control.SIZE_FILL
	else:
		bottom.move_child(log_panel, 0)
		log_panel.custom_minimum_size = Vector2(minf(avail, 560.0), 100)
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

## Ventana ancha: el enemigo arriba al centro con la barra de 600 px. Angosta
## (escala de UI grande): ocupa el ancho a la izquierda de las acciones.
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

func _refresh_ui() -> void:
	enemy_bar.animate_to(maxi(int(core.enemy.hp), 0), int(core.enemy.max_hp))
	enemy_hp_label.text = "%d/%d" % [maxi(int(core.enemy.hp), 0), int(core.enemy.max_hp)]
	hero_card.refresh(core.hero, core.shield, core.defending, not busy and not finished)
	_refresh_statuses()

## Fila de estados del enemigo (se rearma solo si cambió).
func _refresh_statuses() -> void:
	var list := core.enemy_statuses() if not finished else []
	var key := str(list)
	if key == _status_key:
		return
	_status_key = key
	for c in status_row.get_children():
		status_row.remove_child(c)
		c.queue_free()
	for st: Dictionary in list:
		var id := String(st.id)
		var spec: Array = STATUS_ICONS[id]
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 2)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_child(UIIcon.make(String(spec[0]), String(spec[1])))
		var txt := DataRegistry.t("combat.status_carga") if id == "carga" else (DataRegistry.t("combat.status_pct", [int(st.value)]) if id == "marca" else str(int(st.value)))
		var l := UILabel.make(txt, "NumSmallLabel")
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.add_theme_color_override("font_color", UIStyle.DANGER if id == "carga" else UIStyle.TEXT)
		chip.add_child(l)
		UITooltip.attach(chip, DataRegistry.t("combat.status." + id, [int(st.value)]) if id != "carga" else DataRegistry.t("combat.status.carga", [String(enemy_data.ability_name)]))
		status_row.add_child(chip)

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

## Muestra los eventos de CombatCore en orden: registro, números que flotan,
## destellos y la señal de golpe al enemigo (para animarlo).
func _present(events: Array) -> void:
	for ev: Dictionary in events:
		if ev.has("log"):
			_log(String(ev.log), String(ev.get("tone", "info")))
		if ev.has("enemy_dmg"):
			var n := int(ev.enemy_dmg)
			var crit := bool(ev.get("crit", false))
			enemy_hit.emit(n)
			_flash(enemy_box, UIStyle.DANGER)
			var color := UIStyle.ACCENT if crit else (UIStyle.HP if bool(ev.get("bleed", false)) else Color.TRANSPARENT)
			_float_number(("-%d!" if crit else "-%d") % n, _enemy_float_pos(), "DamageLabel", color)
			SceneRouter.play_ui("click")
		if ev.has("hero_dmg"):
			var d := int(ev.hero_dmg)
			_float_number("-%d" % d, _hero_float_pos(), "DamageLabel")
			if int(ev.get("absorbed", 0)) > 0:
				_float_number("-%d" % int(ev.absorbed), _hero_float_pos() + Vector2(-56, 0), "DamageLabel", UIStyle.SOUL_LIGHT)
			if d > 0:
				_flash(hero_card, UIStyle.DANGER)
		if ev.has("heal"):
			_float_number("+%d" % int(ev.heal), _hero_float_pos() + Vector2(40, 0), "HealLabel")
		if ev.has("shield"):
			_float_number("+%d" % int(ev.shield), _hero_float_pos() + Vector2(-40, 0), "HealLabel", UIStyle.SOUL_LIGHT)
		if ev.has("coins"):
			_float_number("+%d" % int(ev.coins), _enemy_float_pos() + Vector2(0, 36), "HealLabel", UIStyle.COIN)

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

func _hero_float_pos() -> Vector2:
	var r := hero_card.get_global_rect()
	return Vector2(r.position.x + r.size.x * 0.55, r.position.y - 52.0)

## Destello de un cuadro (por pasos, sin fundido).
func _flash(control: Control, color: Color) -> void:
	control.modulate = color
	var tw := control.create_tween()
	tw.tween_interval(STEP * 2.0)
	tw.tween_callback(func() -> void: control.modulate = Color.WHITE)

# --- Menús de acción ---------------------------------------------------------------------

## entries: [{text, on, disabled?, tip?, icon? (id del kit), icon_ramp?,
## picture? (Texture2D), value? (cifra a la derecha), value_color?}]. Con
## with_back es un submenú: muestra la miga «ACCIONES › TÍTULO» y un botón
## Volver al final.
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

## Botón de piedra con ícono del kit (bronce → vela con el foco, o la rampa
## propia de una afinidad; apagado si está deshabilitado), retrato de objeto
## o cifra a la derecha.
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
		var own := String(e.get("icon_ramp", ""))
		var rest_ramp := own if own != "" else "bronce"
		var focus_ramp := own if own != "" else "vela"
		b.icon = UIIcon.texture_for(icon_id, "apagado" if b.disabled else rest_ramp)
		b.add_theme_color_override("icon_disabled_color", Color.WHITE)
		if not b.disabled and focus_ramp != rest_ramp:
			b.focus_entered.connect(func() -> void: b.icon = UIIcon.texture_for(icon_id, focus_ramp))
			b.focus_exited.connect(func() -> void: b.icon = UIIcon.texture_for(icon_id, rest_ramp))
	elif picture is Texture2D:
		b.icon = picture
	var value := String(e.get("value", ""))
	if value != "":
		var v := UILabel.make(value, "NumSmallLabel")
		var vc: Color = e.get("value_color", UIStyle.DANGER)
		v.add_theme_color_override("font_color", UIStyle.TEXT_OFF if b.disabled else vc)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		v.offset_left = -60
		v.offset_right = -12
		b.add_child(v)
		# Que el nombre no se monte sobre la cifra.
		var font := b.get_theme_font("font")
		var text_w := font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
		b.custom_minimum_size.x = ceilf(text_w + 24.0 + 12.0 + 32.0 + v.get_minimum_size().x)
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
	var has_abilities := core.soul_count() > 0
	var n_ready := 0
	for i in core.soul_count():
		if core.ability_ready(i):
			n_ready += 1
	var usable := _combat_items()
	var is_boss := String(enemy_data.kind) == RunRules.BOSS
	var ability_tip := DataRegistry.t("combat.ability_none")
	if has_abilities:
		ability_tip = DataRegistry.t("combat.ability_tip", [n_ready, core.soul_count()])
	_show_menu(DataRegistry.t("combat.actions"), [
		{"text": DataRegistry.t("combat.attack"), "on": _on_attack, "icon": "atacar", "tip": DataRegistry.t("combat.attack_tip", [int(core.hero.atk)])},
		{"text": DataRegistry.t("combat.ability"), "on": _show_abilities, "icon": "habilidad", "disabled": not has_abilities,
			"tip": ability_tip, "value": "%d/%d" % [n_ready, core.soul_count()] if has_abilities else "", "value_color": UIStyle.SOUL},
		{"text": DataRegistry.t("combat.defend"), "on": _on_defend, "icon": "stat_def",
			"tip": DataRegistry.t("combat.defend_tip_charge") if core.enemy_special_next() else DataRegistry.t("combat.defend_tip")},
		{"text": DataRegistry.t("combat.item"), "on": _show_items, "icon": "objeto", "disabled": usable.is_empty(),
			"tip": DataRegistry.t("combat.item_tip") if not usable.is_empty() else DataRegistry.t("combat.item_none")},
		{"text": DataRegistry.t("combat.flee_pct", [UIFormat.pct(flee_chance)]) if not is_boss else DataRegistry.t("combat.flee"),
			"on": _on_flee, "icon": "huir", "disabled": is_boss,
			"tip": DataRegistry.t("combat.flee_boss") if is_boss else DataRegistry.t("combat.flee_tip")},
	])

## Turno del enemigo: los comandos quedan a la vista pero apagados, con la
## miga «TURNO ENEMIGO» en rojo.
func _show_waiting() -> void:
	_menu_level = "wait"
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

## Una fila por alma: [afinidad] nombre de la activa ······ daño. Las que se
## están recargando quedan apagadas con los turnos que faltan.
func _show_abilities() -> void:
	var entries: Array = []
	for i in core.soul_count():
		var a := core.active_of(i)
		var soul: Dictionary = core.hero.souls[i]
		var afs: Array = soul.get("afinidades", [])
		var af := DataRegistry.get_affinity(String(afs[0]) if not afs.is_empty() else "")
		var is_ready := core.ability_ready(i)
		var recharge := SoulEffects.recharge_text(a, core, i)
		var desc := SoulEffects.active_text(a, core, i) + "\n" + recharge.left(1).to_upper() + recharge.substr(1)
		var value := ""
		var value_color := UIStyle.DANGER
		if not is_ready:
			value = DataRegistry.t("combat.cooldown_value", [core.cooldowns[i]])
			desc = DataRegistry.t("combat.ability_cooldown", [core.cooldowns[i]]) + "\n" + desc
		elif String(a.tipo) == "escudo":
			value = "+%d" % core.ability_shield(i)
			value_color = UIStyle.SOUL
		elif String(a.tipo) == "multigolpe":
			value = "%d×%d" % [core.ability_hits(i), core.ability_hit(i)]
		else:
			value = str(core.ability_hit(i))
		var idx := i
		entries.append({"text": String(a.name), "on": func() -> void: _on_ability(idx), "disabled": not is_ready,
			"tip": desc, "value": value, "value_color": value_color,
			"icon": String(af.get("icono", "habilidad")), "icon_ramp": String(af.get("rampa", ""))})
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
		var disabled: bool = (it.efecto.tipo == "huida_garantizada" and String(enemy_data.kind) == RunRules.BOSS) \
			or (it.efecto.tipo == "curar" and int(core.hero.hp) >= int(core.hero.max_hp))
		entries.append({"text": String(it.nombre), "on": func() -> void: _on_item(idx), "disabled": disabled,
			"tip": String(it.descripcion), "picture": UIPortrait.item_texture(inventory[i])})
	_show_menu(DataRegistry.t("combat.item"), entries, true)

# --- Turnos --------------------------------------------------------------------------------

func _start_turn() -> void:
	if finished:
		return
	if core.hero_dead():
		_finish(false)
		return
	busy = false
	_present(core.begin_hero_turn())
	_refresh_ui()
	_show_actions()

## Después de la acción del héroe: gana, pierde el turno el enemigo (ronda
## sorpresa) o le toca a él.
func _end_hero_turn() -> void:
	busy = true
	_refresh_ui()
	match core.after_hero_action():
		"victory":
			_finish(true)
		"free_turn":
			_log(DataRegistry.t("combat.enemy_stunned", [core.enemy.name]))
			await get_tree().create_timer(_bal("enemy_turn_delay", 0.35)).timeout
			_start_turn()
		_:
			await get_tree().create_timer(_bal("enemy_turn_delay", 0.35)).timeout
			_enemy_turn()

func _on_attack() -> void:
	if busy:
		return
	busy = true
	_present(core.attack())
	_end_hero_turn()

func _on_ability(i: int) -> void:
	if busy or not core.ability_ready(i):
		return
	busy = true
	SceneRouter.play_ui("soul")
	_present(core.ability(i))
	_end_hero_turn()

func _on_defend() -> void:
	if busy:
		return
	busy = true
	_present(core.defend())
	_end_hero_turn()

func _on_flee() -> void:
	if busy:
		return
	busy = true
	if rng.randf() < flee_chance:
		_log(DataRegistry.t("combat.log_flee_ok"))
		_finish_fled()
	else:
		_log(DataRegistry.t("combat.log_flee_fail"), "taken")
		_end_hero_turn()

func _on_item(index: int) -> void:
	if busy or index >= inventory.size():
		return
	var it := DataRegistry.get_item(inventory[index])
	match String(it.efecto.tipo):
		"curar":
			busy = true
			var item_name := String(it.nombre)
			var amount := int(it.efecto.valor)
			_consume(index)
			SceneRouter.play_ui("item")
			_present(core.heal_hero(amount, item_name))
			_end_hero_turn()
		"huida_garantizada":
			busy = true
			_consume(index)
			_log(DataRegistry.t("combat.log_smoke"))
			_finish_fled()

func _consume(index: int) -> void:
	items_used.append(inventory[index])
	inventory.remove_at(index)

func _enemy_turn() -> void:
	if finished:
		return
	busy = true
	_show_waiting()
	# Sangrado: le hace daño al empezar su turno (puede matarlo).
	var bleed := core.enemy_turn_start()
	if not bleed.is_empty():
		_present(bleed)
		_refresh_ui()
		if core.enemy_dead():
			await get_tree().create_timer(0.3).timeout
			_finish(true)
			return
		await get_tree().create_timer(0.25).timeout
		if finished:
			return
	var intent := core.enemy_intent()
	if intent != "stunned":
		enemy_acting.emit("ability" if intent == "special" else "attack")
		var windup := _bal("enemy_attack_windup", 0.3)
		if windup > 0.0:
			await get_tree().create_timer(windup).timeout
			if finished:
				return
	_present(core.enemy_act())
	_refresh_ui()
	if core.enemy_dead():
		_finish(true)
		return
	if core.hero_dead():
		_finish(false)
		return
	await get_tree().create_timer(0.15).timeout
	_start_turn()

# --- Fin de combate y flujo de alma -----------------------------------------------------

func _result(soul_pick: Dictionary = {}) -> Dictionary:
	return {"hp": {String(hero_data.id): maxi(int(core.hero.hp), 0)}, "items_used": items_used.duplicate(),
		"coins": core.bonus_coins, "soul_pick": soul_pick}

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

## Resumen de victoria: libro de cuentas con monedas y EXP, subida de nivel,
## primera muerte de la especie (con sello) y el aviso del alma.
func _show_victory() -> void:
	var d := _open_dialog(DataRegistry.t("combat.victory_title"), "", "normal", "reward")
	d.title_label.set_colors(UIStyle.BRONZE_LIGHT, UIStyle.CAPITAL)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	rows.custom_minimum_size.x = 480
	rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	d.add_content(rows)
	var coins := int(reward_preview.coins) + core.bonus_coins
	rows.add_child(UILedgerRow.new(DataRegistry.t("combat.ledger_coins"), DataRegistry.t("combat.ledger_value", [coins]), "CoinLabel", "monedas", "moneda"))
	if int(reward_preview.get("xp", 0)) > 0:
		var xp_row := UILedgerRow.new(DataRegistry.t("combat.ledger_xp"), DataRegistry.t("combat.ledger_value", [int(reward_preview.xp)]), "NumLabel", "exp", "amatista")
		xp_row.value_label.add_theme_color_override("font_color", UIStyle.XP)
		UITooltip.attach(xp_row, DataRegistry.t("combat.xp_gained", [int(reward_preview.xp)]))
		rows.add_child(xp_row)
		var lv := int(hero_data.get("level", 1))
		var lv_win := int(hero_data.get("level_win", lv))
		if lv_win > lv:
			rows.add_child(_note_row(UIIcon.make("exp", "amatista"), DataRegistry.t("combat.level_up_line", [hero_data.name, lv_win]), UIStyle.XP))
			var slots := int(hero_data.get("soul_capacity_win", 0)) - int(hero_data.get("soul_capacity", 0))
			if slots > 0:
				rows.add_child(_note_row(UIIcon.make("almas", "alma"), DataRegistry.t("combat.slot_up_line", [int(hero_data.soul_capacity_win)]), UIStyle.SOUL))
	if reward_preview.get("first_kill", false):
		rows.add_child(_note_row(UISprite.new("seal_mini"), DataRegistry.t("combat.first_kill", [String(reward_preview.get("species_name", enemy_data.name)), UIFormat.coins(int(reward_preview.first_kill_bonus))]), UIStyle.ACCENT))
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
	for c: Control in [enemy_box, bottom, menu_panel]:
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

func _hero_souls() -> Array:
	return hero_data.get("souls", [])

## Lugar para almas con el que queda al ganar (si sube a un nivel impar,
## tiene un espacio más).
func _capacity_after_win() -> int:
	return int(hero_data.get("soul_capacity_win", hero_data.get("soul_capacity", 1)))

## Núcleo de combate con el héroe y otra lista de almas: para describir una
## activa con las cifras que tendría (ataque, ESP y sinergias de esa lista).
func _preview_core(souls: Array) -> CombatCore:
	var c := CombatCore.new(rng)
	var h := hero_data.duplicate()
	h["souls"] = souls
	c.setup(h, {"name": "", "hp": 1, "atk": 0})
	return c

## Revelación del alma: carta azul con la tarjeta del alma (cifras de este
## héroe), motas que suben, lo que activaría (afinidades, pactos) y Tomarla /
## Dejarla; sin lugar, Reemplazar una.
func _reveal_soul() -> void:
	var souls := _hero_souls()
	var full := souls.size() >= _capacity_after_win()
	var d := _open_dialog(DataRegistry.t("combat.soul_title"), "", "soul", "soul", 760)
	var after := souls.duplicate()
	after.append(soul_drop)
	var card := UISoulCard.new(soul_drop, false, _preview_core(after), after.size() - 1)
	card.custom_minimum_size.x = 520
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_child(UISoulMotes.new())
	d.add_content(card)
	_pop_in(card)
	var gains := UISynergyDiff.new(SoulBuild.diff_if_added(souls, soul_drop) if not full else {}, String(soul_drop.get("id", "")), souls)
	gains.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	d.add_content(gains)
	var cap := UILabel.make(DataRegistry.t("combat.soul_slots", [souls.size(), _capacity_after_win()]), "DimLabel")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.add_content(cap)

	var leave := d.add_button(DataRegistry.t("combat.soul_leave"), func() -> void: combat_ended.emit("victory", _result()))
	var take: UIButton
	if full:
		take = d.add_button(DataRegistry.t("combat.soul_replace"), _choose_replacement)
		take.icon = UIIcon.kit_texture("soul_empty")
	else:
		take = d.add_button(DataRegistry.t("combat.soul_take"), func() -> void:
			SceneRouter.play_ui("soul")
			combat_ended.emit("victory", _result({"member_id": String(hero_data.id), "soul": soul_drop, "replace_index": -1})))
		take.icon = UIIcon.kit_texture("soul_full")
	leave.focus_neighbor_right = leave.get_path_to(take)
	take.call_deferred("grab_focus")

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

## Sin lugar: reemplazar una de las almas (se pierde) o dejar la nueva. Cada
## fila dice qué se gana y qué se pierde con ese cambio. Esc vuelve.
func _choose_replacement() -> void:
	var d := _open_dialog(DataRegistry.t("combat.replace_title", [hero_data.get("name", "")]), DataRegistry.t("combat.replace_text"), "danger", "", 820)
	d.on_cancel = _reveal_soul
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	var replace_buttons: Array = []
	var souls := _hero_souls()
	for i in souls.size():
		var old: Dictionary = souls[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", GAP)
		list.add_child(row)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var card := UISoulCard.new(old, true, _preview_core(souls), i)
		col.add_child(card)
		var diff := UISynergyDiff.new(SoulBuild.diff_if_added(souls, soul_drop, i), "", [])
		col.add_child(diff)
		var idx := i
		var on_replace := func() -> void:
			SceneRouter.play_ui("soul")
			combat_ended.emit("victory", _result({"member_id": String(hero_data.id), "soul": soul_drop, "replace_index": idx}))
		var b := UIButton.make(DataRegistry.t("combat.replace_short"), on_replace, "DangerButton")
		b.custom_minimum_size.x = 160
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UITooltip.attach(b, DataRegistry.t("combat.replace_btn", [(old.get("active", {}) as Dictionary).get("name", "")]))
		row.add_child(b)
		replace_buttons.append(b)
	# La lista se desplaza (la carta no se sale de la ventana).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size.y = 320
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	d.add_content(scroll)
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
	core.enemy["hp"] = 0
	_finish(true)

func debug_lose() -> void:
	if finished:
		return
	core.hero["hp"] = 0
	_finish(false)


## Tarjeta del héroe: [retrato] Nombre [guardia] [escudo n] ······ 20/30
##                                ▮▮▮▮▮▮▮▮▮ HP ▮▮▮▮▮▮▮▮▮
##                                🔥🔥🔥▯ 3/4 almas
##                         NV 3 ▮▮▮▮▮▮ EXP ▮▮▮▮▮▮▮▮▮▮▮▮
## En su turno: placa encendida, retrato con marco de brasa y la llama del
## cursor sobre el borde. Caído: retrato apagado con calavera.
class HeroCard extends PanelContainer:
	var portrait: UIPortrait
	var name_label: Label
	var guard: UIIcon
	var shield_icon: UIIcon
	var shield_label: Label
	var hp_label: Label
	var bar: UIStatBar
	var souls: UISoulSlots
	var soul_label: Label
	var level_label: Label
	var xp_bar: UIStatBar
	var flame: UIFlameCursor
	var _data: Dictionary

	func _init(m: Dictionary) -> void:
		_data = m
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
		shield_icon = UIIcon.make("escudo", "vela")
		shield_icon.visible = false
		head.add_child(shield_icon)
		shield_label = UILabel.make("", "NumSmallLabel")
		shield_label.add_theme_color_override("font_color", UIStyle.SOUL_LIGHT)
		shield_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		shield_label.visible = false
		head.add_child(shield_label)
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
		var list: Array = m.get("souls", [])
		souls = UISoulSlots.new(list.size(), maxi(int(m.get("soul_capacity", 1)), list.size()))
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

	func refresh(h: Dictionary, shield: int, defending: bool, acting: bool) -> void:
		var hp := int(h.hp)
		var max_hp := int(h.max_hp)
		var fallen := hp <= 0
		acting = acting and not fallen
		bar.animate_to(maxi(hp, 0), max_hp)
		hp_label.text = "%d/%d" % [maxi(hp, 0), max_hp]
		theme_type_variation = "CardFocus" if acting else "Card"
		portrait.set_active(acting)
		portrait.set_fallen(fallen)
		flame.visible = acting
		guard.visible = defending and not fallen
		shield_icon.visible = shield > 0 and not fallen
		shield_label.visible = shield_icon.visible
		shield_label.text = str(shield)
		var list: Array = h.get("souls", [])
		if fallen:
			soul_label.text = DataRegistry.t("combat.fallen")
			soul_label.add_theme_color_override("font_color", UIStyle.TEXT_OFF)
		elif list.is_empty():
			soul_label.text = DataRegistry.t("combat.no_soul")
			soul_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		else:
			soul_label.text = DataRegistry.t("combat.souls_count", [list.size()])
			soul_label.add_theme_color_override("font_color", UIStyle.SOUL)
		var level := int(_data.get("level", 1))
		level_label.text = DataRegistry.t("hud.level", [level]).to_upper()
		var need := RunRules.xp_to_next(level)
		xp_bar.set_values(int(_data.get("xp", 0)) if need > 0 else 1, need if need > 0 else 1)
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
