class_name UIFocus
extends RefCounted
## Utilidades de foco para navegar con teclado/mando: ninguna pantalla debe
## quedar sin foco, y las listas verticales dan la vuelta (último → primero).

## Primer Control enfocable y visible dentro de `root` (en orden de árbol).
static func first_focusable(root: Node) -> Control:
	for child in root.get_children():
		if child is Control:
			var c: Control = child
			if not c.is_visible_in_tree():
				continue
			if c.focus_mode == Control.FOCUS_ALL and not (c is BaseButton and (c as BaseButton).disabled):
				return c
		var deeper := first_focusable(child)
		if deeper != null:
			return deeper
	return null

## Le da el foco al primer enfocable de `root`. Diferido: sirve en _ready().
static func grab_first(root: Node) -> void:
	var c := first_focusable(root)
	if c != null:
		c.call_deferred("grab_focus")

## Enlaza una lista vertical para que ↑/↓ recorran en orden y den la vuelta.
static func chain_vertical(items: Array, loop := true) -> void:
	var list: Array[Control] = []
	for it: Variant in items:
		if it is Control and (it as Control).focus_mode != Control.FOCUS_NONE:
			list.append(it)
	for i in list.size():
		var c := list[i]
		if i > 0:
			c.focus_neighbor_top = c.get_path_to(list[i - 1])
		elif loop and list.size() > 1:
			c.focus_neighbor_top = c.get_path_to(list[list.size() - 1])
		if i < list.size() - 1:
			c.focus_neighbor_bottom = c.get_path_to(list[i + 1])
		elif loop and list.size() > 1:
			c.focus_neighbor_bottom = c.get_path_to(list[0])
