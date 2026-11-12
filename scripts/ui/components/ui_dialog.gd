class_name UIDialog
extends CanvasLayer
## Base de los diálogos modales («carta sellada»): velo, tapa de hierro
## centrada con título gótico, filete, texto, contenido extra, fila de botones
## y un sello de lacre sobre el borde inferior. Funciona con el juego en
## pausa. Tonos: "normal", "danger" (título rojo, sonido de aviso) y "soul".
## La usan UIConfirmDialog y UIChoiceDialog (y el diálogo del alma).

var panel: PanelContainer
var title_label: UIGothicLabel
var message: Label
## Contenido extra entre el texto y los botones (p. ej. una UISoulCard).
var content: VBoxContainer
var buttons_row: BoxContainer
var tone := "normal"
var _previous_focus: Control
var answered_already := false

func _build_frame(title: String, text: String, p_tone := "normal", width := 600, vertical_buttons := false) -> void:
	tone = p_tone
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	var overlay := PanelContainer.new()
	overlay.theme_type_variation = "DimOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	overlay.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = width
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	panel.add_child(vbox)
	_add_seal()

	title_label = UIGothicLabel.new(title)
	title_label.align = HORIZONTAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match tone:
		"danger":
			title_label.set_colors(UIStyle.DANGER, UIStyle.ACCENT)
		"soul":
			title_label.set_colors(UIStyle.SOUL, UIStyle.SOUL_LIGHT)
		_:
			title_label.set_colors(UIStyle.TEXT, UIStyle.CAPITAL)
	vbox.add_child(title_label)
	vbox.add_child(UIDivider.new(360))
	message = Label.new()
	message.text = text
	message.visible = text != ""
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.custom_minimum_size.x = mini(520, width - 80)
	message.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(message)
	content = VBoxContainer.new()
	content.visible = false
	vbox.add_child(content)
	if vertical_buttons:
		buttons_row = VBoxContainer.new()
		buttons_row.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	else:
		buttons_row = HBoxContainer.new()
		buttons_row.alignment = BoxContainer.ALIGNMENT_CENTER
		buttons_row.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	vbox.add_child(buttons_row)
	# Lugar para el sello (que cuelga del borde inferior).
	var pad := Control.new()
	pad.custom_minimum_size.y = UIStyle.SPACE * 2
	vbox.add_child(pad)

## Sello de lacre centrado sobre el borde inferior de la tapa.
func _add_seal() -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(holder)
	var seal := UISprite.new("seal")
	seal.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	seal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	seal.offset_top = 5
	seal.offset_bottom = 31
	holder.add_child(seal)

## Agrega contenido extra (se muestra entre el texto y los botones).
func add_content(c: Control) -> void:
	content.visible = true
	content.add_child(c)

func add_button(text: String, on_pressed: Callable, variation := "") -> UIButton:
	var b := UIButton.make(text, on_pressed, variation)
	b.custom_minimum_size.x = 160
	buttons_row.add_child(b)
	return b

func _ready() -> void:
	_previous_focus = get_viewport().gui_get_focus_owner()
	match tone:
		"danger":
			SceneRouter.play_ui("error")
		"soul":
			SceneRouter.play_ui("soul")
		_:
			SceneRouter.play_ui("open")

## Cierra el diálogo y devuelve el foco a quien lo tenía.
func _close_dialog() -> void:
	if is_instance_valid(_previous_focus) and _previous_focus.is_inside_tree():
		_previous_focus.grab_focus()
	queue_free()
