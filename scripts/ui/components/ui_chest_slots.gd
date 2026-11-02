class_name UIChestSlots
extends Control
## La tragaperras del cofre. Al abrirlo giran tres rodillos con íconos del
## kit y se clavan uno a uno en lo que ya salió (GameState.open_chest decide
## antes de girar, como una de verdad). Si los dos primeros coinciden, el
## tercero frena despacio con la línea latiendo (la tensión); tres iguales =
## premio: la línea destella, llueven monedas y aparece qué ganaste. Después
## el botín: las monedas suben de a poco (con el ×2 / ×3 a la vista si tocó)
## y salen los objetos. Enter o Esc: mientras gira, para todo; con el
## resultado, cierra (si no, se cierra sola). Todo a saltos; colores de
## UIStyle. Destellos y sacudones (Opciones) apaga el destello del premio.

signal finished

## Símbolo → [ícono del kit, rampa]. La calavera es el relleno (nunca paga).
const SYMBOLS := {
	"moneda": ["monedas", "moneda"],
	"objeto": ["objeto", "vela"],
	"alma": ["almas", "alma"],
	"trofeo": ["victoria", "moneda"],
	"calavera": ["muerte", "bronce"],
}
const STEP := 0.066
## Celda del rodillo, escala de los íconos (32 px a ×3) y tamaño del rodillo.
const CELL := 104
const ICON_SCALE := 3
const REEL_W := 124
const REEL_H := 200
## Velocidad de giro (símbolos por segundo) de cada rodillo.
const SPEEDS: Array[float] = [13.0, 14.5, 16.0]
## Se cierra sola después de mostrar el botín.
const AUTO_CLOSE := 4.0

var result: Dictionary
var screen_fx := true
var stage := "spin" # spin | result | closing
var _reels: Array[Reel] = []
var _stopped := 0
var _skip := false
var _seq: Tween
var _pulse: Tween
var _panel: PanelContainer
var _headline: Label
var _prize_label: Label
var _coins_label: Label
var _mult_label: Label
var _items_row: HBoxContainer
var _loot: HBoxContainer
var _hint: Label

## r = GameState.open_chest(): {coins_base, coins, items, left, reels, prize, streak}.
func _init(r: Dictionary = {}) -> void:
	result = r
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_fx = bool(MetaState.settings.get("combat_fx", true))

func _ready() -> void:
	_build()
	_pop_in()
	var seed_base := randi()
	for i in 3:
		_reels[i].stopped.connect(_on_stopped.bind(i))
		_reels[i].seed_ = seed_base + i * 101
		_reels[i].spin(SPEEDS[i])
	_reels[0].ticks = true
	_seq = create_tween()
	_seq.tween_interval(0.7)
	_seq.tween_callback(_land.bind(0, 0.5))

# --- Armado --------------------------------------------------------------------------------

func _build() -> void:
	# Un poco arriba del centro: abajo queda a la vista el cofre abierto.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -150
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = 540
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var title := UIGothicLabel.new(DataRegistry.t("chest.title"), "GothicTitle", UIStyle.TEXT, UIStyle.CAPITAL)
	title.align = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for i in 3:
		var reel := Reel.new()
		# Las flechas de la línea de pago, en los rodillos de las puntas.
		reel.arrow_left = i == 0
		reel.arrow_right = i == 2
		row.add_child(reel)
		_reels.append(reel)
	# Lo que pasó: «¡Premio!» o «¡Casi!», y qué se ganó (alto fijo: la placa no salta).
	_headline = UILabel.make("", "HeadLabel")
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_headline.add_theme_font_size_override("font_size", UIStyle.FONT_HEAD * 2)
	_headline.custom_minimum_size.y = 50
	_headline.add_theme_color_override("font_shadow_color", UIStyle.TINTA)
	_headline.add_theme_constant_override("shadow_offset_x", UIStyle.PIXEL_SCALE * 2)
	_headline.add_theme_constant_override("shadow_offset_y", UIStyle.PIXEL_SCALE * 2)
	box.add_child(_headline)
	_prize_label = UILabel.make("", "AccentLabel", true)
	_prize_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prize_label.custom_minimum_size = Vector2(500, 26)
	box.add_child(_prize_label)
	box.add_child(UIDivider.new(320))
	# Botín: [monedas] 0 → N (×2), y los objetos.
	var loot := HBoxContainer.new()
	loot.alignment = BoxContainer.ALIGNMENT_CENTER
	loot.add_theme_constant_override("separation", 10)
	loot.custom_minimum_size.y = 64
	# Oculto (pero ocupando su lugar) hasta que se cuenta el botín.
	loot.modulate.a = 0.0
	box.add_child(loot)
	_loot = loot
	loot.add_child(UIIcon.make("monedas", "moneda"))
	_coins_label = UILabel.make("", "CoinBigLabel")
	_coins_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	loot.add_child(_coins_label)
	_mult_label = UILabel.make("", "NumLabel")
	_mult_label.add_theme_color_override("font_color", UIStyle.ACCENT)
	_mult_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	loot.add_child(_mult_label)
	_items_row = HBoxContainer.new()
	_items_row.add_theme_constant_override("separation", 10)
	loot.add_child(_items_row)
	_hint = UILabel.make(DataRegistry.t("chest.hint_spin"), "DetailLabel")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)

