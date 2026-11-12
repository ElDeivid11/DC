class_name UITooltip
extends RefCounted
## Tooltip que aparece al ENFOCAR (teclado/mando) o al pasar el mouse, a
## diferencia del tooltip nativo de Godot que solo responde al mouse.
##   UITooltip.attach(boton, "Cura 8 HP...")
## Un único panel compartido vive en su propia CanvasLayer sobre todo.

const META := "ui_tooltip_text"

static var _layer: CanvasLayer
static var _panel: PanelContainer
static var _label: Label
static var _owner: Control

static func attach(control: Control, text: String) -> void:
	control.set_meta(META, text)
	if control.has_meta("ui_tooltip_connected"):
		return
	control.set_meta("ui_tooltip_connected", true)
	control.focus_entered.connect(func() -> void: _show_for(control))
	control.mouse_entered.connect(func() -> void: _show_for(control))
	control.focus_exited.connect(func() -> void: _hide_for(control))
	control.mouse_exited.connect(func() -> void:
		if not control.has_focus():
			_hide_for(control)
	)
	control.tree_exiting.connect(func() -> void: _hide_for(control))

static func _ensure(tree: SceneTree) -> void:
	if is_instance_valid(_layer):
		return
	_layer = CanvasLayer.new()
	_layer.layer = 90
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "TooltipPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = 260
	_label.theme_type_variation = "TooltipLabel"
	_panel.add_child(_label)
	_layer.add_child(_panel)
	tree.root.add_child.call_deferred(_layer)

static func _show_for(control: Control) -> void:
	var text := String(control.get_meta(META, ""))
	if text == "" or not control.is_inside_tree():
		_hide_for(control)
		return
	_ensure(control.get_tree())
	_owner = control
	_label.text = text
	_panel.reset_size()
	_panel.visible = true
	_place.call_deferred(control)

static func _place(control: Control) -> void:
	if not is_instance_valid(control) or _owner != control or not is_instance_valid(_panel):
		return
	var rect := control.get_global_rect()
	var vp := control.get_viewport_rect().size
	var size := _panel.get_combined_minimum_size()
	var pos := Vector2(rect.position.x, rect.end.y + UIStyle.SPACE)
	if pos.y + size.y > vp.y:
		pos.y = rect.position.y - size.y - UIStyle.SPACE
	pos.x = clampf(pos.x, UIStyle.SPACE, maxf(vp.x - size.x - UIStyle.SPACE, UIStyle.SPACE))
	_panel.position = pos

static func _hide_for(control: Control) -> void:
	if _owner == control and is_instance_valid(_panel):
		_panel.visible = false
		_owner = null
