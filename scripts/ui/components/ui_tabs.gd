class_name UITabs
extends VBoxContainer
## Pestañas del grimorio: [Q] lengüetas con ícono [E] arriba y la página en un
## inserto hundido abajo. Con el TabBar enfocado, ←/→ cambian de pestaña;
## además Q/E (o LB/RB) cambian desde cualquier lado, con sonido de página.

signal tab_changed(index: int)

var tab_bar: TabBar
var content: PanelContainer
var _pages: Array[Control] = []

func _init() -> void:
	add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	row.add_child(make_keycap(DataRegistry.t("ui.key_q")))
	tab_bar = TabBar.new()
	tab_bar.focus_mode = Control.FOCUS_ALL
	# Sin recorte: el TabBar pide el ancho de todas sus lengüetas (sin flechas).
	tab_bar.clip_tabs = false
	tab_bar.tab_changed.connect(_on_tab_changed)
	row.add_child(tab_bar)
	row.add_child(make_keycap(DataRegistry.t("ui.key_e")))
	content = PanelContainer.new()
	content.theme_type_variation = "PanelAlt"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(content)

## Tecla en una placa (KeyCap): Q/E de las pestañas, controles en Opciones.
static func make_keycap(key: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.theme_type_variation = "KeyCap"
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.theme_type_variation = "NumSmallLabel"
	l.text = key
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(l)
	return cap

func add_tab(title: String, page: Control, icon_id := "") -> void:
	tab_bar.add_tab(title)
	if icon_id != "":
		# Rampa de reposo; los íconos de color propio (almas) no tienen bronce.
		var tex := UIIcon.texture_for(icon_id, "bronce")
		if tex == null:
			tex = UIIcon.texture_for(icon_id, "vela")
		tab_bar.set_tab_icon(tab_bar.tab_count - 1, tex)
	page.visible = _pages.is_empty()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pages.append(page)
	content.add_child(page)

func current() -> int:
	return tab_bar.current_tab

func select(index: int) -> void:
	tab_bar.current_tab = clampi(index, 0, maxi(_pages.size() - 1, 0))

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _pages.size() < 2:
		return
	var step := 0
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_Q:
			step = -1
		elif k == KEY_E:
			step = 1
	elif event is InputEventJoypadButton and event.is_pressed():
		var b := (event as InputEventJoypadButton).button_index
		if b == JOY_BUTTON_LEFT_SHOULDER:
			step = -1
		elif b == JOY_BUTTON_RIGHT_SHOULDER:
			step = 1
	if step != 0:
		get_viewport().set_input_as_handled()
		select(posmod(tab_bar.current_tab + step, _pages.size()))

func _on_tab_changed(index: int) -> void:
	# Si el foco estaba dentro de la página que se oculta, Godot lo suelta y
	# nadie lo recupera (teclado y mando quedarían sin foco): vuelve al TabBar.
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var lost := focused != null and content.is_ancestor_of(focused)
	for i in _pages.size():
		_pages[i].visible = i == index
	if lost:
		tab_bar.grab_focus()
	SceneRouter.play_ui("page")
	tab_changed.emit(index)
