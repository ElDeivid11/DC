class_name HeroesScreen
extends UIScreen
## Héroes (Hub): nombre y apariencia de cada personaje del equipo, una
## pestaña por héroe (Q/E). A la izquierda, el retrato grande (×4) con el
## nombre y los botones Al azar / Como al principio; a la derecha, una fila
## por parte y por color (← → los cambian). Se guarda al instante
## (MetaState.set_hero) y lo ve la próxima expedición: HUD, combate, Estado.
## Es solo apariencia: no cambia estadísticas.

const PORTRAIT := 192
## Orden de las filas: cada parte junto a su color.
const ROWS: Array[String] = ["cara", "color_piel", "ojos", "color_ojos", "boca", "marca", "pelo", "color_pelo",
	"barba", "tocado", "color_capa", "ropa", "color_ropa"]

var tabs: UITabs
## Uno por héroe: {id, portrait, name, selectors: {clave: UISelector}, first}.
var _editors: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	super(DataRegistry.t("heroes.title"))

func _ready() -> void:
	super._ready()
	_rng.randomize()
	tabs = UITabs.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	for m: Variant in DataRegistry.bal("party", []):
		var id := String((m as Dictionary).get("id", ""))
		tabs.add_tab(MetaState.hero_name(id), _editor(id), "estado")
	tabs.tab_changed.connect(func(_i: int) -> void: _focus_current())
	add_footer_hint(DataRegistry.t("heroes.hint"))
	add_footer_button(DataRegistry.t("ui.back"), close)
	_focus_current.call_deferred()

func _editor(id: String) -> Control:
	var look := MetaState.hero_look(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIStyle.SPACE * 6)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", UIStyle.SPACE * 3)
	row.add_child(left)
	var portrait := UIPortrait.new(null, PORTRAIT)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(portrait)
	left.add_child(UILabel.make(DataRegistry.t("heroes.name"), "DimLabel"))
	var name_edit := LineEdit.new()
	name_edit.text = MetaState.hero_name(id)
	name_edit.max_length = 16
	name_edit.placeholder_text = DataRegistry.t("heroes.name_placeholder")
	name_edit.custom_minimum_size.x = PORTRAIT + 24
	left.add_child(name_edit)
	var random := UIButton.make(DataRegistry.t("heroes.random"), func() -> void: _randomize(id))
	var reset := UIButton.make(DataRegistry.t("heroes.reset"), func() -> void: _reset(id))
	left.add_child(random)
	left.add_child(reset)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	row.add_child(list)
	var selectors := {}
	var chain: Array[Control] = [name_edit, random, reset]
	for key in ROWS:
		var colors := Callable()
		if key.begins_with("color_"):
			var ck := key.substr(6)
			colors = func(i: int) -> Color:
				var tones := DataRegistry.look_tones(ck, i)
				return Color.html(String(tones[mini(1, tones.size() - 1)]))
		var names := func(i: int) -> String: return DataRegistry.look_value_name(key, i)
		var sel := UISelector.new(DataRegistry.look_label(key), DataRegistry.look_options(key), int(look.get(key, 0)), names, colors)
		sel.changed.connect(func(_i: int) -> void: _save(id))
		list.add_child(sel)
		selectors[key] = sel
		chain.append(sel)
	UIFocus.chain_vertical(chain)
	name_edit.text_changed.connect(func(_t: String) -> void: _save(id))
	var ed := {"id": id, "portrait": portrait, "name": name_edit, "selectors": selectors, "first": chain[3]}
	_editors.append(ed)
	portrait.set_hero(id)
	return row

func _editor_of(id: String) -> Dictionary:
	for ed in _editors:
		if String(ed.id) == id:
			return ed
	return {}

## Guarda lo que muestra el editor y actualiza el retrato y la pestaña.
func _save(id: String) -> void:
	var ed := _editor_of(id)
	var look := {}
	for key: String in (ed.selectors as Dictionary).keys():
		look[key] = (ed.selectors[key] as UISelector).index
	var p_name := (ed.name as LineEdit).text.strip_edges()
	MetaState.set_hero(id, p_name, look)
	SaveSystem.save_meta()
	(ed.portrait as UIPortrait).set_hero(id)
	tabs.tab_bar.set_tab_title(_editors.find(ed), MetaState.hero_name(id))

func _apply(id: String, look: Dictionary, p_name: String) -> void:
	var ed := _editor_of(id)
	for key: String in (ed.selectors as Dictionary).keys():
		(ed.selectors[key] as UISelector).set_index(int(look.get(key, 0)), false)
	(ed.name as LineEdit).text = p_name
	SceneRouter.play_ui("page")
	_save(id)

func _randomize(id: String) -> void:
	var look := {}
	for key in DataRegistry.look_keys():
		look[key] = _rng.randi_range(0, DataRegistry.look_options(key) - 1)
	_apply(id, look, (_editor_of(id).name as LineEdit).text)

func _reset(id: String) -> void:
	MetaState.heroes.erase(id)
	_apply(id, DataRegistry.default_look(id), MetaState.hero_name(id))

func _focus_current() -> void:
	if tabs.current() < _editors.size():
		((_editors[tabs.current()] as Dictionary).first as Control).grab_focus()
