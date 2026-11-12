class_name ThemeBuilder
extends RefCounted
## Construye por código el ÚNICO Theme del juego («Grimorio de la Cripta») a
## partir de los tokens de UIStyle y del kit pixel (UIKit: ui/kit/manifest.json
## + ui_atlas.png) y lo guarda en res://ui/theme_main.tres (tema por defecto del
## proyecto: gui/theme/custom). Ninguna pantalla define estilos propios: usan
## los tipos y variaciones de acá.
##
## Regenerar después de tocar este archivo, UIStyle o el kit:
##   python3 -I tools/ui/make_ui_kit.py
##   godot --headless --path . res://tools/build_theme.tscn
##
## Variaciones (theme_type_variation):
##   Label:          HeadLabel, SubtitleLabel, DimLabel, DetailLabel, AccentLabel,
##                   GoodLabel, DangerLabel, SoulLabel, NumLabel, NumSmallLabel,
##                   NumBigLabel, CoinLabel, CoinBigLabel, CoinDangerLabel,
##                   DamageLabel, HealLabel, XpLabel, RankLabel1…RankLabel10, TooltipLabel
##   Button:         MenuItem, DangerButton, ItemSlot, ItemSlotLocked, NicheSlot
##   PanelContainer: PanelAlt, HudPanel, Card, CardSoul, CardFocus, PortraitFrame,
##                   PortraitFrameActive, RankPlaque, KeyCap, ToastPanel, RibbonSmall,
##                   DimOverlay, ScreenBg
##   ProgressBar:    HpGood, HpWarn, HpLow, HpFlash, EnemyBar, SoulBar, XpBar,
##                   XpThinBar, CoinBar, AccentBar, TrailBar
##   Tipos propios:  GothicTitle / GothicQuote (fuentes de UIGothicLabel) y
##                   UIIcons (íconos, cursor, pips, sellos, marcadores, logo)

const THEME_PATH := "res://ui/theme_main.tres"

static func save_theme() -> Error:
	var theme := build()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(THEME_PATH.get_base_dir()))
	return ResourceSaver.save(theme, THEME_PATH)

static func build() -> Theme:
	var t := Theme.new()
	var body := _font(UIStyle.FONT_PATH, false)
	var head := _font(UIStyle.FONT_CAP_PATH)
	var num := _font(UIStyle.FONT_NUM_PATH)
	t.default_font = body
	t.default_font_size = UIStyle.FONT_BODY

	_labels(t, body, head, num)
	_gothic(t)
	_buttons(t, head)
	_panels(t)
	_bars(t)
	_inputs(t, head)
	_tabs_and_scroll(t, head)
	_popups(t)
	_icons(t)
	return t

# --- Fuentes --------------------------------------------------------------------

## Fuente pixel con respaldos: Pixelify (para letras que falten) y las Noto de
## símbolos (◈ ✦ ▶ ★ ← ↑ ...). Sin antialiasing: lo fija cada .import.
static func _font(path: String, with_body_fallback := true) -> Font:
	var v := FontVariation.new()
	if ResourceLoader.exists(path):
		v.base_font = load(path)
	else:
		var system := SystemFont.new()
		system.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		v.base_font = system
	var fallbacks: Array[Font] = []
	if with_body_fallback and ResourceLoader.exists(UIStyle.FONT_PATH):
		fallbacks.append(load(UIStyle.FONT_PATH))
	for p in UIStyle.FONT_FALLBACK_PATHS:
		if ResourceLoader.exists(p):
			fallbacks.append(load(p))
	v.fallbacks = fallbacks
	return v

# --- Helpers ----------------------------------------------------------------------

static func _flat(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.anti_aliasing = false
	s.set_content_margin_all(0)
	return s

static func _empty(h := 0.0, v := 0.0) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = h
	s.content_margin_right = h
	s.content_margin_top = v
	s.content_margin_bottom = v
	return s

static func _button_styles(t: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox, disabled: StyleBox, focus: StyleBox) -> void:
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, focus)
	t.set_constant("align_to_largest_stylebox", type, 1)

