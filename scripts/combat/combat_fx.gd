class_name CombatFx
extends Control
## Lo que hace que un golpe se SIENTA: números que saltan (los críticos, el
## doble y temblando), carteles (la activa que se usa, la sinergia que salta,
## «¡Crítico!», el combo), estallidos de píxeles, destellos de pantalla y la
## viñeta roja al recibir daño (que late con poca vida). Todo a saltos, como
## el resto de la UI; colores de UIStyle. CombatManager decide qué mostrar
## según los eventos de CombatCore; el sacudón de cámara y el hit-stop van
## por su señal `impact`.
## Opciones → «Destellos y sacudones» apaga destellos, viñeta y sacudón: los
## números, carteles y píxeles quedan.

const STEP := 0.066
## Alto de un cartel de sinergia y separación entre los apilados.
const PROC_H := 34

var screen_fx := true
## Dónde se apilan los carteles de sinergia (sobre la tarjeta del héroe).
var proc_anchor := Vector2(16, 400)
var _flash: ColorRect
var _vignette: TextureRect
var _low_hp := false
var _beat: Tween
var _vrng := RandomNumberGenerator.new()
var _procs: Array[Control] = []

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vrng.randomize()
	screen_fx = bool(MetaState.settings.get("combat_fx", true))
	_vignette = TextureRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.texture = _vignette_texture()
	_vignette.modulate.a = 0.0
	add_child(_vignette)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color.TRANSPARENT
	add_child(_flash)

## Viñeta: transparente al centro, sangre oscura en los bordes.
static func _vignette_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, _alpha(UIStyle.SANGRE_OSC, 0.0))
	g.set_offset(0, 0.62)
	g.set_color(1, _alpha(UIStyle.SANGRE_OSC, 0.9))
	g.set_offset(1, 1.0)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 160
	t.height = 90
	return t

static func _alpha(c: Color, a: float) -> Color:
	var out := c
	out.a = a
	return out

## Sombra dura de tinta (un píxel de arte por cada ~22 px de letra): se lee
## encima del sprite sin perder el borde del pixel art.
static func _shadow(l: Label, font_size: int) -> void:
	var off := UIStyle.PIXEL_SCALE * maxi(1, roundi(font_size / float(UIStyle.FONT_NUM_S * 2)))
	l.add_theme_color_override("font_shadow_color", UIStyle.TINTA)
	l.add_theme_constant_override("shadow_offset_x", off)
	l.add_theme_constant_override("shadow_offset_y", off)
	l.add_theme_constant_override("shadow_outline_size", 0)

static func _snap(p: Vector2) -> Vector2:
	return (p / UIStyle.PIXEL_SCALE).round() * UIStyle.PIXEL_SCALE

# --- Pantalla ------------------------------------------------------------------------------

## Destello de pantalla completa en dos pasos.
func flash(color: Color, strength := 0.3) -> void:
	if not screen_fx:
		return
	_flash.color = _alpha(color, strength)
	var tw := _flash.create_tween()
	tw.tween_interval(STEP)
	tw.tween_callback(func() -> void: _flash.color = _alpha(color, strength * 0.4))
	tw.tween_interval(STEP)
	tw.tween_callback(func() -> void: _flash.color = Color.TRANSPARENT)

## Golpe recibido: la viñeta roja entra de golpe y se va a pasos (si hay
## poca vida, vuelve al latido).
func hurt(strength := 1.0) -> void:
	if not screen_fx:
		return
	var tw := _vignette.create_tween()
	for a: float in [1.0, 0.7, 0.4]:
		var alpha := a * clampf(strength, 0.4, 1.0)
		tw.tween_callback(func() -> void: _vignette.modulate.a = alpha)
		tw.tween_interval(STEP * 1.5)
	tw.tween_callback(func() -> void:
		if not _low_hp:
			_vignette.modulate.a = 0.0)

## Con poca vida la viñeta late (dos golpes y una pausa, como un corazón).
func set_low_hp(on: bool) -> void:
	if on == _low_hp:
		return
	_low_hp = on
	if _beat:
		_beat.kill()
		_beat = null
	if not on or not screen_fx:
		_vignette.modulate.a = 0.0
		return
	_beat = _vignette.create_tween().set_loops()
	for a: float in [0.45, 0.25, 0.5, 0.18]:
		var alpha := a
		_beat.tween_callback(func() -> void: _vignette.modulate.a = alpha)
		_beat.tween_interval(STEP * 2.0)
	_beat.tween_interval(0.5)

