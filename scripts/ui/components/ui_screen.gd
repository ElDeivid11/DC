class_name UIScreen
extends Control
## Base de toda pantalla/overlay de menú: velo sobre lo de abajo y una tapa de
## hierro (panel_iron) con cimera de calavera, título gótico centrado con
## filete, placa de monedas, cuerpo desplazable y pie con botones. Esc/B
## (ui_cancel) cierra (emite `closed`).
##
## compact = true (pausa, menús cortos): la tapa va centrada y del tamaño del
## contenido, sin placa de monedas en el encabezado.
##
## Las subclases arman su contenido en `body` y `footer` (en _ready, después
## de super._ready()) y llaman a focus_first() al terminar.

signal closed

const COMPACT_WIDTH := 520

var title_label: UIGothicLabel
var coins_plate: UICoinPlate
var body: VBoxContainer
var footer: HBoxContainer
var header: VBoxContainer
var panel: PanelContainer
var compact := false
## false = Esc no cierra (p. ej. pantallas que deciden ellas qué hace "atrás").
var closable := true
## Acción que abrió la pantalla (p. ej. "open_status" = Tab): volver a
## pulsarla la cierra. Se mira en _input, ANTES que la GUI, porque Godot usa
## Tab para mover el foco.
var toggle_action := ""
var _closing_sound := true

func _init(title := "", p_compact := false) -> void:
	compact = p_compact
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var overlay := PanelContainer.new()
	overlay.theme_type_variation = "DimOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	panel = PanelContainer.new()
	if compact:
		var center := CenterContainer.new()
		overlay.add_child(center)
		panel.custom_minimum_size.x = COMPACT_WIDTH
		center.add_child(panel)
	else:
		var margin := MarginContainer.new()
		for side: String in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, UIStyle.MARGIN_SCREEN)
		overlay.add_child(margin)
		margin.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	panel.add_child(vbox)
	_add_crest()

	# Encabezado: título gótico centrado, placa de monedas a la derecha y filete.
	header = VBoxContainer.new()
	header.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	vbox.add_child(header)
	var top := Control.new()
	top.custom_minimum_size.y = 48
	header.add_child(top)
	title_label = UIGothicLabel.new(title)
	title_label.align = HORIZONTAL_ALIGNMENT_CENTER
	title_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	top.add_child(title_label)
	coins_plate = UICoinPlate.new()
	coins_plate.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	coins_plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	coins_plate.grow_vertical = Control.GROW_DIRECTION_BOTH
	coins_plate.visible = false
	top.add_child(coins_plate)
	header.add_child(UIDivider.new(360))

	# El cuerpo va en un ScrollContainer: con la escala de UI alta o ventanas
	# chicas, lo que no entre se desplaza siguiendo al foco en vez de cortarse.
	# Margen interior de 4 px para que el aro de foco no quede recortado.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	vbox.add_child(scroll)
	var inner := MarginContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, UIStyle.SPACE)
	scroll.add_child(inner)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(body)
	footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	vbox.add_child(footer)
	if compact:
		scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		footer.alignment = BoxContainer.ALIGNMENT_CENTER

## Cimera de calavera sobre el borde superior de la tapa.
func _add_crest() -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(holder)
	var crest := UISprite.new("crest")
	crest.set_anchors_preset(Control.PRESET_CENTER_TOP)
	crest.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# El contenido empieza 28 px debajo del borde; la cimera se centra en el hierro.
	crest.offset_top = -38
	crest.offset_bottom = -20
	holder.add_child(crest)

func _ready() -> void:
	# Apertura por pasos (PS1): la tapa crece en alto 0 → 50% → 100%.
	SceneRouter.play_ui("open")
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2(1, 0.0)
	var tw := create_tween()
	tw.tween_callback(func() -> void:
		panel.pivot_offset = panel.size / 2.0
		panel.scale = Vector2(1, 0.5)
	).set_delay(0.033)
	tw.tween_callback(func() -> void: panel.scale = Vector2.ONE).set_delay(0.033)

func show_coins(amount: int) -> void:
	coins_plate.visible = not compact
	coins_plate.set_amount(amount)

func add_footer_button(text: String, on_pressed: Callable, variation := "") -> UIButton:
	var b := UIButton.make(text, on_pressed, variation)
	b.custom_minimum_size.x = 160
	footer.add_child(b)
	return b

## Pista en una cinta al pie (a la izquierda de los botones).
func add_footer_hint(text: String) -> PanelContainer:
	var ribbon := PanelContainer.new()
	ribbon.theme_type_variation = "RibbonSmall"
	ribbon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.theme_type_variation = "DetailLabel"
	l.text = text
	ribbon.add_child(l)
	footer.add_child(ribbon)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	footer.move_child(ribbon, 0)
	footer.move_child(spacer, 1)
	return ribbon

func focus_first() -> void:
	UIFocus.grab_first(body)

func close() -> void:
	if _closing_sound:
		SceneRouter.play_ui("close")
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if toggle_action != "" and closable and event.is_action_pressed(toggle_action) and _is_topmost():
		get_viewport().set_input_as_handled()
		close()

## Solo la pantalla de más arriba reacciona (p. ej. Estado abierto desde Pausa).
func _is_topmost() -> bool:
	for c in get_children():
		if c is UIScreen or c is UIDialog:
			return false
	return true

func _unhandled_input(event: InputEvent) -> void:
	if closable and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
