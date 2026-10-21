class_name UIPortrait
extends PanelContainer
## Retrato en un nicho con marco de bronce (héroes y objetos). Píxel nítido: filtro nearest y la
## imagen centrada sin deformar. Los PNG salen de tools/portraits (render 3D
## con filtro PS1); la ruta va en los datos: items.json → retrato y
## balance.json → party[].retrato.

var texture_rect: TextureRect
var _skull: UIIcon

func _init(texture: Texture2D = null, side := 64) -> void:
	theme_type_variation = "PortraitFrame"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	texture_rect = TextureRect.new()
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.custom_minimum_size = Vector2(side, side)
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(texture_rect)
	set_texture(texture)

func set_texture(texture: Texture2D) -> void:
	texture_rect.texture = texture

## Apagado (objeto bloqueado).
func set_dimmed(on: bool) -> void:
	texture_rect.modulate = UIStyle.FALLEN_TINT if on else Color.WHITE

## Personaje caído: retrato apagado y una calavera encima.
func set_fallen(on: bool) -> void:
	set_dimmed(on)
	if on and _skull == null:
		_skull = UIIcon.make("muerte", "sangre")
		_skull.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		add_child(_skull)
	if _skull:
		_skull.visible = on

## Marco encendido (el que actúa en combate).
func set_active(on: bool) -> void:
	theme_type_variation = "PortraitFrameActive" if on else "PortraitFrame"

## Silueta (objeto secreto todavía no descubierto).
func set_silhouette(on: bool) -> void:
	texture_rect.modulate = UIStyle.BORDER.darkened(0.5) if on else Color.WHITE

static func _load(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	return tex

## Retrato de un personaje del equipo (por id, de balance.json → party).
static func hero_texture(member_id: String) -> Texture2D:
	for m: Variant in DataRegistry.bal("party", []):
		var md: Dictionary = m
		if String(md.get("id", "")) == member_id:
			return _load(String(md.get("retrato", "")))
	return null

static func item_texture(item_id: String) -> Texture2D:
	return _load(String(DataRegistry.get_item(item_id).get("retrato", "")))

static func for_hero(member_id: String, side := 64) -> UIPortrait:
	return UIPortrait.new(hero_texture(member_id), side)

static func for_item(item_id: String, side := 64) -> UIPortrait:
	return UIPortrait.new(item_texture(item_id), side)
