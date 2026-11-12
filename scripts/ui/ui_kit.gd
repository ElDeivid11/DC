class_name UIKit
extends RefCounted
## Lee el kit pixel generado por tools/ui/make_ui_kit.py (ui/kit/manifest.json
## + ui/kit/ui_atlas.png) y arma las piezas del Theme: StyleBoxTexture 9-slice
## y AtlasTexture. Solo lo usan ThemeBuilder (al regenerar el Theme) y los
## tests: en el juego todo llega por el Theme ya guardado.
##
## El manifiesto guarda las regiones en px del atlas (ya escalado ×2) y los
## márgenes y el contenido en píxeles de arte («a»): acá se multiplican por
## UIStyle.PIXEL_SCALE.

const MANIFEST_PATH := "res://ui/kit/manifest.json"

static var _manifest: Dictionary = {}
static var _atlas: Texture2D

static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var text := FileAccess.get_file_as_string(MANIFEST_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			_manifest = parsed
		else:
			push_error("UIKit: no se pudo leer %s" % MANIFEST_PATH)
	return _manifest

static func atlas() -> Texture2D:
	if _atlas == null:
		_atlas = load(String(manifest().get("atlas", "")))
	return _atlas

static func has_sprite(sprite_name: String) -> bool:
	var sprites: Dictionary = manifest().get("sprites", {})
	return sprites.has(sprite_name)

static func _rect(region: Variant) -> Rect2:
	var r: Array = region
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))

## StyleBoxTexture 9-slice de una pieza. El contenido siempre explícito (con
## content_margin = -1 Godot usaría el margen de textura).
static func style(sprite_name: String) -> StyleBoxTexture:
	var sprites: Dictionary = manifest().get("sprites", {})
	var info: Dictionary = sprites.get(sprite_name, {})
	var s := StyleBoxTexture.new()
	if info.is_empty():
		push_error("UIKit: falta la pieza '%s'" % sprite_name)
		return s
	var scale := UIStyle.PIXEL_SCALE
	var m: Array = info.margin
	var cm: Array = info.content
	var axis: Array = info.axis
	s.texture = atlas()
	s.region_rect = _rect(info.region)
	s.texture_margin_left = float(m[0]) * scale
	s.texture_margin_top = float(m[1]) * scale
	s.texture_margin_right = float(m[2]) * scale
	s.texture_margin_bottom = float(m[3]) * scale
	s.content_margin_left = float(cm[0]) * scale
	s.content_margin_top = float(cm[1]) * scale
	s.content_margin_right = float(cm[2]) * scale
	s.content_margin_bottom = float(cm[3]) * scale
	s.axis_stretch_horizontal = _axis(String(axis[0]))
	s.axis_stretch_vertical = _axis(String(axis[1]))
	s.draw_center = bool(info.get("draw_center", true))
	return s

## Igual que style() pero con otro contenido (en px de UI), p. ej. filas de lista.
static func style_with_content(sprite_name: String, left: float, top: float, right: float, bottom: float) -> StyleBoxTexture:
	var s := style(sprite_name)
	s.content_margin_left = left
	s.content_margin_top = top
	s.content_margin_right = right
	s.content_margin_bottom = bottom
	return s

static func _axis(mode: String) -> StyleBoxTexture.AxisStretchMode:
	return StyleBoxTexture.AXIS_STRETCH_MODE_TILE if mode == "tile" else StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH

static func region_texture(region: Variant) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = atlas()
	t.region = _rect(region)
	return t

## Ícono de game-icons en una rampa de color ("bronce", "vela", "apagado"...).
static func icon(icon_id: String, ramp: String) -> AtlasTexture:
	var icons: Dictionary = manifest().get("icons", {})
	var ramps: Dictionary = icons.get(icon_id, {})
	if not ramps.has(ramp):
		push_error("UIKit: el ícono '%s' no tiene la rampa '%s'" % [icon_id, ramp])
		return null
	return region_texture(ramps[ramp])

## Sprite suelto (sello, cimera, pips, llamas de alma, marcadores del mapa...).
static func single(sprite_name: String) -> AtlasTexture:
	var singles: Dictionary = manifest().get("singles", {})
	if not singles.has(sprite_name):
		push_error("UIKit: falta el sprite '%s'" % sprite_name)
		return null
	return region_texture(singles[sprite_name])

## Cuadros de una tira animada (el cursor de llama).
static func frames(strip_name: String) -> Array[AtlasTexture]:
	var out: Array[AtlasTexture] = []
	var strips: Dictionary = manifest().get("frames", {})
	var info: Dictionary = strips.get(strip_name, {})
	if info.is_empty():
		return out
	var region: Array = info.region
	var frame: Array = info.frame
	for i in int(info.count):
		out.append(region_texture([float(region[0]) + i * float(frame[0]), float(region[1]), float(frame[0]), float(frame[1])]))
	return out

static func logo() -> AtlasTexture:
	var info: Dictionary = manifest().get("logo", {})
	return region_texture(info.get("region", [0, 0, 1, 1]))