## Un cuadro de la UI tiembla a saltos (la barra del enemigo, la tarjeta).
func jolt(c: Control, amount := 6.0) -> void:
	if not is_instance_valid(c):
		return
	var base := c.position
	var tw := c.create_tween()
	for k: float in [1.0, -0.6, 0.3]:
		var off := Vector2(amount * k, 0.0)
		tw.tween_callback(func() -> void: c.position = base + off)
		tw.tween_interval(STEP * 0.7)
	tw.tween_callback(func() -> void: c.position = base)

# --- Números y carteles --------------------------------------------------------------------

## Número que salta: aparece grande, se asienta y sube a saltos de 2 px.
## font_size: múltiplo de la grilla de Micro 5 (0 = el de la variación);
## big: crítico (salta más y tiembla).
func number(text: String, at: Vector2, variation: String, color := Color.TRANSPARENT, font_size := 0, big := false) -> void:
	var l := UILabel.make(text, variation)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)
	_shadow(l, font_size if font_size > 0 else UIStyle.FONT_NUM_L)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var sz := l.get_combined_minimum_size()
	var base := _snap(at - sz / 2.0)
	l.position = base
	l.pivot_offset = (sz / 2.0).round()
	var tw := l.create_tween()
	var pops: Array[float] = [1.4, 1.0]
	if big:
		pops = [1.7, 1.3, 1.0]
	for s: float in pops:
		var sc := s
		tw.tween_callback(func() -> void: l.scale = Vector2(sc, sc))
		tw.tween_interval(STEP)
	var steps := 10 if big else 8
	for i in steps:
		var y := -2.0 * (i + 1)
		var x := (2.0 if i % 2 == 0 else -2.0) if big and i < 4 else 0.0
		tw.tween_callback(func() -> void: l.position = base + Vector2(x, y))
		tw.tween_interval((0.7 if big else 0.5) / steps)
	tw.tween_callback(func() -> void: l.modulate.a = 0.5)
	tw.tween_interval(STEP * 2.0)
	tw.tween_callback(l.queue_free)

## Palabra sobre un número («¡Crítico!», «¡Ejecución!»): salta y se queda
## un momento.
func tag(text: String, at: Vector2, color: Color, big := false) -> void:
	var l := UILabel.make(text, "HeadLabel")
	l.add_theme_color_override("font_color", color)
	if big:
		l.add_theme_font_size_override("font_size", UIStyle.FONT_HEAD * 2)
	_shadow(l, UIStyle.FONT_HEAD * (2 if big else 1))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var sz := l.get_combined_minimum_size()
	l.position = _snap(at - sz / 2.0)
	l.pivot_offset = (sz / 2.0).round()
	var tw := l.create_tween()
	for s: float in [0.6, 1.25, 1.0]:
		var sc := s
		tw.tween_callback(func() -> void: l.scale = Vector2(sc, sc))
		tw.tween_interval(STEP)
	tw.tween_interval(0.55)
	tw.tween_callback(func() -> void: l.modulate.a = 0.5)
	tw.tween_interval(STEP * 2.0)
	tw.tween_callback(l.queue_free)

## Cartel de la activa que se usa: [ícono] Nombre, en el color de su
## afinidad, entra de costado, se queda y se va.
func ability_banner(title: String, icon: String, ramp: String, at_y: float) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "ToastPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	row.add_child(UIIcon.make(icon, ramp))
	var l := UILabel.make(title, "HeadLabel")
	l.add_theme_color_override("font_color", UIStyle.ramp_color(ramp))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	add_child(panel)
	var sz := panel.get_combined_minimum_size()
	var base := _snap(Vector2((size.x - sz.x) / 2.0, at_y))
	_slide(panel, base, Vector2(-32, 0), 1.0)

