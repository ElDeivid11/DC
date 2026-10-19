class_name ThemeBuilder
extends RefCounted
## Construye por código el ÚNICO Theme del juego a partir de los tokens de
## UIStyle y lo guarda en res://ui/theme_main.tres (tema por defecto del
## proyecto: gui/theme/custom). Ninguna pantalla define estilos propios: usan
## los tipos y variaciones de acá.
##
## Regenerar después de tocar este archivo o UIStyle:
##   godot --headless --path . res://tools/build_theme.tscn
##
## Variaciones disponibles (theme_type_variation):
##   Label:          TitleLabel, SubtitleLabel, DimLabel, DetailLabel,
##                   AccentLabel, CoinLabel, SoulLabel, GoodLabel, DangerLabel
##   Button:         MenuItem (ítem de menú en lista), DangerButton, ItemSlot
##   PanelContainer: PanelAlt, ScreenBg, HudPanel, DimOverlay, Card
##   ProgressBar:    HpGood, HpWarn, HpLow, SoulBar, CoinBar, AccentBar

const THEME_PATH := "res://ui/theme_main.tres"
const BOLD_FONT_PATH := "res://assets/fonts/PixelifySans-Bold.woff"
const SYMBOL_FONT_PATHS: Array[String] = [
	"res://assets/fonts/NotoSansSymbols2-Regular.woff",
	"res://assets/fonts/NotoSansSymbols-Regular.woff",
]

static func save_theme() -> Error:
	var theme := build()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(THEME_PATH.get_base_dir()))
	return ResourceSaver.save(theme, THEME_PATH)

static func build() -> Theme:
	var t := Theme.new()
	var regular := _font(UIStyle.FONT_PATH)
	var bold := _font(BOLD_FONT_PATH)
	t.default_font = regular
	t.default_font_size = UIStyle.FONT_BODY

	_labels(t, bold)
	_buttons(t)
	_panels(t)
	_bars(t)
	_inputs(t)
	_tabs_and_scroll(t)
	_popups(t)
	return t

# --- Fuentes --------------------------------------------------------------------

## Fuente pixel con respaldo de símbolos (◈ ✦ ▶ ★ ← ↑ ...), que Pixelify no
## trae. Sin antialiasing: lo fija la importación (.import → antialiasing=0).
static func _font(path: String) -> Font:
	var v := FontVariation.new()
	if ResourceLoader.exists(path):
		v.base_font = load(path)
	else:
		var fallback := SystemFont.new()
		fallback.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		v.base_font = fallback
	var fallbacks: Array[Font] = []
	for p in SYMBOL_FONT_PATHS:
		if ResourceLoader.exists(p):
			fallbacks.append(load(p))
	v.fallbacks = fallbacks
	return v

# --- Helpers de estilo --------------------------------------------------------------

