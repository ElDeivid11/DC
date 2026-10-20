class_name UIItemSlot
extends UIButton
## Casilla de objeto (inventario, listas de objetos): retrato + nombre +
## etiqueta de tipo; vacía muestra "— vacío —" y no se puede elegir. La
## descripción sale como tooltip al enfocar/pasar el mouse.

var item_id := ""
## false cuando la pantalla ya muestra la descripción en un panel de detalle.
var with_tooltip := true

func _init(p_item_id := "", p_with_tooltip := true) -> void:
	super("", "ItemSlot")
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	with_tooltip = p_with_tooltip
	set_item(p_item_id)

func set_item(p_item_id: String) -> void:
	item_id = p_item_id
	if item_id == "":
		text = DataRegistry.t("item.empty_slot")
		icon = null
		disabled = true
		UITooltip.attach(self, "")
		return
	disabled = false
	var it := DataRegistry.get_item(item_id)
	var tag := DataRegistry.t("item.type." + String(it.get("tipo", "consumible")))
	text = "%s   %s" % [it.get("nombre", item_id), tag]
	icon = UIPortrait.item_texture(item_id)
	UITooltip.attach(self, String(it.get("descripcion", "")) if with_tooltip else "")
