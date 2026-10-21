class_name UIChoiceDialog
extends UIDialog
## Diálogo con varias opciones en lista (salida del piso, a quién usarle un
## objeto...). Emite `chosen(index)`; -1 = cancelado (Esc/B o "cancelar").
##   var d := UIChoiceDialog.ask(self, "Salida", "¿Qué hacés?", ["Bajar", "Retirarse"], "Quedarse")
##   var i: int = await d.chosen

signal chosen(index: int)

var _buttons: Array = []
var _cancellable := true

static func ask(parent: Node, title: String, text: String, options: Array, cancel_text := "", danger_index := -1) -> UIChoiceDialog:
	var d := UIChoiceDialog.new()
	d._build(title, text, options, cancel_text, danger_index)
	parent.add_child(d)
	return d

func _build(title: String, text: String, options: Array, cancel_text: String, danger_index: int) -> void:
	_build_frame(title, text, "normal", 640, true)
	_cancellable = cancel_text != ""
	for i in options.size():
		var idx := i
		var b := add_button(String(options[i]), func() -> void: _answer(idx), "DangerButton" if i == danger_index else "")
		_buttons.append(b)
	if _cancellable:
		var c := add_button(cancel_text, func() -> void: _answer(-1))
		_buttons.append(c)
	UIFocus.chain_vertical(_buttons)

func _ready() -> void:
	super._ready()
	if not _buttons.is_empty():
		(_buttons[0] as Control).call_deferred("grab_focus")

func _unhandled_input(event: InputEvent) -> void:
	if _cancellable and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		SceneRouter.play_ui("cancel")
		_answer(-1)

func _answer(index: int) -> void:
	if answered_already:
		return
	answered_already = true
	chosen.emit(index)
	_close_dialog()
