class_name UIToast
extends RefCounted
## Avisos breves arriba al centro, en una cinta con cola de golondrina
## ("Mejora comprada", "Inventario lleno"...). Se apilan (máx. 3) y se
## disuelven solos, por pasos.
## kind: info | good | danger | coin | soul | level.
##   UIToast.show(get_tree(), "Texto", "good")

const DURATION := 2.0
const MAX_STACK := 3

static var _layer: CanvasLayer
static var _stack: VBoxContainer

static func show(tree: SceneTree, text: String, kind := "info") -> void:
	if tree == null:
		return
	_ensure(tree)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "ToastPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var color := UIStyle.ACCENT
	var icon_name := ""
	match kind:
		"good":
			color = UIStyle.GOOD
		"danger":
			color = UIStyle.DANGER
		"coin":
			color = UIStyle.COIN
			icon_name = "monedas_moneda"
		"soul":
			color = UIStyle.SOUL
			icon_name = "almas_alma"
		"level":
			color = UIStyle.XP
			icon_name = "exp_amatista"
	if icon_name != "":
		var icon := TextureRect.new()
		icon.texture = UIIcon.kit_texture(icon_name)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
	var l := Label.new()
	l.theme_type_variation = "HeadLabel"
	l.add_theme_color_override("font_color", color)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	_stack.add_child(panel)
	# remove_child primero: queue_free solo no saca al nodo en el momento, la
	# cuenta no baja y el bucle no terminaba nunca.
	while _stack.get_child_count() > MAX_STACK:
		var oldest := _stack.get_child(0)
		_stack.remove_child(oldest)
		oldest.queue_free()
	# Entrada por pasos (sin suavizado) y salida en tres pasos de opacidad.
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_callback(func() -> void: panel.modulate.a = 0.5)
	tw.tween_interval(0.033)
	tw.tween_callback(func() -> void: panel.modulate.a = 1.0)
	tw.tween_interval(DURATION)
	for a: float in [0.66, 0.33]:
		var alpha := a
		tw.tween_callback(func() -> void: panel.modulate.a = alpha)
		tw.tween_interval(0.066)
	tw.tween_callback(panel.queue_free)

static func _ensure(tree: SceneTree) -> void:
	if is_instance_valid(_layer):
		return
	_layer = CanvasLayer.new()
	_layer.layer = 70
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(anchor)
	_stack = VBoxContainer.new()
	_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stack.offset_top = 16
	_stack.add_theme_constant_override("separation", 8)
	anchor.add_child(_stack)
	tree.root.add_child(_layer)
