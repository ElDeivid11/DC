class_name UIChoiceDialog
extends CanvasLayer
## Diálogo con varias opciones en lista (salida del piso, a quién usarle un
## objeto...). Emite `chosen(index)`; -1 = cancelado (Esc/B o "cancelar").
##   var d := UIChoiceDialog.ask(self, "Salida", "¿Qué hacés?", ["Bajar", "Retirarse"], "Quedarse")
##   var i: int = await d.chosen

signal chosen(index: int)

var _buttons: Array = []
var _cancellable := true
var _previous_focus: Control
var _done := false

static func ask(parent: Node, title: String, text: String, options: Array, cancel_text := "", danger_index := -1) -> UIChoiceDialog:
	var d := UIChoiceDialog.new()
	d._build(title, text, options, cancel_text, danger_index)
	parent.add_child(d)
	return d

func _build(title: String, text: String, options: Array, cancel_text: String, danger_index: int) -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cancellable = cancel_text != ""
	var overlay := PanelContainer.new()
	overlay.theme_type_variation = "DimOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	overlay.add_child(center)
	var panel := UIPanel.new(title, "", "TitleLabel")
	panel.custom_minimum_size.x = 460
	center.add_child(panel)
	if text != "":
		var msg := Label.new()
		msg.text = text
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		msg.custom_minimum_size.x = 420
		panel.body.add_child(msg)
	for i in options.size():
		var idx := i
		var b := UIButton.make(String(options[i]), func() -> void: _answer(idx), "DangerButton" if i == danger_index else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		panel.body.add_child(b)
		_buttons.append(b)
	if _cancellable:
		var c := UIButton.make(cancel_text, func() -> void: _answer(-1))
		c.alignment = HORIZONTAL_ALIGNMENT_LEFT
		panel.body.add_child(c)
		_buttons.append(c)
	UIFocus.chain_vertical(_buttons)

func _ready() -> void:
	_previous_focus = get_viewport().gui_get_focus_owner()
	if not _buttons.is_empty():
		(_buttons[0] as Control).call_deferred("grab_focus")

func _unhandled_input(event: InputEvent) -> void:
	if _cancellable and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_answer(-1)

func _answer(index: int) -> void:
	if _done:
		return
	_done = true
	chosen.emit(index)
	if is_instance_valid(_previous_focus) and _previous_focus.is_inside_tree():
		_previous_focus.grab_focus()
	queue_free()