func _pop_in() -> void:
	_panel.modulate.a = 0.0
	SceneRouter.play_ui("open")
	var tw := _panel.create_tween()
	for a: float in [0.5, 1.0]:
		var alpha := a
		tw.tween_callback(func() -> void: _panel.modulate.a = alpha)
		tw.tween_interval(STEP)

# --- Giro ----------------------------------------------------------------------------------

func _reel_symbol(i: int) -> String:
	var reels: Array = result.get("reels", ["calavera", "calavera", "calavera"])
	return String(reels[i])

func _land(i: int, dur: float) -> void:
	if _reels[i].spinning and not _reels[i].landing:
		_reels[i].land(_reel_symbol(i), dur)

## Un rodillo se clavó: suena, el siguiente pasa a hacer tic y se programa
## su parada; con los dos primeros iguales, el tercero frena despacio.
func _on_stopped(i: int) -> void:
	SceneRouter.play_ui("slot_stop")
	_reels[i].ticks = false
	_stopped += 1
	if _stopped >= 3:
		_show_result()
		return
	if _skip:
		return
	var next := i + 1
	_reels[next].ticks = true
	_seq = create_tween()
	if next == 2 and _reel_symbol(0) == _reel_symbol(1):
		# Tensión: la línea de los dos iguales late y el tercero frena.
		_pulse_line([0, 1], 0.14)
		_seq.tween_property(_reels[2], "speed", 4.5, 0.9).set_ease(Tween.EASE_OUT)
		_seq.tween_interval(0.5)
		_seq.tween_callback(_land.bind(2, 0.9))
	else:
		_seq.tween_interval(0.35)
		_seq.tween_callback(_land.bind(next, 0.5))

## Enter / Esc: mientras gira, para todo ya; con el resultado, cierra.
func advance() -> void:
	match stage:
		"spin":
			if _skip:
				return
			_skip = true
			if _seq:
				_seq.kill()
			var k := 0
			for i in 3:
				if _reels[i].spinning and not _reels[i].landing:
					_land(i, 0.16 + 0.1 * k)
					k += 1
		"result":
			close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		advance()

# --- Resultado -----------------------------------------------------------------------------

func _show_result() -> void:
	stage = "result"
	_hint.text = DataRegistry.t("chest.hint_done")
	if _pulse:
		_pulse.kill()
	for r in _reels:
		r.glow = false
		r.queue_redraw()
	var prize := String(result.get("prize", ""))
	var delay := 0.15
	if prize != "":
		delay = 0.7
		SceneRouter.play_ui("slot_win")
		_pulse_line([0, 1, 2], 0.1, 10)
		_headline.text = DataRegistry.t("chest.prize_title")
		_headline.add_theme_color_override("font_color", UIStyle.ACCENT)
		_pop(_headline)
		_prize_label.text = _prize_text(prize)
		for r in _reels:
			var c := r.get_global_rect().get_center()
			add_child(UIBurst.make(c, [UIStyle.COIN, UIStyle.MONEDA_LUZ, UIStyle.VELA_BLANCA], 22, 380.0))
		if screen_fx:
			_flash_panel()
	elif _reel_symbol(0) == _reel_symbol(1):
		SceneRouter.play_ui("slot_near")
		_headline.text = DataRegistry.t("chest.near")
		_headline.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		_pop(_headline)
		_reels[2].dim = true
		_reels[2].queue_redraw()
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(_count_loot)

static func _prize_text(prize: String) -> String:
	match prize:
		"moneda":
			return DataRegistry.t("chest.prize.moneda", [DataRegistry.bal_i("chest_slots.monedas_mult", 2)])
		"trofeo":
			return DataRegistry.t("chest.prize.trofeo", [DataRegistry.bal_i("chest_slots.trofeo_mult", 3)])
		"alma":
			return DataRegistry.t("chest.prize.alma", [DataRegistry.bal_i("chest_slots.racha_alma", 4)])
	return DataRegistry.t("chest.prize." + prize)

