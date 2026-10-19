class_name UIToast
extends RefCounted
## Avisos breves abajo al centro ("Mejora comprada", "Inventario lleno"...).
## Se apilan y se desvanecen solos. kind: info | good | danger | coin | soul.
##   UIToast.show(get_tree(), "Texto", "good")

const DURATION := 2.2

static var _layer: CanvasLayer
static var _stack: VBoxContainer

static func show(tree: SceneTree, text: String, kind := "info") -> void:
	if tree == null:
		return
	_ensure(tree)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "HudPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match kind:
		"good":
			l.theme_type_variation = "GoodLabel"
		"danger":
			l.theme_type_variation = "DangerLabel"
		"coin":
			l.theme_type_variation = "CoinLabel"
		"soul":
			l.theme_type_variation = "SoulLabel"
	panel.add_child(l)
	_stack.add_child(panel)
	while _stack.get_child_count() > 4:
		_stack.get_child(0).queue_free()
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, UIStyle.TRANSITION)
	tw.tween_interval(DURATION)
	tw.tween_property(panel, "modulate:a", 0.0, 0.3)
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
	_stack.alignment = BoxContainer.ALIGNMENT_END
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stack.offset_bottom = -96
	anchor.add_child(_stack)
	tree.root.add_child(_layer)
