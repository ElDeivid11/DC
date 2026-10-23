extends TestCase
## Kit pixel de la UI: la paleta de data/ui_palette.json, UIStyle, el atlas y
## su manifiesto (tools/ui/make_ui_kit.py) y el Theme guardado tienen que
## estar sincronizados. Si falla: correr make_ui_kit.py y build_theme.tscn.

const PALETTE_PATH := "res://data/ui_palette.json"
const GENERATOR_PATH := "res://tools/ui/make_ui_kit.py"

func _palette() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_PATH))
	var d: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return d

func test_manifiesto_al_dia() -> void:
	var m := UIKit.manifest()
	eq(String(m.get("palette_sha256", "")), FileAccess.get_sha256(PALETTE_PATH), "el kit se generó con esta paleta (correr make_ui_kit.py)")
	eq(String(m.get("generator_sha256", "")), FileAccess.get_sha256(GENERATOR_PATH), "el kit se generó con este generador (correr make_ui_kit.py)")

func test_paleta_igual_a_uistyle() -> void:
	var data := _palette()
	var pal: Dictionary = data.get("palette", {})
	eq(pal.size(), UIStyle.PALETTE.size(), "misma cantidad de colores")
	for color_name: String in pal.keys():
		check(UIStyle.PALETTE.has(color_name), "UIStyle tiene %s" % color_name)
		if UIStyle.PALETTE.has(color_name):
			var c: Color = UIStyle.PALETTE[color_name]
			check(c.is_equal_approx(Color(String(pal[color_name]))), "%s igual en JSON y UIStyle" % color_name)
	var tokens: Dictionary = data.get("tokens", {})
	for token: String in tokens.keys():
		check(pal.has(String(tokens[token])), "el token %s apunta a un color de la paleta" % token)
		eq(String(UIStyle.TOKENS.get(token, "")), String(tokens[token]), "token %s igual en JSON y UIStyle" % token)
	eq(int(data.get("pixel_scale", 0)), UIStyle.PIXEL_SCALE, "misma escala de píxel")

func test_regiones_dentro_del_atlas() -> void:
	var m := UIKit.manifest()
	var size: Array = m.get("size", [0, 0])
	var atlas := Rect2(0, 0, float(size[0]), float(size[1]))
	var sprites: Dictionary = m.get("sprites", {})
	for sprite_name: String in sprites.keys():
		var info: Dictionary = sprites[sprite_name]
		var r: Array = info.region
		var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		check(atlas.encloses(rect), "%s entra en el atlas" % sprite_name)
		var mg: Array = info.margin
		check((float(mg[0]) + float(mg[2])) * UIStyle.PIXEL_SCALE <= rect.size.x, "%s: márgenes horizontales < ancho" % sprite_name)
		check((float(mg[1]) + float(mg[3])) * UIStyle.PIXEL_SCALE <= rect.size.y, "%s: márgenes verticales < alto" % sprite_name)
	check(UIKit.atlas() != null, "el atlas carga")
	eq(int(UIKit.atlas().get_width()), int(size[0]), "ancho del atlas igual al manifiesto")

func test_iconos_de_uistyle_existen() -> void:
	var icons: Dictionary = UIKit.manifest().get("icons", {})
	for id in UIStyle.ICON_IDS:
		check(icons.has(id), "el kit tiene el ícono %s" % id)
	eq(icons.size(), UIStyle.ICON_IDS.size(), "mismos íconos en el kit y en UIStyle.ICON_IDS")

func test_logo_dice_el_titulo() -> void:
	var logo: Dictionary = UIKit.manifest().get("logo", {})
	eq(String(logo.get("text", "")), DataRegistry.t("app.title"), "el logo horneado coincide con app.title (regenerar el kit si cambia)")

func test_theme_guardado_al_dia() -> void:
	var theme: Theme = load(ThemeBuilder.THEME_PATH)
	check(theme != null, "el Theme carga")
	if theme == null:
		return
	for pair: Array in [["panel", "PanelContainer", "panel_iron"], ["normal", "Button", "button_normal"], ["focus", "Button", "button_focus"]]:
		var sb := theme.get_stylebox(String(pair[0]), String(pair[1])) as StyleBoxTexture
		check(sb != null, "%s/%s es una textura del kit" % [pair[1], pair[0]])
		if sb:
			var info: Dictionary = (UIKit.manifest().get("sprites", {}) as Dictionary).get(String(pair[2]), {})
			var r: Array = info.get("region", [0, 0, 0, 0])
			eq(sb.region_rect, Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])), "%s/%s al día con el manifiesto (correr build_theme)" % [pair[1], pair[0]])
	check(theme.has_icon("logo", "UIIcons"), "el Theme tiene el logo")
	check(theme.has_icon("cursor_0", "UIIcons"), "el Theme tiene el cursor de llama")

func test_fuentes_en_su_grilla() -> void:
	for path: String in [UIStyle.FONT_PATH, UIStyle.FONT_GOTHIC_PATH, UIStyle.FONT_CAP_PATH, UIStyle.FONT_QUOTE_PATH, UIStyle.FONT_NUM_PATH, UIStyle.FONT_LOGO_PATH]:
		check(ResourceLoader.exists(path), "existe %s" % path)
	eq(UIStyle.FONT_GOTHIC % 21, 0, "Jacquard 12 en múltiplos de 21")
	eq(UIStyle.FONT_GOTHIC_CAP % 27, 0, "Jersey 15 (capitular) en múltiplos de 27")
	eq(UIStyle.FONT_HEAD % 27, 0, "Jersey 15 en múltiplos de 27")
	eq(UIStyle.FONT_QUOTE % 13, 0, "Jacquarda Bastarda 9 en múltiplos de 13")
	for s: int in [UIStyle.FONT_NUM_S, UIStyle.FONT_NUM, UIStyle.FONT_NUM_L]:
		eq(s % 11, 0, "Micro 5 en múltiplos de 11")

func test_textos_goticos_sin_simbolos() -> void:
	for key in UIGothicLabel.FIXED_KEYS:
		var text := DataRegistry.t(key)
		check(not text.begins_with("["), "la clave %s existe" % key)
		for sym: String in ["◈", "✦", "★", "▲", "■", "□", "✓", "↑", "↓", "→"]:
			check(not text.contains(sym), "%s no lleva el símbolo %s (las góticas no lo tienen)" % [key, sym])

func test_romanos() -> void:
	eq(UIFormat.roman(1), "I", "1")
	eq(UIFormat.roman(4), "IV", "4")
	eq(UIFormat.roman(9), "IX", "9")
	eq(UIFormat.roman(10), "X", "10")
	eq(UIFormat.roman(14), "XIV", "14")
