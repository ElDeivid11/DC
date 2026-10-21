class_name RunSummaryScreen
extends UIScreen
## Resumen de fin de run. Acá (y solo acá) la run toca el estado persistente:
## RunRewards calcula todo (monedas desglosadas, primeras kills, desbloqueos)
## y MetaState.apply_run_result() lo aplica UNA vez; después se autoguarda.
##
## Los desbloqueos se anuncian ocultos ("¡Presiona CONTINUAR!") y se revelan
## con una pequeña animación al pulsar Continuar; el segundo Continuar vuelve
## al Hub.

var result: Dictionary = {}
var unlocks_box: VBoxContainer
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
	var coins: Dictionary = result.coins
	var outcome := String(result.outcome)
	title_label.text = DataRegistry.t("summary.title", [DataRegistry.t("outcome." + outcome), int(snap.max_floor), UIFormat.time(float(snap.time_sec))])
	if outcome == "muerte" or outcome == "abandono":
		title_label.theme_type_variation = "DangerLabel"
		title_label.add_theme_font_size_override("font_size", UIStyle.FONT_NUM)
	show_coins(MetaState.coins)

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", UIStyle.SPACE * 4)
	body.add_child(row)

	# Monedas desglosadas
	var money := UIPanel.new(DataRegistry.t("summary.coins"), "PanelAlt")
	money.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(money)
	_kv(money.body, "summary.kills_coins", "+" + UIFormat.number(int(coins.kills)))
	_kv(money.body, "summary.boss_coins", "+" + UIFormat.number(int(coins.boss)))
	_kv(money.body, "summary.chest_coins", "+" + UIFormat.number(int(coins.chests)))
	_kv(money.body, "summary.first_kill_coins", "+" + UIFormat.number(int(coins.first_kill)))
	if int(coins.botin_bonus) > 0:
		_kv(money.body, "summary.botin", "+%s (%d%%)" % [UIFormat.number(int(coins.botin_bonus)), int(coins.botin_pct)])
	money.body.add_child(HSeparator.new())
	if int(coins.lost) > 0:
		_kv(money.body, "summary.lost", "-%s (%s)" % [UIFormat.number(int(coins.lost)), UIFormat.pct(1.0 - float(coins.keep_fraction))], "DangerLabel")
	var total := Label.new()
	total.theme_type_variation = "CoinLabel"
	total.add_theme_font_size_override("font_size", UIStyle.FONT_NUM)
	total.text = "= " + UIFormat.coins(int(coins.total))
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money.body.add_child(total)
	if bool(result.test_room):
		_line(money.body, DataRegistry.t("summary.test_room"), "DimLabel")

	# La expedición
	var run_panel := UIPanel.new(DataRegistry.t("summary.run"), "PanelAlt")
	run_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(run_panel)
	_kv(run_panel.body, "summary.floor", str(int(snap.max_floor)))
	_kv(run_panel.body, "summary.kills", str(int(snap.kills_total)))
	_kv(run_panel.body, "summary.time", UIFormat.time(float(snap.time_sec)))
	if String(snap.cause) != "":
		_line(run_panel.body, DataRegistry.t("summary.cause", [snap.cause]), "DangerLabel" if outcome == "muerte" else "DimLabel")
	_line(run_panel.body, DataRegistry.t("summary.souls"), "SoulLabel")
	var souls: Array = snap.souls_taken
	if souls.is_empty():
		_line(run_panel.body, DataRegistry.t("summary.no_souls"), "DimLabel")
	for s: Dictionary in souls:
		_line(run_panel.body, DataRegistry.t("summary.soul_line", [s.name, s.member, int(s.rank)]), "")
	_line(run_panel.body, DataRegistry.t("summary.souls_lost"), "DetailLabel")

	# Bestiario y desbloqueos
	var news := UIPanel.new(DataRegistry.t("summary.news"), "PanelAlt")
	news.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(news)
	var new_species: Array = result.new_species
	if new_species.is_empty():
		_line(news.body, DataRegistry.t("summary.no_new_species"), "DimLabel")
	for sp: Dictionary in new_species:
		_line(news.body, DataRegistry.t("summary.new_species", [sp.name, UIFormat.coins(int(sp.bonus))]), "AccentLabel")
	news.body.add_child(HSeparator.new())
	unlocks_box = VBoxContainer.new()
	news.body.add_child(unlocks_box)
	var new_unlocks: Array = result.new_unlocks
	if new_unlocks.is_empty():
		_line(unlocks_box, DataRegistry.t("summary.no_unlocks"), "DimLabel")
		revealed = true
	else:
		_line(unlocks_box, DataRegistry.t("summary.unlocks_hidden", [new_unlocks.size()]), "SoulLabel")

	continue_btn = add_footer_button(DataRegistry.t("ui.continue"), _on_continue)
	continue_btn.call_deferred("grab_focus")

func _on_continue() -> void:
	if not revealed:
		revealed = true
		_reveal_unlocks()
		return
	SceneRouter.goto(SceneRouter.HUB)

## Revela cada desbloqueo con un "pop" escalonado.
func _reveal_unlocks() -> void:
	for c in unlocks_box.get_children():
		c.queue_free()
	var i := 0
	for uid: Variant in result.new_unlocks:
		var u := DataRegistry.get_unlock(String(uid))
		var it := DataRegistry.get_item(String(u.recompensa))
		var card := UIPanel.new(DataRegistry.t("summary.unlocked", [it.nombre]), "Card", "SoulLabel")
		var d := Label.new()
		d.text = String(it.descripcion)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.body.add_child(d)
		var why := Label.new()
		why.theme_type_variation = "DetailLabel"
		why.text = String(u.descripcion)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.body.add_child(why)
		unlocks_box.add_child(card)
		card.modulate.a = 0.0
		var tw := card.create_tween()
		tw.tween_interval(0.12 * i)
		tw.tween_property(card, "modulate:a", 1.0, UIStyle.TRANSITION)
		i += 1
	SceneRouter.play_ui("coin")

func _kv(parent: Container, key: String, value: String, variation := "") -> void:
	var r := HBoxContainer.new()
	parent.add_child(r)
	var k := Label.new()
	k.text = DataRegistry.t(key)
	k.theme_type_variation = "DimLabel"
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(k)
	var v := Label.new()
	v.text = value
	v.theme_type_variation = variation if variation != "" else "AccentLabel"
	r.add_child(v)

func _line(parent: Container, text: String, variation: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != "":
		l.theme_type_variation = variation
	parent.add_child(l)