## Las monedas suben a saltos hasta lo de siempre; si el premio multiplica,
## aparece el «×2» y suben otra vez hasta el total. Después, los objetos.
func _count_loot() -> void:
	var base := int(result.get("coins_base", 0))
	var total := int(result.get("coins", base))
	_loot.modulate.a = 1.0
	var tw := create_tween()
	_count(tw, 0, base, 10)
	if total > base:
		tw.tween_interval(0.2)
		tw.tween_callback(func() -> void:
			_mult_label.text = "×%d" % roundi(float(total) / maxf(base, 1.0))
			_pop(_mult_label)
			SceneRouter.play_ui("reward"))
		tw.tween_interval(0.3)
		_count(tw, base, total, 8)
	var items: Array = result.get("items", [])
	var left: Array = result.get("left", [])
	for id: Variant in items:
		var item_id := String(id)
		tw.tween_interval(0.2)
		tw.tween_callback(func() -> void: _add_item(item_id, left.has(item_id)))
	tw.tween_interval(0.2)
	tw.tween_callback(func() -> void:
		var auto := create_tween()
		auto.tween_interval(AUTO_CLOSE)
		auto.tween_callback(close))

func _count(tw: Tween, from: int, to: int, steps: int) -> void:
	for k in range(1, steps + 1):
		var v := from + roundi(float(to - from) * k / steps)
		tw.tween_callback(func() -> void:
			_coins_label.text = "+%d" % v
			SceneRouter.play_ui("coin"))
		tw.tween_interval(0.05)

## Un objeto del botín: su retrato y su nombre (si no entró, en gris y «al suelo»).
func _add_item(id: String, on_floor: bool) -> void:
	var it := DataRegistry.get_item(id)
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 6)
	var pic := TextureRect.new()
	pic.texture = UIPortrait.item_texture(id)
	if pic.texture == null:
		pic.texture = UIIcon.texture_for("objeto", "vela")
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if on_floor:
		pic.modulate = UIStyle.TEXT_OFF
	cell.add_child(pic)
	var name_label := UILabel.make(DataRegistry.t("chest.item_floor", [it.nombre]) if on_floor else String(it.nombre), "DetailLabel" if on_floor else "")
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_child(name_label)
	_items_row.add_child(cell)
	SceneRouter.play_ui("item")

func close() -> void:
	if stage == "closing":
		return
	stage = "closing"
	SceneRouter.play_ui("close")
	var tw := _panel.create_tween()
	for a: float in [0.5, 0.0]:
		var alpha := a
		tw.tween_callback(func() -> void: _panel.modulate.a = alpha)
		tw.tween_interval(STEP)
	tw.tween_callback(func() -> void:
		finished.emit()
		queue_free())

# --- Efectos -------------------------------------------------------------------------------

## La línea de pago de esos rodillos se prende y se apaga (count veces; 0 =
## hasta que algo la corte).
func _pulse_line(which: Array[int], period: float, count := 0) -> void:
	if _pulse:
		_pulse.kill()
	_pulse = create_tween()
	if count <= 0:
		_pulse.set_loops()
	var on := true
	for k in (2 if count <= 0 else count):
		var lit := on
		_pulse.tween_callback(func() -> void:
			for i in which:
				_reels[i].glow = lit
				_reels[i].queue_redraw())
		_pulse.tween_interval(period)
		on = not on
	if count > 0:
		_pulse.tween_callback(func() -> void:
			for i in which:
				_reels[i].glow = true
				_reels[i].queue_redraw())

func _pop(c: Control) -> void:
	var tw := c.create_tween()
	for s: float in [1.5, 1.15, 1.0]:
		var sc := s
		tw.tween_callback(func() -> void:
			c.pivot_offset = (c.size / 2.0).round()
			c.scale = Vector2(sc, sc))
		tw.tween_interval(STEP)

func _flash_panel() -> void:
	var tw := _panel.create_tween()
	for k in 3:
		tw.tween_callback(func() -> void: _panel.modulate = UIStyle.VELA_BLANCA)
		tw.tween_interval(STEP)
		tw.tween_callback(func() -> void: _panel.modulate = Color.WHITE)
		tw.tween_interval(STEP)


