class_name UIScreen
extends Control
## Base de toda pantalla/overlay de menú: fondo atenuado a pantalla completa,
## panel grande con [Título ......... ◈ monedas] / separador / cuerpo / pie
## con botones. Esc/B (ui_cancel) cierra (emite `closed`).
##
## Las subclases arman su contenido en `body` y `footer` (en _ready, después
## de super._ready()) y llaman a focus_first() al terminar.

signal closed

var title_label: Label
var coins_label: Label
var body: VBoxContainer
var footer: HBoxContainer
var panel: PanelContainer
## false = Esc no cierra (p. ej. pantallas que deciden ellas qué hace "atrás").
var closable := true

func _init(title := "") -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var overlay := PanelContainer.new()
	overlay.theme_type_variation = "DimOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UIStyle.MARGIN_SCREEN)
	overlay.add_child(margin)
	panel = PanelContainer.new()
	margin.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	panel.add_child(vbox)
	var header := HBoxContainer.new()
	vbox.add_child(header)
	title_label = Label.new()
	title_label.theme_type_variation = "TitleLabel"
	title_label.text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	coins_label = Label.new()
	coins_label.theme_type_variation = "CoinLabel"
	coins_label.add_theme_font_size_override("font_size", UIStyle.FONT_SUBTITLE)
	coins_label.visible = false
	header.add_child(coins_label)
	vbox.add_child(HSeparator.new())
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)
	footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	vbox.add_child(footer)

func _ready() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, UIStyle.TRANSITION)

func show_coins(amount: int) -> void:
	coins_label.visible = true
	coins_label.text = UIFormat.coins(amount)

func add_footer_button(text: String, on_pressed: Callable, variation := "") -> UIButton:
	var b := UIButton.make(text, on_pressed, variation)
	footer.add_child(b)
	return b

func focus_first() -> void:
	UIFocus.grab_first(body)

func close() -> void:
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if closable and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
