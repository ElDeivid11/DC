class_name UIIcon
extends TextureRect
## Ícono del kit (game-icons.net, CC BY 3.0) en una rampa de color: "bronce"
## (reposo), "vela" (foco), "apagado" (deshabilitado), "moneda", "alma",
## "sangre", "amatista". Sale del tipo UIIcons del Theme: <id>_<rampa>.
##   var i := UIIcon.make("mejoras")      # 32×32 px
##   i.set_ramp("vela")

var icon_id := ""
var ramp := "bronce"

func _init(p_id := "", p_ramp := "bronce", side := UIStyle.ICON_SIZE) -> void:
	icon_id = p_id
	ramp = p_ramp
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	custom_minimum_size = Vector2(side, side)
	# Más grande que 32: se escala ×2/×3 entero (pixel nítido).
	if side != UIStyle.ICON_SIZE:
		stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply()

static func make(p_id: String, p_ramp := "bronce", side := UIStyle.ICON_SIZE) -> UIIcon:
	return UIIcon.new(p_id, p_ramp, side)

func set_ramp(p_ramp: String) -> void:
	if p_ramp == ramp:
		return
	ramp = p_ramp
	_apply()

func set_icon(p_id: String, p_ramp := "") -> void:
	icon_id = p_id
	if p_ramp != "":
		ramp = p_ramp
	_apply()

func _apply() -> void:
	texture = texture_for(icon_id, ramp)

## Textura de un ícono (o null si no existe esa rampa).
static func texture_for(p_id: String, p_ramp: String) -> Texture2D:
	return kit_texture("%s_%s" % [p_id, p_ramp])

## Cualquier sprite del tipo UIIcons (pips, sellos, cursor, marcadores, logo).
static func kit_texture(sprite_name: String) -> Texture2D:
	var th := ThemeDB.get_project_theme()
	if th == null or not th.has_icon(sprite_name, "UIIcons"):
		return null
	return th.get_icon(sprite_name, "UIIcons")
