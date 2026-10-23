class_name UIItemSlot
extends UIButton
## Casilla de objeto. Dos formas:
##  - niche = true: nicho de piedra de 80×80 del morral, con el retrato del
##    objeto (64 px, sin escalar) y un punto de color según el tipo
##    (consumible / pasivo).
##  - niche = false (listas): fila de piedra con retrato chico + nombre + tipo.
## Vacía no se puede elegir. La descripción sale como tooltip al enfocar.

const NICHE_SIZE := Vector2(80, 80)

var item_id := ""
## false cuando la pantalla ya muestra la descripción en un panel de detalle.
var with_tooltip := true
var niche := false
var _dot: ColorRect

func _init(p_item_id := "", p_with_tooltip := true, p_niche := false) -> void:
	niche = p_niche
	super("", "NicheSlot" if niche else "ItemSlot")
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	with_tooltip = p_with_tooltip
	if niche:
		custom_minimum_size = NICHE_SIZE
		icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		expand_icon = false
		_dot = ColorRect.new()
		_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dot.size = Vector2(6, 6)
		_dot.position = NICHE_SIZE - Vector2(14, 14)
		add_child(_dot)
	set_item(p_item_id)

func set_item(p_item_id: String) -> void:
	item_id = p_item_id
	if item_id == "":
		text = "" if niche else DataRegistry.t("item.empty_slot")
		icon = null
		disabled = true
		if _dot:
			_dot.visible = false
		UITooltip.attach(self, "")
		return
	disabled = false
	var it := DataRegistry.get_item(item_id)
	var kind := String(it.get("tipo", "consumible"))
	if niche:
		text = ""
		_dot.visible = true
		_dot.color = UIStyle.BRONZE if kind == "pasivo" else UIStyle.DANGER_FILL
	else:
		text = "%s   %s" % [it.get("nombre", item_id), DataRegistry.t("item.type." + kind)]
	icon = UIPortrait.item_texture(item_id)
	var tip := String(it.get("nombre", "")) + "\n" + String(it.get("descripcion", "")) if niche else String(it.get("descripcion", ""))
	UITooltip.attach(self, tip if with_tooltip else "")

## Placa de piedra con el tipo del objeto ("CONSUMIBLE", "PASIVO").
static func type_plate(kind: String) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.theme_type_variation = "RankPlaque"
	plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	plate.add_child(UILabel.make(DataRegistry.t("item.type." + kind).to_upper(), "NumSmallLabel"))
	return plate
