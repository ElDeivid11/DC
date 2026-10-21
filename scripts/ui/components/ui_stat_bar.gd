class_name UIStatBar
extends HBoxContainer
## Barra con nombre y valor: "Bjorn ▮▮▮▮▮▯ 14/18", en marco de hierro hundido.
## kind: "hp" (siempre rojo sangre; con < 25% destella), "enemy" (más gruesa),
## "soul", "coin", "accent" (bronce), "xp" y "xp_thin" (amatista).
## Al bajar, un rastro claro se queda en el valor anterior y lo sigue en 0,4 s.

const LOW := 0.25
const FLASH_EVERY := 0.8
const FLASH_TIME := 0.066
const KINDS := {
	"hp": ["HpGood", 16], "enemy": ["EnemyBar", 20], "soul": ["SoulBar", 16], "coin": ["CoinBar", 16],
	"accent": ["AccentBar", 16], "xp": ["XpBar", 14], "xp_thin": ["XpThinBar", 10],
}

var kind := "hp"
var name_label: Label
var bar: ProgressBar
var trail: ProgressBar
var value_label: Label
var _fraction := 1.0
var _flash_t := 0.0
var _trail_tween: Tween

func _init(p_name := "", p_kind := "hp", bar_width := 120) -> void:
	kind = p_kind if KINDS.has(p_kind) else "hp"
	add_theme_constant_override("separation", 8)
	name_label = Label.new()
	name_label.theme_type_variation = "SubtitleLabel"
	name_label.text = p_name
	name_label.visible = p_name != ""
	name_label.custom_minimum_size.x = 64
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(name_label)
	var info: Array = KINDS[kind]
	var stack := MarginContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.custom_minimum_size = Vector2(bar_width, int(info[1]))
	add_child(stack)
	# Atrás: marco + rastro. Adelante: el relleno (sin fondo propio).
	trail = _make_bar("TrailBar")
	stack.add_child(trail)
	bar = _make_bar(String(info[0]))
	bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	stack.add_child(bar)
	value_label = Label.new()
	value_label.theme_type_variation = "NumSmallLabel"
	value_label.custom_minimum_size.x = 56
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(value_label)
	set_process(kind == "hp")

func _make_bar(variation: String) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.theme_type_variation = variation
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

func set_values(value: int, max_value: int) -> void:
	var top := maxi(max_value, 1)
	for b: ProgressBar in [bar, trail]:
		b.max_value = top
		b.value = clampi(value, 0, top)
	value_label.text = "%d/%d" % [maxi(value, 0), max_value]
	_fraction = float(maxi(value, 0)) / float(top)

## Al bajar, el rastro se queda en el valor anterior y lo alcanza por pasos.
func animate_to(value: int, max_value: int) -> void:
	var top := maxi(max_value, 1)
	var target := float(clampi(value, 0, top))
	bar.max_value = top
	trail.max_value = top
	value_label.text = "%d/%d" % [maxi(value, 0), max_value]
	_fraction = float(maxi(value, 0)) / float(top)
	if _trail_tween:
		_trail_tween.kill()
	if target >= trail.value:
		bar.value = target
		trail.value = target
		return
	bar.value = target
	_trail_tween = create_tween()
	_trail_tween.tween_interval(0.12)
	_trail_tween.tween_property(trail, "value", target, 0.4)

func set_name_text(t: String) -> void:
	name_label.text = t
	name_label.visible = t != ""

## HP bajo: destello corto cada 0,8 s (el color de la barra no cambia).
func _process(delta: float) -> void:
	if _fraction >= LOW or _fraction <= 0.0:
		if bar.theme_type_variation != "HpGood":
			bar.theme_type_variation = "HpGood"
		return
	_flash_t += delta
	var phase := fmod(_flash_t, FLASH_EVERY)
	bar.theme_type_variation = "HpFlash" if phase < FLASH_TIME else "HpGood"
