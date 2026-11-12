class_name UIButton
extends Button
## Botón estándar del juego. Mínimo 40 px de alto, enfocable con teclado y
## mando, y el mouse mueve el foco (así nunca hay dos "seleccionados" a la vez).
## Variaciones de theme: "" (normal), "DangerButton", "ItemSlot", "MenuItem".

func _init(p_text := "", variation := "") -> void:
	text = p_text
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size.y = UIStyle.BUTTON_MIN_H
	if variation != "":
		theme_type_variation = variation
	mouse_entered.connect(_on_mouse_entered)
	focus_entered.connect(_on_focus_entered)
	pressed.connect(func() -> void: SceneRouter.play_ui("click"))

static func make(p_text: String, on_pressed: Callable, variation := "") -> UIButton:
	var b := UIButton.new(p_text, variation)
	b.pressed.connect(on_pressed)
	return b

func _on_mouse_entered() -> void:
	if not disabled and focus_mode != Control.FOCUS_NONE:
		grab_focus()

func _on_focus_entered() -> void:
	SceneRouter.play_ui("hover")
