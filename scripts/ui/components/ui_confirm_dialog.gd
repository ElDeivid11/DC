class_name UIConfirmDialog
extends CanvasLayer
## Diálogo de confirmación modal (fondo atenuado + panel con título). Funciona
## con el juego en pausa. El foco arranca en "No" (lo seguro); Esc/B = No.
##   var d := UIConfirmDialog.ask(self, "Abandonar", "¿Seguro?", "Abandonar", "Volver", true)
##   if await d.answered: ...

signal answered(yes: bool)

var _yes: UIButton
var _no: UIButton
var _previous_focus: Control
var _done := false

static func ask(parent: Node, title: String, text: String, yes_text: String, no_text: String, danger := false) -> UIConfirmDialog:
	var d := UIConfirmDialog.new()
	d._build(title, text, yes_text, no_text, danger)
	parent.add_child(d)
	return d

func _build(title: String, text: String, yes_text: String, no_text: String, danger: bool) -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	var overlay := PanelContainer.new()
	overlay.theme_type_variation = "DimOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	overlay.add_child(center)
	var panel := UIPanel.new(title, "", "TitleLabel")
	panel.custom_minimum_size.x = 440
	center.add_child(panel)
	var msg := Label.new()
	msg.text = text
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size.x = 400
	panel.body.add_child(msg)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	panel.body.add_child(row)
	_no = UIButton.make(no_text, func() -> void: _answer(false))
	_yes = UIButton.make(yes_text, func() -> void: _answer(true), "DangerButton" if danger else "")
	row.add_child(_no)
	row.add_child(_yes)

func _ready() -> void:
	_previous_focus = get_viewport().gui_get_focus_owner()
	_no.call_deferred("grab_focus")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_answer(false)

func _answer(yes: bool) -> void:
	if _done:
		return
	_done = true
	answered.emit(yes)
	if is_instance_valid(_previous_focus) and _previous_focus.is_inside_tree():
		_previous_focus.grab_focus()
	queue_free()
