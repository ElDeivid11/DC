class_name UISelector
extends UIListRow
## Fila de lista con un valor que se cambia en el lugar:
## [llama] Nombre ............ ‹ Valor › [muestra]
## ← / → (o los botones del mando) pasan al anterior o al siguiente (da la
## vuelta); Enter o clic, al siguiente. La muestra (opcional) es un cuadrito
## con un color de los datos (p. ej. la piel de un héroe).

signal changed(index: int)

const VALUE_WIDTH := 190
const SWATCH := 18

var count := 1
var index := 0
var value_label: Label
var swatch: Panel
var _name_of: Callable
var _color_of: Callable

## names: (i) -> String. colors (opcional): (i) -> Color para la muestra.
func _init(p_text: String, p_count: int, p_index: int, names: Callable, colors := Callable()) -> void:
	super(p_text)
	count = maxi(p_count, 1)
	index = clampi(p_index, 0, count - 1)
	_name_of = names
	_color_of = colors
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(UILabel.make("‹", "NumSmallLabel"))
	value_label = UILabel.make("", "DetailLabel")
	value_label.custom_minimum_size.x = VALUE_WIDTH
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(value_label)
	box.add_child(UILabel.make("›", "NumSmallLabel"))
	if colors.is_valid():
		swatch = Panel.new()
		swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(swatch)
	add_column(box)
	pressed.connect(func() -> void: set_index(index + 1))
	_show()

func set_index(i: int, notify := true) -> void:
	index = posmod(i, count)
	_show()
	if notify:
		SceneRouter.play_ui("hover")
		changed.emit(index)

func _show() -> void:
	value_label.text = String(_name_of.call(index))
	if swatch:
		var sb := StyleBoxFlat.new()
		sb.bg_color = _color_of.call(index)
		sb.border_color = UIStyle.INK
		sb.set_border_width_all(2)
		swatch.add_theme_stylebox_override("panel", sb)

func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		set_index(index - 1)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		set_index(index + 1)
		accept_event()
