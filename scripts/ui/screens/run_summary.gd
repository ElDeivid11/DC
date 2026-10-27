class_name RunSummaryScreen
extends UIScreen
## Resumen de fin de run: la «Crónica». Acá (y solo acá) la run toca el estado
## persistente: RunRewards calcula todo (monedas desglosadas, primeras kills,
## desbloqueos) y MetaState.apply_run_result() lo aplica UNA vez; después se
## autoguarda.
##
## Encabezado: epitafio gótico según el desenlace + «PISO III · 24:12». Tres
## paneles de libro de cuentas: Monedas (el total cuenta hacia arriba), La
## expedición y Novedades (cintas con sello que se «estampan»). Los
## desbloqueos se anuncian ocultos y se revelan al pulsar Continuar; el
## segundo Continuar vuelve al Hub.

## Desenlace → [clave del epitafio, color, color de la capitular].
const EPITAPHS := {
	"muerte": ["summary.epitaph_death", UIStyle.RUBRICA_CLARA, UIStyle.VELA],
	"victoria": ["summary.epitaph_victory", UIStyle.BRONCE_LUZ, UIStyle.RUBRICA_CLARA],
	"retiro": ["summary.epitaph_retire", UIStyle.HUESO, UIStyle.RUBRICA_CLARA],
	"abandono": ["summary.epitaph_abandon", UIStyle.CENIZA, UIStyle.RUBRICA_CLARA],
}
const COUNT_TIME := 0.8
const COUNT_STEPS := 16
const STAMP_GAP := 0.25

var result: Dictionary = {}
var unlocks_box: VBoxContainer
var news_box: VBoxContainer
var total_label: Label
var revealed := false
var continue_btn: UIButton

func _init() -> void:
	super("")
	closable = false

func _ready() -> void:
	super._ready()
	if not GameState.result_applied:
		var snap := GameState.snapshot()
		result = RunRewards.compute(snap, MetaState)
		if not bool(result.test_room):
			MetaState.apply_run_result(result)
			SaveSystem.save_meta()
			for uid: Variant in result.new_unlocks:
				EventBus.unlock_earned.emit(String(uid))
		GameState.last_result = result
		GameState.result_applied = true
	else:
		result = GameState.last_result
	if result.is_empty():
		SceneRouter.goto.call_deferred(SceneRouter.HUB)
		return
	_build()

func _build() -> void:
	var snap: Dictionary = result.snapshot
	var outcome := String(result.outcome)
	var ep: Array = EPITAPHS.get(outcome, EPITAPHS["retiro"])
	title_label.text = DataRegistry.t(String(ep[0]))
	var color: Color = ep[1]
	var cap_color: Color = ep[2]
	title_label.set_colors(color, cap_color)
	show_coins(MetaState.coins)
	var sub := UILabel.make(DataRegistry.t("summary.subline", [UIFormat.roman(int(snap.max_floor)), UIFormat.time(float(snap.time_sec))]).to_upper(), "NumLabel")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	header.add_child(sub)
	header.move_child(sub, 1)
	if bool(result.test_room):
		var test_label := UILabel.make(DataRegistry.t("summary.test_room"), "DangerLabel")
		test_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(test_label)

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	body.add_child(row)
	_build_coins(_panel(row, "summary.coins"))
	_build_run(_panel(row, "summary.run"), snap, outcome)
	_build_news(_panel(row, "summary.news"))

	# Cita al pie, a la izquierda del botón.
	var note := UIGothicLabel.new(DataRegistry.t("summary.souls_note"), "GothicQuote", UIStyle.TEXT_DIM, UIStyle.SOUL)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(note)
	continue_btn = add_footer_button(DataRegistry.t("ui.continue"), _on_continue)
	continue_btn.call_deferred("grab_focus")
	_count_total(int(result.coins.total))

func _panel(parent: Control, title_key: String) -> UIPanel:
	var p := UIPanel.new(DataRegistry.t(title_key), "PanelAlt")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.0
	p.body.add_theme_constant_override("separation", UIStyle.SPACE)
	parent.add_child(p)
	return p

func _build_coins(p_panel: UIPanel) -> void:
	var coins: Dictionary = result.coins
	var b := p_panel.body
	b.add_child(UILedgerRow.new(DataRegistry.t("summary.kills_coins"), "+" + UIFormat.number(int(coins.kills)), "CoinLabel"))
	b.add_child(UILedgerRow.new(DataRegistry.t("summary.boss_coins"), "+" + UIFormat.number(int(coins.boss)), "CoinLabel"))
	b.add_child(UILedgerRow.new(DataRegistry.t("summary.chest_coins"), "+" + UIFormat.number(int(coins.chests)), "CoinLabel"))
	b.add_child(UILedgerRow.new(DataRegistry.t("summary.first_kill_coins"), "+" + UIFormat.number(int(coins.first_kill)), "CoinLabel"))
	if int(coins.botin_bonus) > 0:
		b.add_child(UILedgerRow.new(DataRegistry.t("summary.botin", [int(coins.botin_pct)]), "+" + UIFormat.number(int(coins.botin_bonus)), "CoinLabel"))
	if int(coins.lost) > 0:
		b.add_child(UILedgerRow.new(DataRegistry.t("summary.lost", [UIFormat.pct(1.0 - float(coins.keep_fraction))]), "-" + UIFormat.number(int(coins.lost)), "CoinDangerLabel"))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_child(spacer)
	var total_row := HBoxContainer.new()
	total_row.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	var total_name := UILabel.make(DataRegistry.t("summary.total"), "HeadLabel")
	total_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	total_row.add_child(total_name)
	total_row.add_child(UIIcon.make("monedas", "moneda"))
	total_label = UILabel.make("0", "CoinBigLabel")
	total_row.add_child(total_label)
	b.add_child(total_row)