static func _button_colors(t: Theme, type: String, normal: Color, hot: Color, disabled := UIStyle.TEXT_OFF) -> void:
	t.set_color("font_color", type, normal)
	t.set_color("font_hover_color", type, hot)
	t.set_color("font_pressed_color", type, hot)
	t.set_color("font_hover_pressed_color", type, hot)
	t.set_color("font_focus_color", type, hot)
	t.set_color("font_disabled_color", type, disabled)
	t.set_color("font_outline_color", type, UIStyle.INK)
	for state: String in ["icon_normal_color", "icon_hover_color", "icon_focus_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		t.set_color(state, type, Color.WHITE)
	t.set_color("icon_disabled_color", type, UIStyle.TEXT_OFF)

# --- Tipos ------------------------------------------------------------------------

static func _labels(t: Theme, body: Font, head: Font, num: Font) -> void:
	t.set_color("font_color", "Label", UIStyle.TEXT)
	t.set_color("font_shadow_color", "Label", UIStyle.INK)
	t.set_constant("shadow_offset_x", "Label", 2)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_constant("line_spacing", "Label", 2)

	# nombre → [fuente, tamaño, color]
	var variations := {
		"HeadLabel": [head, UIStyle.FONT_HEAD, UIStyle.ACCENT],
		"SubtitleLabel": [head, UIStyle.FONT_HEAD, UIStyle.TEXT],
		"DimLabel": [body, UIStyle.FONT_BODY, UIStyle.TEXT_DIM],
		"DetailLabel": [body, UIStyle.FONT_DETAIL, UIStyle.TEXT_DIM],
		"AccentLabel": [body, UIStyle.FONT_BODY, UIStyle.ACCENT],
		"GoodLabel": [body, UIStyle.FONT_BODY, UIStyle.GOOD],
		"DangerLabel": [body, UIStyle.FONT_BODY, UIStyle.DANGER],
		"SoulLabel": [body, UIStyle.FONT_BODY, UIStyle.SOUL],
		"NumLabel": [num, UIStyle.FONT_NUM, UIStyle.TEXT],
		"NumSmallLabel": [num, UIStyle.FONT_NUM_S, UIStyle.TEXT_DIM],
		"NumBigLabel": [num, UIStyle.FONT_NUM_L, UIStyle.TEXT],
		"CoinLabel": [num, UIStyle.FONT_NUM, UIStyle.COIN],
		"CoinBigLabel": [num, UIStyle.FONT_NUM_L, UIStyle.COIN],
		"CoinDangerLabel": [num, UIStyle.FONT_NUM, UIStyle.DANGER],
		"DamageLabel": [num, UIStyle.FONT_NUM_L, UIStyle.DANGER],
		"HealLabel": [num, UIStyle.FONT_NUM_L, UIStyle.GOOD],
		"XpLabel": [num, UIStyle.FONT_NUM_S, UIStyle.XP],
		"TooltipLabel": [body, UIStyle.FONT_DETAIL, UIStyle.TEXT],
	}
	for rank in range(1, 11):
		variations["RankLabel%d" % rank] = [num, UIStyle.FONT_NUM_S, UIStyle.rank_color(rank)]
	for name: String in variations.keys():
		var v: Array = variations[name]
		t.set_type_variation(name, "Label")
		t.set_font("font", name, v[0])
		t.set_font_size("font_size", name, v[1])
		t.set_color("font_color", name, v[2])
	# TooltipLabel es además el tipo nativo de los tooltips de Godot.
	t.set_color("font_color", "TooltipLabel", UIStyle.TEXT)
	t.set_font_size("font_size", "TooltipLabel", UIStyle.FONT_DETAIL)

	t.set_color("default_color", "RichTextLabel", UIStyle.TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", UIStyle.FONT_BODY)
	t.set_font("bold_font", "RichTextLabel", head)

## Fuentes de UIGothicLabel: minúsculas góticas + mayúsculas de Jersey 15.
static func _gothic(t: Theme) -> void:
	var cap := _font(UIStyle.FONT_CAP_PATH)
	t.set_font("font_low", "GothicTitle", _font(UIStyle.FONT_GOTHIC_PATH))
	t.set_font("font_cap", "GothicTitle", cap)
	t.set_font_size("font_size_low", "GothicTitle", UIStyle.FONT_GOTHIC)
	t.set_font_size("font_size_cap", "GothicTitle", UIStyle.FONT_GOTHIC_CAP)
	t.set_font("font_low", "GothicQuote", _font(UIStyle.FONT_QUOTE_PATH))
	t.set_font("font_cap", "GothicQuote", cap)
	t.set_font_size("font_size_low", "GothicQuote", UIStyle.FONT_QUOTE)
	t.set_font_size("font_size_cap", "GothicQuote", UIStyle.FONT_QUOTE_CAP)

static func _buttons(t: Theme, head: Font) -> void:
	# Botón de piedra tallada; el foco es un aro de brasa superpuesto.
	_button_styles(t, "Button", UIKit.style("button_normal"), UIKit.style("button_normal"),
		UIKit.style("button_pressed"), UIKit.style("button_disabled"), UIKit.style("button_focus"))
	_button_colors(t, "Button", UIStyle.TEXT, UIStyle.ACCENT)
	t.set_font("font", "Button", head)
	t.set_font_size("font_size", "Button", UIStyle.FONT_HEAD)
	t.set_constant("h_separation", "Button", 8)
	t.set_constant("icon_max_width", "Button", UIStyle.ICON_SIZE)

	t.set_type_variation("DangerButton", "Button")
	_button_styles(t, "DangerButton", UIKit.style("button_normal"), UIKit.style("button_normal"),
		UIKit.style("button_pressed"), UIKit.style("button_disabled"), UIKit.style("button_danger_focus"))
	_button_colors(t, "DangerButton", UIStyle.DANGER, UIStyle.ACCENT)

	# Ítem de menú (Hub, pausa): sin caja; el foco es una banda de brasa que se
	# desvanece. El texto lo dibuja UIMenuItem (cursor + ícono + gótica).
	t.set_type_variation("MenuItem", "Button")
	_button_styles(t, "MenuItem", _empty(), _empty(), _empty(), _empty(), UIKit.style("menu_band"))
	_button_colors(t, "MenuItem", UIStyle.TEXT, UIStyle.ACCENT)

	# Fila de lista (Mejoras, Bestiario, inventario en lista): piedra con lugar
	# a la izquierda para el cursor de llama.
	var row_px := float(UIStyle.PIXEL_SCALE)
	for type: String in ["ItemSlot", "ItemSlotLocked"]:
		t.set_type_variation(type, "Button")
		_button_styles(t, type,
			UIKit.style_with_content("button_normal", 14 * row_px, 3 * row_px, 6 * row_px, 3 * row_px),
			UIKit.style_with_content("button_normal", 14 * row_px, 3 * row_px, 6 * row_px, 3 * row_px),
			UIKit.style_with_content("button_pressed", 14 * row_px, 3 * row_px, 6 * row_px, 3 * row_px),
			UIKit.style_with_content("button_disabled", 14 * row_px, 3 * row_px, 6 * row_px, 3 * row_px),
			UIKit.style_with_content("button_focus", 14 * row_px, 3 * row_px, 6 * row_px, 3 * row_px))
		t.set_font("font", type, _font(UIStyle.FONT_PATH, false))
		t.set_font_size("font_size", type, UIStyle.FONT_BODY)
		t.set_constant("icon_max_width", type, UIStyle.ICON_SIZE)
		t.set_constant("h_separation", type, 8)
	_button_colors(t, "ItemSlot", UIStyle.TEXT, UIStyle.ACCENT)
	_button_colors(t, "ItemSlotLocked", UIStyle.TEXT_DIM, UIStyle.TEXT)

	# Nicho de piedra (morral): el retrato va como ícono.
	t.set_type_variation("NicheSlot", "Button")
	_button_styles(t, "NicheSlot", UIKit.style("slot_normal"), UIKit.style("slot_normal"),
		UIKit.style("slot_normal"), UIKit.style("slot_empty"), UIKit.style("slot_focus"))
	_button_colors(t, "NicheSlot", UIStyle.TEXT, UIStyle.ACCENT)
	t.set_constant("icon_max_width", "NicheSlot", 64)
	t.set_constant("h_separation", "NicheSlot", 0)

	# CheckBox: casilla de nicho; el foco, el aro de brasa.
	var check_pad := 3.0 * UIStyle.PIXEL_SCALE
	_button_styles(t, "CheckBox", _empty(0, check_pad), _empty(0, check_pad), _empty(0, check_pad), _empty(0, check_pad), UIKit.style("button_focus"))
	_button_colors(t, "CheckBox", UIStyle.TEXT, UIStyle.ACCENT)
	t.set_icon("checked", "CheckBox", UIKit.single("check_on"))
	t.set_icon("unchecked", "CheckBox", UIKit.single("check_off"))
	t.set_icon("checked_disabled", "CheckBox", UIKit.single("check_on"))
	t.set_icon("unchecked_disabled", "CheckBox", UIKit.single("check_off"))
	t.set_constant("h_separation", "CheckBox", 12)

	# OptionButton: como un botón, con flecha de bronce.
	_button_styles(t, "OptionButton", UIKit.style("button_normal"), UIKit.style("button_normal"),
		UIKit.style("button_pressed"), UIKit.style("button_disabled"), UIKit.style("button_focus"))
	_button_colors(t, "OptionButton", UIStyle.TEXT, UIStyle.ACCENT)
	t.set_font("font", "OptionButton", head)
	t.set_font_size("font_size", "OptionButton", UIStyle.FONT_HEAD)
	t.set_icon("arrow", "OptionButton", UIKit.single("option_arrow"))
	t.set_constant("arrow_margin", "OptionButton", 12)

static func _panels(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", UIKit.style("panel_iron"))
	t.set_stylebox("panel", "Panel", UIKit.style("panel_iron"))
	var variations := {
		"PanelAlt": "panel_inset", "HudPanel": "panel_hud", "Card": "card", "CardSoul": "card_soul",
		"CardFocus": "card_focus", "PortraitFrame": "portrait_frame", "PortraitFrameActive": "portrait_frame_active",
		"RankPlaque": "rank_plaque", "KeyCap": "keycap", "ToastPanel": "ribbon", "RibbonSmall": "ribbon_small",
	}
	for name: String in variations.keys():
		t.set_type_variation(name, "PanelContainer")
		t.set_stylebox("panel", name, UIKit.style(String(variations[name])))
	t.set_type_variation("ScreenBg", "PanelContainer")
	t.set_stylebox("panel", "ScreenBg", _flat(UIStyle.BG_DEEP))
	t.set_type_variation("DimOverlay", "PanelContainer")
	t.set_stylebox("panel", "DimOverlay", _flat(UIStyle.VEIL))

	t.set_stylebox("separator", "HSeparator", UIKit.style("separator"))
	t.set_constant("separation", "HSeparator", 2 * UIStyle.PIXEL_SCALE)
	t.set_stylebox("separator", "VSeparator", UIKit.style("separator_v"))
	t.set_constant("separation", "VSeparator", 2 * UIStyle.PIXEL_SCALE)

	for type: String in ["BoxContainer", "VBoxContainer", "HBoxContainer"]:
		t.set_constant("separation", type, UIStyle.SPACE * 2)
	t.set_constant("h_separation", "GridContainer", UIStyle.SPACE * 2)
	t.set_constant("v_separation", "GridContainer", UIStyle.SPACE * 2)

	t.set_stylebox("panel", "TooltipPanel", UIKit.style("tooltip"))

## ProgressBar dibuja el relleno sobre todo el alto: con márgenes de expansión
## negativos (el grosor del marco) queda adentro del marco de hierro.
static func _fill(fill: String) -> StyleBoxTexture:
	var s := UIKit.style(fill)
	var inset := -2.0 * UIStyle.PIXEL_SCALE
	s.expand_margin_left = inset
	s.expand_margin_top = inset
	s.expand_margin_right = inset
	s.expand_margin_bottom = inset
	return s

static func _bar(t: Theme, type: String, fill: String, background := "bar_frame") -> void:
	t.set_type_variation(type, "ProgressBar")
	t.set_stylebox("fill", type, _fill(fill))
	t.set_stylebox("background", type, UIKit.style(background))

static func _bars(t: Theme) -> void:
	t.set_stylebox("background", "ProgressBar", UIKit.style("bar_frame"))
	t.set_stylebox("fill", "ProgressBar", _fill("bar_fill_progress"))
	t.set_color("font_color", "ProgressBar", UIStyle.TEXT)
	t.set_font_size("font_size", "ProgressBar", UIStyle.FONT_DETAIL)
	for type: String in ["HpGood", "HpWarn", "HpLow"]:
		_bar(t, type, "bar_fill_hp")
	_bar(t, "HpFlash", "bar_fill_flash")
	_bar(t, "EnemyBar", "bar_fill_enemy")
	_bar(t, "SoulBar", "bar_fill_soul")
	_bar(t, "XpBar", "bar_fill_exp")
	_bar(t, "XpThinBar", "bar_fill_exp_thin")
	_bar(t, "CoinBar", "bar_fill_coin")
	_bar(t, "AccentBar", "bar_fill_progress")
	_bar(t, "TrailBar", "bar_fill_trail")

static func _inputs(t: Theme, head: Font) -> void:
	t.set_stylebox("normal", "LineEdit", UIKit.style("panel_inset"))
	t.set_stylebox("focus", "LineEdit", UIKit.style("button_focus"))
	t.set_stylebox("read_only", "LineEdit", UIKit.style("panel_inset"))
	t.set_color("font_color", "LineEdit", UIStyle.TEXT)
	t.set_color("font_placeholder_color", "LineEdit", UIStyle.TEXT_DIM)
	t.set_color("caret_color", "LineEdit", UIStyle.ACCENT)
	t.set_color("selection_color", "LineEdit", Color(UIStyle.EMBER, 0.35))
	t.set_font("font", "LineEdit", head)

	t.set_stylebox("slider", "HSlider", UIKit.style("bar_frame"))
	t.set_stylebox("grabber_area", "HSlider", UIKit.style("bar_fill_progress"))
	t.set_stylebox("grabber_area_highlight", "HSlider", UIKit.style("bar_fill_progress"))
	t.set_stylebox("focus", "HSlider", UIKit.style("bar_focus"))
	t.set_icon("grabber", "HSlider", UIKit.single("slider_grabber"))
	t.set_icon("grabber_highlight", "HSlider", UIKit.single("slider_grabber_focus"))
	t.set_icon("grabber_disabled", "HSlider", UIKit.single("slider_grabber"))

static func _tabs_and_scroll(t: Theme, head: Font) -> void:
	for type: String in ["TabBar", "TabContainer"]:
		t.set_stylebox("tab_selected", type, UIKit.style("tab_selected"))
		t.set_stylebox("tab_unselected", type, UIKit.style("tab_normal"))
		t.set_stylebox("tab_hovered", type, UIKit.style("tab_normal"))
		t.set_stylebox("tab_disabled", type, UIKit.style("tab_normal"))
		t.set_stylebox("tab_focus", type, UIKit.style("tab_focus"))
		t.set_color("font_selected_color", type, UIStyle.ACCENT)
		t.set_color("font_hovered_color", type, UIStyle.TEXT)
		t.set_color("font_unselected_color", type, UIStyle.TEXT_DIM)
		t.set_color("font_disabled_color", type, UIStyle.TEXT_OFF)
		t.set_color("font_outline_color", type, UIStyle.INK)
		t.set_font("font", type, head)
		t.set_font_size("font_size", type, UIStyle.FONT_HEAD)
		t.set_constant("h_separation", type, 8)
		t.set_constant("icon_max_width", type, UIStyle.ICON_SIZE)
	t.set_stylebox("panel", "TabContainer", UIKit.style("panel_inset"))
	t.set_stylebox("tabbar_background", "TabContainer", _empty())

	var none := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	for type: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, UIKit.style("scroll_track"))
		t.set_stylebox("scroll_focus", type, UIKit.style("scroll_track"))
		t.set_stylebox("grabber", type, UIKit.style("scroll_grabber"))
		t.set_stylebox("grabber_highlight", type, UIKit.style("scroll_grabber_hot"))
		t.set_stylebox("grabber_pressed", type, UIKit.style("scroll_grabber_hot"))
		for icon: String in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
			t.set_icon(icon, type, none)

static func _popups(t: Theme) -> void:
	t.set_stylebox("panel", "PopupMenu", UIKit.style("card"))
	t.set_stylebox("hover", "PopupMenu", _flat(Color(UIStyle.BRASA_OSC, 0.43)))
	t.set_color("font_color", "PopupMenu", UIStyle.TEXT)
	t.set_color("font_hover_color", "PopupMenu", UIStyle.ACCENT)
	t.set_color("font_disabled_color", "PopupMenu", UIStyle.TEXT_OFF)
	t.set_stylebox("panel", "PopupPanel", UIKit.style("card"))

## Íconos del kit en el tipo propio UIIcons: <id>_<rampa>, cursor_0..4, los
## sprites sueltos (pips, llamas de alma, sellos, cimera, marcadores) y el logo.
static func _icons(t: Theme) -> void:
	var icons: Dictionary = UIKit.manifest().get("icons", {})
	for icon_id: String in icons.keys():
		var ramps: Dictionary = icons[icon_id]
		for ramp: String in ramps.keys():
			t.set_icon("%s_%s" % [icon_id, ramp], "UIIcons", UIKit.icon(icon_id, ramp))
	var singles: Dictionary = UIKit.manifest().get("singles", {})
	for single_name: String in singles.keys():
		t.set_icon(single_name, "UIIcons", UIKit.single(single_name))
	var flame := UIKit.frames("cursor_flame")
	for i in flame.size():
		t.set_icon("cursor_%d" % i, "UIIcons", flame[i])
	t.set_icon("logo", "UIIcons", UIKit.logo())