## Cartel de sinergia: [ícono] «Pacto: Hemorragia» o «Sangre · Herida
## abierta», sobre la tarjeta del héroe; varios se apilan.
func proc_banner(text: String, icon: String, ramp: String, color: Color) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "RibbonSmall"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	row.add_child(UIIcon.make(icon, ramp))
	var l := UILabel.make(text, "DetailLabel")
	l.add_theme_color_override("font_color", color)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	add_child(panel)
	_procs = _procs.filter(func(c: Control) -> bool: return is_instance_valid(c))
	var base := _snap(proc_anchor - Vector2(0, PROC_H * (_procs.size() + 1)))
	_procs.append(panel)
	_slide(panel, base, Vector2(-48, 0), 1.3)

## Entra desde `from` (relativo) a saltos, se queda `hold` s y se apaga.
func _slide(c: Control, base: Vector2, from: Vector2, hold: float) -> void:
	c.position = base + from
	c.modulate.a = 0.0
	var tw := c.create_tween()
	for k: float in [0.5, 0.15, 0.0]:
		var p := base + from * k
		var a := 1.0 - k
		tw.tween_callback(func() -> void:
			c.position = p
			c.modulate.a = a)
		tw.tween_interval(STEP)
	tw.tween_interval(hold)
	for a: float in [0.6, 0.25]:
		var alpha := a
		tw.tween_callback(func() -> void: c.modulate.a = alpha)
		tw.tween_interval(STEP)
	tw.tween_callback(c.queue_free)

# --- Píxeles -------------------------------------------------------------------------------

## Estallido de píxeles en `at`. target: si se da, los píxeles viajan hasta
## ahí (robo de vida, monedas); up: flotan hacia arriba sin caer (curas).
func burst(at: Vector2, colors: Array[Color], count: int, speed := 260.0, target := Vector2.INF, up := false) -> void:
	var b := Burst.new()
	b.setup(at, colors, count, speed, target, up, _vrng)
	add_child(b)


## Píxeles (cuadrados de 1–2 píxeles de arte) con velocidad, gravedad y
## vida; se dibujan en la grilla de píxel de arte. Se borra solo.
class Burst extends Control:
	const GRAVITY := 900.0
	var parts: Array[Dictionary] = []
	var target := Vector2.INF
	var up := false

	func setup(at: Vector2, colors: Array[Color], count: int, speed: float, p_target: Vector2, p_up: bool, rng: RandomNumberGenerator) -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		target = p_target
		up = p_up
		for i in count:
			var ang := rng.randf_range(-PI, PI) if not up else rng.randf_range(-PI * 0.85, -PI * 0.15)
			var spd := speed * rng.randf_range(0.35, 1.0)
			var life := rng.randf_range(0.35, 0.7) if target == Vector2.INF else rng.randf_range(0.5, 0.8)
			parts.append({
				"p": at + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)),
				"v": Vector2(cos(ang), sin(ang)) * spd,
				"c": colors[i % colors.size()],
				"s": float(UIStyle.PIXEL_SCALE * (2 if rng.randf() < 0.35 else 1)),
				"life": life, "max": life,
			})

	func _process(delta: float) -> void:
		var alive := false
		for q: Dictionary in parts:
			var life := float(q.life) - delta
			q["life"] = life
			if life <= 0.0:
				continue
			alive = true
			var v: Vector2 = q.v
			var p: Vector2 = q.p
			if target != Vector2.INF and float(q.max) - life > 0.12:
				# Viaja hacia el destino y se apaga al llegar.
				v = v.lerp((target - p).normalized() * 700.0, minf(1.0, delta * 7.0))
				if p.distance_to(target) < 14.0:
					q["life"] = 0.0
			elif up:
				v *= maxf(0.0, 1.0 - delta * 2.5)
				v.y -= 60.0 * delta
			else:
				v.y += GRAVITY * delta
			q["v"] = v
			q["p"] = p + v * delta
		if not alive:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		for q: Dictionary in parts:
			var life := float(q.life)
			if life <= 0.0:
				continue
			var f := life / float(q.max)
			var c: Color = q.c
			# Se apagan a saltos (3 tonos), no en fundido.
			c.a = 1.0 if f > 0.5 else (0.6 if f > 0.25 else 0.3)
			var s := float(q.s)
			var p := ((q.p as Vector2) / UIStyle.PIXEL_SCALE).floor() * UIStyle.PIXEL_SCALE
			draw_rect(Rect2(p, Vector2(s, s)), c)