static func _box(bg: Color, border: Color, border_w := UIStyle.BORDER_W, margin_h := 12, margin_v := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(0)
	s.anti_aliasing = false
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	return s

static func _empty(margin_h := 0, margin_v := 0) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	return s

## Icono pixel generado por código: `rows` es un dibujo con "#" = color.
static func _pixel_icon(rows: Array[String], color: Color, scale := 2) -> ImageTexture:
	var h := rows.size()
	var w := rows[0].length()
	var img := Image.create(w * scale, h * scale, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			if rows[y][x] == "#":
				img.fill_rect(Rect2i(x * scale, y * scale, scale, scale), color)
	return ImageTexture.create_from_image(img)

# --- Tipos ------------------------------------------------------------------------

static func _labels(t: Theme, bold: Font) -> void:
	t.set_color("font_color", "Label", UIStyle.TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_constant("line_spacing", "Label", 2)

	var variations := {
		"TitleLabel": [UIStyle.ACCENT, UIStyle.FONT_TITLE, true],
		"SubtitleLabel": [UIStyle.TEXT, UIStyle.FONT_SUBTITLE, true],
		"DimLabel": [UIStyle.TEXT_DIM, UIStyle.FONT_BODY, false],
		"DetailLabel": [UIStyle.TEXT_DIM, UIStyle.FONT_DETAIL, false],
		"AccentLabel": [UIStyle.ACCENT, UIStyle.FONT_BODY, false],
		"CoinLabel": [UIStyle.COIN, UIStyle.FONT_BODY, false],
		"SoulLabel": [UIStyle.SOUL, UIStyle.FONT_BODY, false],
		"GoodLabel": [UIStyle.GOOD, UIStyle.FONT_BODY, false],
		"DangerLabel": [UIStyle.DANGER, UIStyle.FONT_BODY, false],
	}
	for name: String in variations.keys():
		var v: Array = variations[name]
		t.set_type_variation(name, "Label")
		t.set_color("font_color", name, v[0])
		t.set_font_size("font_size", name, v[1])
		if v[2]:
			t.set_font("font", name, bold)

	t.set_color("default_color", "RichTextLabel", UIStyle.TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", UIStyle.FONT_BODY)
	t.set_font("bold_font", "RichTextLabel", bold)

static func _button_styles(t: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox, disabled: StyleBox, focus: StyleBox) -> void:
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, focus)

static func _button_colors(t: Theme, type: String, normal: Color, hot: Color) -> void:
	t.set_color("font_color", type, normal)
	t.set_color("font_hover_color", type, hot)
	t.set_color("font_pressed_color", type, hot)
	t.set_color("font_hover_pressed_color", type, hot)
	t.set_color("font_focus_color", type, hot)
	t.set_color("font_disabled_color", type, UIStyle.TEXT_DIM.darkened(0.3))
	t.set_color("icon_normal_color", type, normal)
	t.set_color("icon_hover_color", type, hot)
	t.set_color("icon_focus_color", type, hot)
	t.set_color("icon_pressed_color", type, hot)

static func _buttons(t: Theme) -> void:
	# Botón estándar: panel oscuro con borde de piedra; foco/hover = ámbar.
	# 12 px de margen vertical + fuente 16 ≈ 40 px de alto mínimo.
	var focus := _box(Color(0, 0, 0, 0), UIStyle.BORDER_FOCUS)
	focus.draw_center = false
	_button_styles(t, "Button",
		_box(UIStyle.PANEL_ALT, UIStyle.BORDER, UIStyle.BORDER_W, 16, 10),
		_box(UIStyle.PANEL_ALT.lightened(0.06), UIStyle.ACCENT.darkened(0.35), UIStyle.BORDER_W, 16, 10),
		_box(UIStyle.BG_DEEP, UIStyle.ACCENT, UIStyle.BORDER_W, 16, 10),
		_box(UIStyle.PANEL, UIStyle.BORDER.darkened(0.4), UIStyle.BORDER_W, 16, 10),
		focus)
	_button_colors(t, "Button", UIStyle.TEXT, UIStyle.ACCENT)
	t.set_constant("h_separation", "Button", 8)

	# Ítem de menú (Hub, pausa): sin caja; el foco marca una franja ámbar a la izquierda.
	t.set_type_variation("MenuItem", "Button")
	var menu_hot := _box(UIStyle.PANEL_ALT, UIStyle.ACCENT, 0, 16, 10)
	menu_hot.border_width_left = 4
	var menu_focus := _box(Color(0, 0, 0, 0), UIStyle.BORDER_FOCUS, 0, 16, 10)
	menu_focus.border_width_left = 4
	menu_focus.draw_center = false
	_button_styles(t, "MenuItem", _empty(20, 10), menu_hot, menu_hot, _empty(20, 10), menu_focus)
	_button_colors(t, "MenuItem", UIStyle.TEXT, UIStyle.ACCENT)
	t.set_font_size("font_size", "MenuItem", UIStyle.FONT_SUBTITLE)

	# Peligro (abandonar run, reiniciar guardado): borde rojo apagado.
	t.set_type_variation("DangerButton", "Button")
	_button_styles(t, "DangerButton",
		_box(UIStyle.PANEL_ALT, UIStyle.DANGER.darkened(0.2), UIStyle.BORDER_W, 16, 10),
		_box(UIStyle.PANEL_ALT.lightened(0.06), UIStyle.DANGER, UIStyle.BORDER_W, 16, 10),
		_box(UIStyle.BG_DEEP, UIStyle.DANGER, UIStyle.BORDER_W, 16, 10),
		_box(UIStyle.PANEL, UIStyle.BORDER.darkened(0.4), UIStyle.BORDER_W, 16, 10),
		focus)
	_button_colors(t, "DangerButton", UIStyle.TEXT, UIStyle.DANGER.lightened(0.3))

	# Casilla de inventario / lista seleccionable: compacta, texto a la izquierda.
	t.set_type_variation("ItemSlot", "Button")
	_button_styles(t, "ItemSlot",
		_box(UIStyle.PANEL, UIStyle.BORDER, UIStyle.BORDER_W, 12, 8),
		_box(UIStyle.PANEL_ALT, UIStyle.ACCENT.darkened(0.35), UIStyle.BORDER_W, 12, 8),
		_box(UIStyle.PANEL_ALT, UIStyle.ACCENT, UIStyle.BORDER_W, 12, 8),
		_box(UIStyle.BG_DEEP, UIStyle.BORDER.darkened(0.4), UIStyle.BORDER_W, 12, 8),
		focus)
	_button_colors(t, "ItemSlot", UIStyle.TEXT, UIStyle.ACCENT)

	# CheckBox: iconos pixel.
	var off := _pixel_icon(["######", "#....#", "#....#", "#....#", "#....#", "######"], UIStyle.BORDER.lightened(0.3), 3)
	var on := _pixel_icon(["######", "#....#", "#.##.#", "#.##.#", "#....#", "######"], UIStyle.ACCENT, 3)
	t.set_icon("checked", "CheckBox", on)
	t.set_icon("unchecked", "CheckBox", off)
	t.set_icon("checked_disabled", "CheckBox", on)
	t.set_icon("unchecked_disabled", "CheckBox", off)
	_button_styles(t, "CheckBox", _empty(8, 8), _box(UIStyle.PANEL_ALT, UIStyle.PANEL_ALT, 0, 8, 8), _empty(8, 8), _empty(8, 8), focus)
	_button_colors(t, "CheckBox", UIStyle.TEXT, UIStyle.ACCENT)
	t.set_constant("h_separation", "CheckBox", 12)

	# OptionButton: flecha pixel.
	t.set_icon("arrow", "OptionButton", _pixel_icon(["#######", ".#####.", "..###..", "...#..."], UIStyle.ACCENT, 2))
	_button_styles(t, "OptionButton",
		_box(UIStyle.PANEL_ALT, UIStyle.BORDER, UIStyle.BORDER_W, 16, 10),
		_box(UIStyle.PANEL_ALT.lightened(0.06), UIStyle.ACCENT.darkened(0.35), UIStyle.BORDER_W, 16, 10),
		_box(UIStyle.BG_DEEP, UIStyle.ACCENT, UIStyle.BORDER_W, 16, 10),
		_box(UIStyle.PANEL, UIStyle.BORDER.darkened(0.4), UIStyle.BORDER_W, 16, 10),
		focus)
	_button_colors(t, "OptionButton", UIStyle.TEXT, UIStyle.ACCENT)

static func _panels(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", _box(UIStyle.PANEL, UIStyle.BORDER, UIStyle.BORDER_W, 16, 16))
	t.set_stylebox("panel", "Panel", _box(UIStyle.PANEL, UIStyle.BORDER, UIStyle.BORDER_W, 16, 16))

	t.set_type_variation("PanelAlt", "PanelContainer")
	t.set_stylebox("panel", "PanelAlt", _box(UIStyle.PANEL_ALT, UIStyle.BORDER, UIStyle.BORDER_W, 12, 12))

	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", _box(UIStyle.PANEL_ALT, UIStyle.BORDER, UIStyle.BORDER_W, 12, 8))

	t.set_type_variation("ScreenBg", "PanelContainer")
	t.set_stylebox("panel", "ScreenBg", _box(UIStyle.BG_DEEP, UIStyle.BG_DEEP, 0, 0, 0))

	t.set_type_variation("HudPanel", "PanelContainer")
	t.set_stylebox("panel", "HudPanel", _box(Color(UIStyle.PANEL, 0.85), UIStyle.BORDER, UIStyle.BORDER_W, 8, 6))

	t.set_type_variation("DimOverlay", "PanelContainer")
	t.set_stylebox("panel", "DimOverlay", _box(Color(UIStyle.BG_DEEP, 0.75), Color(0, 0, 0, 0), 0, 0, 0))

	var sep := StyleBoxLine.new()
	sep.color = UIStyle.BORDER
	sep.thickness = UIStyle.BORDER_W
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 12)
	var vsep := StyleBoxLine.new()
	vsep.color = UIStyle.BORDER
	vsep.thickness = UIStyle.BORDER_W
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	t.set_constant("separation", "VSeparator", 12)

	t.set_constant("separation", "VBoxContainer", UIStyle.SPACE * 2)
	t.set_constant("separation", "HBoxContainer", UIStyle.SPACE * 2)

	t.set_stylebox("panel", "TooltipPanel", _box(UIStyle.PANEL_ALT, UIStyle.ACCENT.darkened(0.3), UIStyle.BORDER_W, 10, 6))
	t.set_color("font_color", "TooltipLabel", UIStyle.TEXT)
	t.set_font_size("font_size", "TooltipLabel", UIStyle.FONT_DETAIL)

static func _bar(t: Theme, type: String, fill: Color) -> void:
	t.set_type_variation(type, "ProgressBar")
	t.set_stylebox("fill", type, _box(fill, fill.lightened(0.2), 0, 0, 0))

static func _bars(t: Theme) -> void:
	t.set_stylebox("background", "ProgressBar", _box(UIStyle.BG_DEEP, UIStyle.BORDER, UIStyle.BORDER_W, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _box(UIStyle.GOOD, UIStyle.GOOD, 0, 0, 0))
	t.set_color("font_color", "ProgressBar", UIStyle.TEXT)
	t.set_font_size("font_size", "ProgressBar", UIStyle.FONT_DETAIL)
	_bar(t, "HpGood", UIStyle.GOOD)
	_bar(t, "HpWarn", UIStyle.ACCENT)
	_bar(t, "HpLow", UIStyle.DANGER)
	_bar(t, "SoulBar", UIStyle.SOUL)
	_bar(t, "CoinBar", UIStyle.COIN)
	_bar(t, "AccentBar", UIStyle.ACCENT)

static func _inputs(t: Theme) -> void:
	t.set_stylebox("normal", "LineEdit", _box(UIStyle.BG_DEEP, UIStyle.BORDER, UIStyle.BORDER_W, 10, 8))
	t.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), UIStyle.BORDER_FOCUS, UIStyle.BORDER_W, 10, 8))
	t.set_stylebox("read_only", "LineEdit", _box(UIStyle.PANEL, UIStyle.BORDER, UIStyle.BORDER_W, 10, 8))
	t.set_color("font_color", "LineEdit", UIStyle.TEXT)
	t.set_color("font_placeholder_color", "LineEdit", UIStyle.TEXT_DIM)
	t.set_color("caret_color", "LineEdit", UIStyle.ACCENT)
	t.set_color("selection_color", "LineEdit", Color(UIStyle.ACCENT, 0.35))

	var track := _box(UIStyle.BG_DEEP, UIStyle.BORDER, UIStyle.BORDER_W, 0, 4)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", _box(UIStyle.ACCENT.darkened(0.3), UIStyle.ACCENT.darkened(0.3), 0, 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(UIStyle.ACCENT, UIStyle.ACCENT, 0, 0, 4))
	var grab := _pixel_icon(["####", "####", "####", "####", "####", "####"], UIStyle.TEXT, 3)
	var grab_hot := _pixel_icon(["####", "####", "####", "####", "####", "####"], UIStyle.ACCENT, 3)
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab_hot)
	t.set_icon("grabber_disabled", "HSlider", grab)
	var slider_focus := _box(Color(0, 0, 0, 0), UIStyle.BORDER_FOCUS, UIStyle.BORDER_W, 0, 0)
	slider_focus.draw_center = false
	t.set_stylebox("focus", "HSlider", slider_focus)