## El total sube de 0 al valor final por pasos, con monedas sonando.
func _count_total(total: int) -> void:
	if total <= 0:
		total_label.text = UIFormat.number(total)
		return
	var tw := create_tween()
	for i in range(1, COUNT_STEPS + 1):
		var value := roundi(total * float(i) / COUNT_STEPS)
		tw.tween_callback(func() -> void:
			total_label.text = UIFormat.number(value)
			SceneRouter.play_ui("coin")
		).set_delay(COUNT_TIME / COUNT_STEPS)
	tw.tween_callback(func() -> void: SceneRouter.play_ui("reward"))

func _build_run(p_panel: UIPanel, snap: Dictionary, outcome: String) -> void:
	var b := p_panel.body
	b.add_child(UILedgerRow.new(DataRegistry.t("summary.floor"), UIFormat.roman(int(snap.max_floor)), "NumLabel", "piso", "bronce"))
	b.add_child(UILedgerRow.new(DataRegistry.t("summary.kills"), UIFormat.number(int(snap.kills_total)), "NumLabel", "muerte", "bronce"))
	b.add_child(UILedgerRow.new(DataRegistry.t("summary.time"), UIFormat.time(float(snap.time_sec)), "NumLabel", "tiempo", "bronce"))
	if String(snap.cause) != "":
		b.add_child(UILabel.make(DataRegistry.t("summary.cause", [snap.cause]), "DangerLabel" if outcome == "muerte" else "DimLabel", true))
	var souls: Array = snap.souls_taken
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	head.add_child(UIIcon.make("almas", "alma"))
	var head_label := UILabel.make(DataRegistry.t("summary.souls", [souls.size()]), "SoulLabel")
	head_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(head_label)
	b.add_child(head)
	for s: Dictionary in souls:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", UIStyle.SPACE * 2)
		line.add_child(UIRankBadge.new(int(s.rank)))
		var l := UILabel.make(DataRegistry.t("summary.soul_line", [s.name, s.member]), "", true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(l)
		b.add_child(line)

func _build_news(p_panel: UIPanel) -> void:
	# Con muchos desbloqueos, las novedades se desplazan dentro de su panel
	# (los otros dos paneles marcan el alto).
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p_panel.body.add_child(scroll)
	news_box = VBoxContainer.new()
	news_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(news_box)
	var new_species: Array = result.new_species
	var ribbons: Array[Control] = []
	for sp: Dictionary in new_species:
		ribbons.append(_ribbon(DataRegistry.t("summary.new_species", [sp.name]), DataRegistry.t("summary.new_species_bonus", [UIFormat.number(int(sp.bonus))])))
	news_box.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	unlocks_box = VBoxContainer.new()
	unlocks_box.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	var new_unlocks: Array = result.new_unlocks
	if new_unlocks.is_empty():
		revealed = true
		if new_species.is_empty():
			news_box.add_child(UILabel.make(DataRegistry.t("summary.no_news"), "DimLabel", true))
	else:
		unlocks_box.add_child(UILabel.make(DataRegistry.t("summary.unlocks_hidden", [new_unlocks.size()]), "SoulLabel", true))
	for r in ribbons:
		news_box.add_child(r)
	news_box.add_child(unlocks_box)
	_stamp(ribbons)

## Tarjeta con sello: título y detalle.
func _ribbon(title: String, detail_text: String) -> PanelContainer:
	var ribbon := PanelContainer.new()
	ribbon.theme_type_variation = "Card"
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", UIStyle.SPACE * 2)
	ribbon.add_child(r)
	var seal := UISprite.new("seal_mini")
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(seal)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	r.add_child(col)
	col.add_child(UILabel.make(title, "AccentLabel", true))
	if detail_text != "":
		col.add_child(UILabel.make(detail_text, "DetailLabel", true))
	return ribbon

## Las cintas se «estampan» una por una: escala 1,3 → 1 en dos cuadros.
func _stamp(ribbons: Array[Control]) -> void:
	for i in ribbons.size():
		var rb := ribbons[i]
		rb.modulate.a = 0.0
		var tw := rb.create_tween()
		tw.tween_interval(STAMP_GAP * (i + 1))
		tw.tween_callback(func() -> void:
			rb.pivot_offset = rb.size / 2.0
			rb.scale = Vector2(1.3, 1.3)
			rb.modulate.a = 1.0
			SceneRouter.play_ui("click"))
		tw.tween_callback(func() -> void: rb.scale = Vector2(1.15, 1.15)).set_delay(0.033)
		tw.tween_callback(func() -> void: rb.scale = Vector2.ONE).set_delay(0.033)

func _on_continue() -> void:
	if not revealed:
		revealed = true
		_reveal_unlocks()
		return
	SceneRouter.goto(SceneRouter.HUB)

## Revela cada desbloqueo como una cinta nueva.
func _reveal_unlocks() -> void:
	for c in unlocks_box.get_children():
		c.queue_free()
	var ribbons: Array[Control] = []
	for uid: Variant in result.new_unlocks:
		var u := DataRegistry.get_unlock(String(uid))
		var it := DataRegistry.get_item(String(u.recompensa))
		var rb := _ribbon(DataRegistry.t("summary.unlocked", [it.nombre]), String(u.descripcion))
		unlocks_box.add_child(rb)
		ribbons.append(rb)
	SceneRouter.play_ui("soul")
	_stamp(ribbons)
