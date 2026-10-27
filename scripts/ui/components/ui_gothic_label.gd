class_name UIGothicLabel
extends Control
## Texto gótico del grimorio: minúsculas en Jacquard (títulos) o Jacquarda
## Bastarda (citas) y TODAS las mayúsculas en Jersey 15, porque las fraktur se
## confunden (I parece J, A parece Il). La primera mayúscula es la capitular y
## va en `cap_color`. Sombra dura de tinta (+2, +2). Una sola línea.
##
## style: "GothicTitle" (títulos, ítems del Hub, nombre del enemigo) o
## "GothicQuote" (lemas y citas). Las fuentes salen del Theme (tipos propios).
## Los textos góticos no llevan símbolos (◈ ✦ …): las claves fijas que se usan
## acá figuran en FIXED_KEYS y tests/unit/test_ui_kit.gd las revisa.

const FIXED_KEYS: Array[String] = [
	"app.subtitle", "hub.start", "hub.heroes", "heroes.title", "hub.upgrades", "hub.unlocks", "hub.bestiary", "hub.stats",
	"hub.options", "hub.quit", "hub.no_runs", "pause.title", "pause.continue", "pause.status",
	"pause.inventory", "pause.map", "pause.options", "pause.abandon", "summary.epitaph_death",
	"summary.epitaph_victory", "summary.epitaph_retire", "summary.epitaph_abandon",
	"combat.soul_title", "combat.soul_choice_title", "upgrades.title", "unlocks.title", "bestiary.title",
	"stats.title", "options.title", "status.title", "inventory.title",
	"combat.victory_title", "summary.souls_note",
	"combat.defeat_title", "combat.fled_title", "combat.replace_title", "exit.title", "exit.title_last",
	"stats.no_kills",
]
const SHADOW := 2

var text := "":
	set(value):
		text = value
		update_minimum_size()
		queue_redraw()
var style := "GothicTitle"
var color := UIStyle.TEXT
var cap_color := UIStyle.CAPITAL
var align := HORIZONTAL_ALIGNMENT_LEFT

func _init(p_text := "", p_style := "GothicTitle", p_color := UIStyle.TEXT, p_cap_color := UIStyle.CAPITAL) -> void:
	text = p_text
	style = p_style
	color = p_color
	cap_color = p_cap_color
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

func set_text(t: String) -> void:
	text = t

func set_colors(p_color: Color, p_cap_color: Color) -> void:
	color = p_color
	cap_color = p_cap_color
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		update_minimum_size()
		queue_redraw()

func _low() -> Font:
	return get_theme_font("font_low", style)

func _cap() -> Font:
	return get_theme_font("font_cap", style)

func _low_size() -> int:
	return get_theme_font_size("font_size_low", style)

func _cap_size() -> int:
	return get_theme_font_size("font_size_cap", style)

static func _is_cap(ch: String) -> bool:
	return ch != ch.to_lower()

## Tramos [texto, es_mayúscula].
func _runs() -> Array:
	var runs: Array = []
	var cur := ""
	var cur_cap := false
	for i in text.length():
		var ch := text[i]
		var is_cap := _is_cap(ch)
		if cur != "" and is_cap != cur_cap:
			runs.append([cur, cur_cap])
			cur = ""
		cur += ch
		cur_cap = is_cap
	if cur != "":
		runs.append([cur, cur_cap])
	return runs

func _run_width(run: Array) -> float:
	var is_cap: bool = run[1]
	var font := _cap() if is_cap else _low()
	return font.get_string_size(String(run[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, _cap_size() if is_cap else _low_size()).x

func _text_width() -> float:
	var w := 0.0
	for run: Array in _runs():
		w += _run_width(run)
	return w

func _get_minimum_size() -> Vector2:
	var low := _low()
	var h := low.get_ascent(_low_size()) + low.get_descent(_low_size()) + SHADOW
	return Vector2(ceilf((_text_width() + SHADOW) / 2.0) * 2.0, ceilf(h / 2.0) * 2.0)

func _draw() -> void:
	if text == "":
		return
	var low := _low()
	var width := _text_width()
	var x0 := 0.0
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x0 = (size.x - width - SHADOW) / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x0 = size.x - width - SHADOW
	var line_h := low.get_ascent(_low_size()) + low.get_descent(_low_size())
	var baseline := (size.y - line_h - SHADOW) / 2.0 + low.get_ascent(_low_size())
	# Alineado a la grilla de 2 px (sin medios píxeles).
	x0 = roundf(x0 / 2.0) * 2.0
	baseline = roundf(baseline / 2.0) * 2.0
	for pass_i in 2:
		var x := x0
		var capital_done := false
		for run: Array in _runs():
			var is_cap: bool = run[1]
			var font := _cap() if is_cap else _low()
			var fsize := _cap_size() if is_cap else _low_size()
			var s := String(run[0])
			if pass_i == 0:
				draw_string(font, Vector2(x + SHADOW, baseline + SHADOW), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, UIStyle.INK)
			elif is_cap and not capital_done:
				# Capitular: solo la primera mayúscula del texto.
				var first := s.substr(0, 1)
				draw_string(font, Vector2(x, baseline), first, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, cap_color)
				var fw := font.get_string_size(first, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
				if s.length() > 1:
					draw_string(font, Vector2(x + fw, baseline), s.substr(1), HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)
			else:
				draw_string(font, Vector2(x, baseline), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)
			if is_cap:
				capital_done = true
			x += font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
