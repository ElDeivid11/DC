class_name UIConfirmDialog
extends UIDialog
## Diálogo de confirmación modal. El foco arranca en "No" (lo seguro); Esc/B
## = No. Con danger el título va en rojo y "Sí" es un botón de peligro.
##   var d := UIConfirmDialog.ask(self, "Abandonar", "¿Seguro?", "Abandonar", "Volver", true)
##   if await d.answered: ...

signal answered(yes: bool)

var _yes: UIButton
var _no: UIButton

static func ask(parent: Node, title: String, text: String, yes_text: String, no_text: String, danger := false) -> UIConfirmDialog:
	var d := UIConfirmDialog.new()
	d._build(title, text, yes_text, no_text, danger)
	parent.add_child(d)
	return d

func _build(title: String, text: String, yes_text: String, no_text: String, danger: bool) -> void:
	_build_frame(title, text, "danger" if danger else "normal", 600)
	_no = add_button(no_text, func() -> void: _answer(false))
	_yes = add_button(yes_text, func() -> void: _answer(true), "DangerButton" if danger else "")

func _ready() -> void:
	super._ready()
	_no.call_deferred("grab_focus")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		SceneRouter.play_ui("cancel")
		_answer(false)

func _answer(yes: bool) -> void:
	if answered_already:
		return
	answered_already = true
	answered.emit(yes)
	_close_dialog()
