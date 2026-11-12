class_name UICinematic
extends CanvasLayer
## Modo cine para la presentación del jefe: franjas de tinta arriba y abajo
## (entran y salen a saltos, como el resto de la UI), la pista para acelerar
## y el cartel del jefe sobre una banda velada: piso, nombre en gótica grande
## (×2, píxel entero) y epíteto entre dos filetes.
##   var cine := UICinematic.open(self)
##   cine.show_title("Guardián del piso I", "Nigromante novicio", "...", 2.2)
##   await cine.title_done
##   cine.close()

signal title_done

const BAR_FRACTION := 0.1
const TITLE_SCALE := 2
const STEP := 0.05

var _root: Control
var _top: ColorRect
var _bottom: ColorRect
var _bar_h := 0.0
## Hay un cartel en pantalla (termina con title_done).
var title_showing := false

static func open(parent: Node) -> UICinematic:
	var c := UICinematic.new()
	parent.add_child(c)
	return c

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_bar_h = roundf(_root.get_viewport_rect().size.y * BAR_FRACTION / 2.0) * 2.0
	_top = _make_bar(Control.PRESET_TOP_WIDE)
	_bottom = _make_bar(Control.PRESET_BOTTOM_WIDE)
	_add_hint()
	_slide(1.0)

func _make_bar(preset: int) -> ColorRect:
	var r := ColorRect.new()
	r.color = UIStyle.INK
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(preset)
	_root.add_child(r)
	return r

## «[Enter] acelerar», en la franja de abajo, a la derecha.
func _add_hint() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BOTH
	row.offset_left = -24
	row.offset_right = -24
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(UITabs.make_keycap(DataRegistry.t("ui.key_enter")))
	var l := UILabel.make(DataRegistry.t("boss.skip"), "DetailLabel")
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	_bottom.add_child(row)

## Franjas: 0 = afuera, 1 = adentro (en cuatro saltos).
func _slide(to: float) -> void:
	var tw := create_tween()
	for i in range(1, 5):
		var k := (i / 4.0) if to > 0.5 else (1.0 - i / 4.0)
		tw.tween_callback(func() -> void: _set_bars(k))
		tw.tween_interval(STEP)

func _set_bars(k: float) -> void:
	var h := roundf(_bar_h * k / 2.0) * 2.0
	_top.offset_top = 0.0
	_top.offset_bottom = h
	_bottom.offset_top = -h
	_bottom.offset_bottom = 0.0

## El cartel: entra en tres pasos de opacidad, se queda `hold` segundos y se
## va igual; al irse emite title_done.
func show_title(kicker: String, title: String, epithet: String, hold: float) -> void:
	title_showing = true
	# Columna a pantalla completa que centra la banda en alto; la banda ocupa
	# todo el ancho.
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(layout)
	var band := PanelContainer.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var veil := StyleBoxFlat.new()
	veil.bg_color = UIStyle.VEIL
	veil.content_margin_top = 18
	veil.content_margin_bottom = 18
	band.add_theme_stylebox_override("panel", veil)
	layout.add_child(band)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(box)
	box.add_child(UIDivider.new(420))
	var top := UILabel.make(kicker.to_upper(), "DetailLabel")
	top.add_theme_color_override("font_color", UIStyle.ACCENT)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(top)
	# Gótica a doble tamaño: el rótulo se escala y su contenedor reserva el lugar.
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(holder)
	var big := UIGothicLabel.new(title, "GothicTitle", UIStyle.DANGER, UIStyle.ACCENT)
	holder.add_child(big)
	var big_size := big.get_combined_minimum_size()
	big.size = big_size
	big.scale = Vector2(TITLE_SCALE, TITLE_SCALE)
	holder.custom_minimum_size = big_size * TITLE_SCALE
	if epithet != "":
		var quote := UIGothicLabel.new(epithet, "GothicQuote", UIStyle.TEXT_DIM, UIStyle.TEXT_DIM)
		quote.align = HORIZONTAL_ALIGNMENT_CENTER
		quote.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(quote)
	box.add_child(UIDivider.new(420))
	layout.modulate.a = 0.0
	var tw := create_tween()
	for a: float in [0.33, 0.66, 1.0]:
		var alpha := a
		tw.tween_callback(func() -> void: layout.modulate.a = alpha)
		tw.tween_interval(STEP * 1.5)
	tw.tween_interval(hold)
	for a: float in [0.66, 0.33, 0.0]:
		var alpha := a
		tw.tween_callback(func() -> void: layout.modulate.a = alpha)
		tw.tween_interval(STEP * 1.5)
	tw.tween_callback(func() -> void:
		layout.queue_free()
		title_showing = false
		title_done.emit())

## Saca las franjas y se libera.
func close() -> void:
	_slide(0.0)
	var tw := create_tween()
	tw.tween_interval(STEP * 5)
	tw.tween_callback(queue_free)
