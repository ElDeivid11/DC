class_name UIFloorCard
extends CanvasLayer
## Postal del piso: al llegar a un piso aparece arriba la pintura de su
## bioma (assets/art/bioma_*.png, en píxel ×2) con «PISO II DE V» y el
## nombre en gótica; se queda un momento y se va a saltos. No frena el
## juego: se cierra sola o con el primer paso (dismiss).
##   UIFloorCard.show_for(self, 2)

const STEP := 0.066
const HOLD := 2.8
## La postal se muestra a esta escala entera (320×180 → 640×360).
const SCALE := 2

var _panel: PanelContainer
var _closing := false

static func show_for(parent: Node, floor_n: int) -> UIFloorCard:
	var th := DataRegistry.get_theme(floor_n)
	var path := String(th.get("postal", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var card := UIFloorCard.new()
	card._build(load(path), floor_n, String(th.get("nombre", "")))
	parent.add_child(card)
	return card

func _build(tex: Texture2D, floor_n: int, biome: String) -> void:
	layer = 8
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "HudPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_top = 56
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.custom_minimum_size = Vector2(tex.get_size()) * SCALE
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pic)
	var kicker := UILabel.make(DataRegistry.t("hub.last_floor_of", [UIFormat.roman(floor_n), UIFormat.roman(DataRegistry.bal_i("floors_per_run", 5))]).to_upper(), "NumSmallLabel")
	kicker.add_theme_color_override("font_color", UIStyle.ACCENT)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kicker)
	var title := UIGothicLabel.new(biome, "GothicTitle", UIStyle.TEXT, UIStyle.CAPITAL)
	title.align = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

func _ready() -> void:
	_panel.modulate.a = 0.0
	var tw := create_tween()
	for a: float in [0.35, 0.7, 1.0]:
		var alpha := a
		tw.tween_callback(func() -> void: _panel.modulate.a = alpha)
		tw.tween_interval(STEP)
	tw.tween_interval(HOLD)
	tw.tween_callback(dismiss)

## Se va a saltos (una sola vez).
func dismiss() -> void:
	if _closing:
		return
	_closing = true
	var tw := create_tween()
	for a: float in [0.6, 0.3, 0.0]:
		var alpha := a
		tw.tween_callback(func() -> void: _panel.modulate.a = alpha)
		tw.tween_interval(STEP)
	tw.tween_callback(queue_free)
