class_name UITabs
extends VBoxContainer
## Pestañas: TabBar arriba + contenido abajo. Con el TabBar enfocado,
## ←/→ cambian de pestaña; además Q/E (o LB/RB) cambian desde cualquier lado.

signal tab_changed(index: int)

var tab_bar: TabBar
var content: PanelContainer
var _pages: Array[Control] = []

func _init() -> void:
	tab_bar = TabBar.new()
	tab_bar.focus_mode = Control.FOCUS_ALL
	tab_bar.tab_changed.connect(_on_tab_changed)
	add_child(tab_bar)
	content = PanelContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(content)

func add_tab(title: String, page: Control) -> void:
	tab_bar.add_tab(title)
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
	SceneRouter.play_ui("hover")
	tab_changed.emit(index)
