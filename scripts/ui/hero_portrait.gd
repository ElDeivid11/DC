class_name HeroPortrait
extends RefCounted
## Retratos de los héroes en pixel art (48x48), armados por capas con las
## piezas de tools/portraits/draw_hero_parts.py (assets/portraits/heroes/
## partes.png + partes.json) y las paletas de data/apariencia.json, según la
## apariencia de cada uno (MetaState.hero_look). En el PNG cada píxel guarda
## material (R / 16) y tono (G / 80); acá se pintan con su color.
##
## Tamaños: el retrato se muestra a escala entera (×1, ×2...); en huecos más
## chicos que 48 se recorta alrededor de la cara (el píxel nunca se achica).

const SIZE := 48
const ATLAS := "res://assets/portraits/heroes/partes.png"
## Centro de la cara: los retratos chicos se recortan alrededor de acá.
const FACE := Vector2i(24, 21)
## Materiales fijos (mismo color para todos): fijos de apariencia.json.
const FIXED: Array[String] = ["tinta", "blanco", "cuero", "metal", "oso", "dientes", "pintura"]

static var _atlas: Image
static var _manifest: Dictionary = {}
static var _images: Dictionary = {}
static var _textures: Dictionary = {}

static func _ensure_loaded() -> bool:
	if _atlas != null:
		return true
	if not ResourceLoader.exists(ATLAS) or not FileAccess.file_exists(DataRegistry.HERO_PARTS_MANIFEST):
		return false
	var tex: Texture2D = load(ATLAS)
	_atlas = tex.get_image()
	if _atlas.is_compressed():
		_atlas.decompress()
	_atlas.convert(Image.FORMAT_RGBA8)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DataRegistry.HERO_PARTS_MANIFEST))
	if parsed is Dictionary:
		_manifest = parsed
	return not _manifest.is_empty()

## Olvida lo armado (después de cambiar una apariencia).
static func clear_cache() -> void:
	_images.clear()
	_textures.clear()

static func _key(look: Dictionary) -> String:
	var parts: Array[String] = []
	for k in DataRegistry.look_keys():
		parts.append(str(int(look.get(k, 0))))
	return ",".join(parts)

static func _tones(hexes: Array) -> Array[Color]:
	var out: Array[Color] = []
	for h: Variant in hexes:
		out.append(Color.html(String(h)))
	return out

## Material -> tonos [claro, medio, oscuro] para una apariencia.
static func _palette(look: Dictionary) -> Dictionary:
	var pal := {}
	for mat in FIXED:
		pal[mat] = _tones(DataRegistry.look_tones(mat))
	for c in DataRegistry.LOOK_COLORS:
		pal[c] = _tones(DataRegistry.look_tones(c, int(look.get("color_" + c, 0))))
	return pal

## El retrato de 48x48 de una apariencia (se arma una vez y queda guardado).
static func image(look: Dictionary) -> Image:
	var key := _key(look)
	if _images.has(key):
		return _images[key]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	if not _ensure_loaded():
		return img
	var materials: Array = _manifest.get("materials", [])
	var hides: Array = _manifest.get("hides_hair", [])
	var cats: Dictionary = _manifest.get("categories", {})
	var picks := {}
	for cat: String in cats.keys():
		var opts: Array = cats[cat]
		picks[cat] = opts[clampi(int(look.get(cat, 0)), 0, opts.size() - 1)]
	# Bajo capucha, cabeza de oso o casco el pelo queda adentro.
	var headwear: Dictionary = picks.get("tocado", {})
	var hood := hides.has(String(headwear.get("id", "")))
	var pal := _palette(look)
	for layer: Variant in _manifest.get("layers", []):
		for cat: String in picks.keys():
			if hood and cat == "pelo":
				continue
			var pick: Dictionary = picks[cat]
			var spec: Variant = (pick.get("layers", {}) as Dictionary).get(String(layer))
			if not spec is Dictionary:
				continue
			var r: Array = (spec as Dictionary).rect
			var at: Array = (spec as Dictionary).at
			for yy in int(r[3]):
				for xx in int(r[2]):
					var px := _atlas.get_pixel(int(r[0]) + xx, int(r[1]) + yy)
					if px.a8 == 0:
						continue
					var tones: Array = pal.get(String(materials[px.r8 >> 4]), [])
					if tones.is_empty():
						continue
					var tone := mini(int(px.g8 / 80.0), tones.size() - 1)
					img.set_pixel(int(at[0]) + xx, int(at[1]) + yy, tones[tone])
	_images[key] = img
	return img

## Para un hueco de `side` px: a escala entera si entra (48, 96...), o un
## recorte de side x side alrededor de la cara si es más chico.
static func texture(look: Dictionary, side := SIZE) -> Texture2D:
	var key := "%s@%d" % [_key(look), side]
	if _textures.has(key):
		return _textures[key]
	var img := image(look)
	var out: Image
	if side >= SIZE:
		var k := floori(float(side) / SIZE)
		out = img.duplicate() as Image
		out.resize(SIZE * k, SIZE * k, Image.INTERPOLATE_NEAREST)
	else:
		var x0 := clampi(FACE.x - floori(side / 2.0), 0, SIZE - side)
		var y0 := clampi(FACE.y - floori(side / 2.0), 0, SIZE - side)
		out = img.get_region(Rect2i(x0, y0, side, side))
	var tex := ImageTexture.create_from_image(out)
	_textures[key] = tex
	return tex

## El retrato de un héroe del equipo (con la apariencia guardada).
static func for_member(member_id: String, side := SIZE) -> Texture2D:
	return texture(MetaState.hero_look(member_id), side)
