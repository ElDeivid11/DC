class_name UIMenuItem
extends UIButton
## Ítem de menú en lista (Hub, pausa): sin caja, alineado a la izquierda, con
## "▶" delante cuando tiene el foco (como en el wireframe del Hub).

var label_text := ""

func _init(p_text := "") -> void:
	super(p_text, "MenuItem")
	label_text = p_text
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	_refresh(false)
	focus_entered.connect(func() -> void: _refresh(true))
	focus_exited.connect(func() -> void: _refresh(false))

static func make_item(p_text: String, on_pressed: Callable) -> UIMenuItem:
	var b := UIMenuItem.new(p_text)
	b.pressed.connect(on_pressed)
	return b

func set_label(t: String) -> void:
	label_text = t
	_refresh(has_focus())

func _refresh(focused: bool) -> void:
	text = ("▶  " if focused else "    ") + label_text