## Un rodillo: una tira infinita de símbolos (los que no se fijan salen de
## la semilla) que baja a `speed` símbolos por segundo; `land` lo frena en
## un símbolo con el golpe de la traba (pasa un poco y vuelve). Dibujado a
## mano: hueco, la fila de la línea de pago (con flechas en las puntas), los
## íconos a ×3 (estela si va rápido) y sombras arriba y abajo (es un cilindro).
class Reel extends Control:
	signal stopped

	var pos := 0.0
	var speed := 0.0
	var spinning := false
	var landing := false
	var ticks := false
	## Línea de pago encendida (tensión, premio) o el símbolo apagado («casi»).
	var glow := false
	var dim := false
	var arrow_left := false
	var arrow_right := false
	var seed_ := 0
	var overrides := {}
	var _last := 0
	var _tw: Tween

	func _init() -> void:
		custom_minimum_size = Vector2(UIChestSlots.REEL_W, UIChestSlots.REEL_H)
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func symbol_at(i: int) -> String:
		if overrides.has(i):
			return String(overrides[i])
		var keys: Array = UIChestSlots.SYMBOLS.keys()
		return String(keys[posmod(hash(i * 7919 + seed_), keys.size())])

	func spin(p_speed: float) -> void:
		speed = p_speed
		spinning = true
		landing = false

	## Para en `symbol` en `dur` segundos.
	func land(symbol: String, dur: float) -> void:
		landing = true
		var ti := ceili(pos + maxf(speed, 3.0) * dur * 0.45)
		overrides[ti] = symbol
		if _tw:
			_tw.kill()
		_tw = create_tween()
		_tw.tween_property(self, "pos", float(ti), dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tw.tween_callback(func() -> void:
			pos = float(ti)
			spinning = false
			landing = false
			queue_redraw()
			stopped.emit())

	func _process(delta: float) -> void:
		if not spinning:
			return
		if not landing:
			pos += speed * delta
		var i := floori(pos)
		if i != _last:
			_last = i
			if ticks:
				SceneRouter.play_ui("slot_tick")
		queue_redraw()

	func _draw() -> void:
		var full := Rect2(Vector2.ZERO, size)
		draw_rect(full, UIStyle.HUNDIDO)
		var cell := float(UIChestSlots.CELL)
		var mid := floorf((size.y - cell) / 2.0)
		draw_rect(Rect2(0.0, mid, size.x, cell), UIStyle.PIEDRA_LUZ if glow else UIStyle.NICHO)
		var blur := spinning and not landing and speed > 8.0
		var base := floori(pos)
		for i in range(base - 2, base + 3):
			var spec: Array = UIChestSlots.SYMBOLS[symbol_at(i)]
			var tex := UIIcon.texture_for(String(spec[0]), String(spec[1]))
			if tex == null:
				continue
			var sz := tex.get_size() * float(UIChestSlots.ICON_SCALE)
			var y := roundf((mid + (pos - i) * cell) / UIStyle.PIXEL_SCALE) * UIStyle.PIXEL_SCALE
			var at := Vector2(floorf((size.x - sz.x) / 2.0), y + floorf((cell - sz.y) / 2.0))
			if blur:
				draw_texture_rect(tex, Rect2(at - Vector2(0.0, cell * 0.3), sz), false, _alpha(UIStyle.TEXT_DIM, 0.35))
			var on_line := i == roundi(pos) and not spinning
			draw_texture_rect(tex, Rect2(at, sz), false, UIStyle.TEXT_OFF if dim and on_line else Color.WHITE)
		# El rodillo es un cilindro: oscuro arriba y abajo.
		var band := mid / 2.0
		for k in 2:
			var a := 0.65 if k == 0 else 0.3
			draw_rect(Rect2(0.0, band * k, size.x, band), _alpha(UIStyle.TINTA, a))
			draw_rect(Rect2(0.0, size.y - band * (k + 1), size.x, band), _alpha(UIStyle.TINTA, a))
		var line := UIStyle.VELA if glow else UIStyle.BRONCE
		draw_rect(Rect2(1.0, mid, size.x - 2.0, cell), line, false, 2.0)
		var cy := mid + cell / 2.0
		if arrow_left:
			draw_colored_polygon(PackedVector2Array([Vector2(2, cy - 10), Vector2(12, cy), Vector2(2, cy + 10)]), line)
		if arrow_right:
			draw_colored_polygon(PackedVector2Array([Vector2(size.x - 2, cy - 10), Vector2(size.x - 12, cy), Vector2(size.x - 2, cy + 10)]), line)
		draw_rect(full, UIStyle.HIERRO, false, 2.0)

	static func _alpha(c: Color, a: float) -> Color:
		var out := c
		out.a = a
		return out
