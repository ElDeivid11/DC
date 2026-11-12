class_name UIPortrait
extends PanelContainer
## Retrato en un nicho con marco de bronce (héroes y objetos). Píxel nítido: filtro nearest y la
## imagen centrada sin deformar. Objetos: PNG de tools/portraits (render 3D
## con filtro PS1), la ruta en items.json → retrato. Héroes: pixel art armado
## por capas según su apariencia (HeroPortrait), a escala entera o recortado
## alrededor de la cara si el hueco es más chico.

var texture_rect: TextureRect
var side := 64
var _skull: UIIcon

func _init(texture: Texture2D = null, p_side := 64) -> void:
	side = p_side
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

## Retrato de un personaje del equipo para un hueco de `p_side` px.
static func hero_texture(member_id: String, p_side := UIStyle.ICON_SIZE) -> Texture2D:
	return HeroPortrait.for_member(member_id, p_side)

## Muestra el retrato de un héroe del equipo, sin escalar (ya viene a escala
## entera o recortado al tamaño del hueco).
func set_hero(member_id: String) -> void:
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	set_texture(HeroPortrait.for_member(member_id, side))

static func item_texture(item_id: String) -> Texture2D:
	return _load(String(DataRegistry.get_item(item_id).get("retrato", "")))

static func for_hero(member_id: String, p_side := 64) -> UIPortrait:
	var p := UIPortrait.new(null, p_side)
	p.set_hero(member_id)
	return p

static func for_item(item_id: String, p_side := 64) -> UIPortrait:
	return UIPortrait.new(item_texture(item_id), p_side)