static func _tabs_and_scroll(t: Theme) -> void:
	var sel := _box(UIStyle.PANEL_ALT, UIStyle.ACCENT, 0, 16, 8)
	sel.border_width_bottom = 3
	var unsel := _box(UIStyle.PANEL, UIStyle.BORDER, 0, 16, 8)
	unsel.border_width_bottom = 2
	var hov := _box(UIStyle.PANEL_ALT, UIStyle.ACCENT.darkened(0.35), 0, 16, 8)
	hov.border_width_bottom = 2
	var tfocus := _box(Color(0, 0, 0, 0), UIStyle.BORDER_FOCUS, UIStyle.BORDER_W, 16, 8)
	tfocus.draw_center = false
	for type: String in ["TabBar", "TabContainer"]:
		t.set_stylebox("tab_selected", type, sel)
		t.set_stylebox("tab_unselected", type, unsel)
		t.set_stylebox("tab_hovered", type, hov)
		t.set_stylebox("tab_disabled", type, unsel)
		t.set_stylebox("tab_focus", type, tfocus)
		t.set_color("font_selected_color", type, UIStyle.ACCENT)
		t.set_color("font_hovered_color", type, UIStyle.TEXT)
		t.set_color("font_unselected_color", type, UIStyle.TEXT_DIM)
		t.set_color("font_disabled_color", type, UIStyle.TEXT_DIM.darkened(0.3))
		t.set_constant("h_separation", type, 4)
	t.set_stylebox("panel", "TabContainer", _box(UIStyle.PANEL, UIStyle.BORDER, UIStyle.BORDER_W, 12, 12))
	t.set_stylebox("tabbar_background", "TabContainer", _empty())

	var empty_icon := _pixel_icon(["."], Color(0, 0, 0, 0), 1)
	for type: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, _box(UIStyle.BG_DEEP, UIStyle.BG_DEEP, 0, 4, 4))
		t.set_stylebox("scroll_focus", type, _box(UIStyle.BG_DEEP, UIStyle.BG_DEEP, 0, 4, 4))
		t.set_stylebox("grabber", type, _box(UIStyle.BORDER, UIStyle.BORDER, 0, 4, 4))
		t.set_stylebox("grabber_highlight", type, _box(UIStyle.ACCENT.darkened(0.3), UIStyle.ACCENT, 0, 4, 4))
		t.set_stylebox("grabber_pressed", type, _box(UIStyle.ACCENT, UIStyle.ACCENT, 0, 4, 4))
		for icon: String in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
			t.set_icon(icon, type, empty_icon)

static func _popups(t: Theme) -> void:
	t.set_stylebox("panel", "PopupMenu", _box(UIStyle.PANEL_ALT, UIStyle.BORDER, UIStyle.BORDER_W, 8, 8))
	t.set_stylebox("hover", "PopupMenu", _box(UIStyle.PANEL, UIStyle.ACCENT, 0, 8, 4))
	t.set_color("font_color", "PopupMenu", UIStyle.TEXT)
	t.set_color("font_hover_color", "PopupMenu", UIStyle.ACCENT)
	t.set_color("font_disabled_color", "PopupMenu", UIStyle.TEXT_DIM)
	t.set_stylebox("panel", "PopupPanel", _box(UIStyle.PANEL_ALT, UIStyle.BORDER, UIStyle.BORDER_W, 8, 8))
