class_name UnlocksScreen
extends ListDetailScreen
## Objetos y desbloqueos: todos los objetos que pueden aparecer en las runs.
## Se desbloquean por CONDICIONES (nunca con monedas). Estados: disponible de
## inicio, desbloqueado, en progreso (barra 7/10) y bloqueado; los ocultos se
## ven como "???" hasta cumplirlos.

var ids: Array[String] = []

func _init() -> void:
	super(DataRegistry.t("unlocks.title"))

func _ready() -> void:
	ids.assign(DataRegistry.items.keys())
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ra := _rank(a)
		var rb := _rank(b)
		return ra < rb if ra != rb else a < b
	)
	super._ready()
	var available := MetaState.available_items().size()
	show_count("%d/%d" % [available, ids.size()])
	add_footer_button(DataRegistry.t("ui.back"), close)

## Orden: de inicio, desbloqueados, en progreso, bloqueados.
func _rank(item_id: String) -> int:
	var it := DataRegistry.get_item(item_id)
	if it.unlock_id == null:
		return 0
	if MetaState.is_unlocked(String(it.unlock_id)):
		return 1
	return 2

func _hidden(item_id: String) -> bool:
	var it := DataRegistry.get_item(item_id)
	if it.unlock_id == null or MetaState.is_unlocked(String(it.unlock_id)):
		return false
	return bool(DataRegistry.get_unlock(String(it.unlock_id)).get("oculto", false))

func _fill_list() -> void:
	for id in ids:
		var it := DataRegistry.get_item(id)
		var columns: Array = []
		if it.unlock_id == null:
			columns.append(col(DataRegistry.t("unlocks.from_start"), "GoodLabel", 150))
		elif MetaState.is_unlocked(String(it.unlock_id)):
			columns.append(col(DataRegistry.t("unlocks.unlocked"), "GoodLabel", 150))
		elif _hidden(id):
			columns.append(col("???", "DimLabel", 150))
		else:
			var u := DataRegistry.get_unlock(String(it.unlock_id))
			var p := UnlockEvaluator.progress_of(u, MetaState.progress)
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.theme_type_variation = "CoinBar"
			bar.custom_minimum_size = Vector2(96, 16)
			bar.max_value = maxi(p.y, 1)
			bar.value = clampi(p.x, 0, maxi(p.y, 1))
			columns.append(bar)
			columns.append(col("%d/%d" % [mini(p.x, p.y), p.y], "NumSmallLabel", 48))
		var row := add_row("???" if _hidden(id) else String(it.nombre), columns, _rank(id) == 2, "", UIPortrait.item_texture(id))
		if _hidden(id) and row.picture:
			row.picture.modulate = UIStyle.HIERRO_OSC

func _show_detail(index: int) -> void:
	var id := ids[index]
	var it := DataRegistry.get_item(id)
	var is_hidden := _hidden(id)
	var info := detail_header("???" if is_hidden else String(it.nombre), UIPortrait.item_texture(id))
	# Retrato: en silueta si el objeto todavía es secreto, apagado si está bloqueado.
	if is_hidden:
		detail_portrait.set_silhouette(true)
		detail_line(DataRegistry.t("unlocks.hidden_text"), "DimLabel")
		return
	elif _rank(id) == 2:
		detail_portrait.set_dimmed(true)
	info.add_child(UIItemSlot.type_plate(String(it.tipo)))
	detail_line(String(it.descripcion))
	if it.unlock_id == null:
		detail_line(DataRegistry.t("unlocks.from_start_text"), "GoodLabel")
		return
	var u := DataRegistry.get_unlock(String(it.unlock_id))
	if MetaState.is_unlocked(String(it.unlock_id)):
		detail_line(DataRegistry.t("unlocks.done_text", [u.descripcion]), "GoodLabel")
		return
	var p := UnlockEvaluator.progress_of(u, MetaState.progress)
	detail_line(DataRegistry.t("unlocks.condition"), "AccentLabel")
	detail_box.add_child(UIProgressUnlock.new(String(u.descripcion), p.x, p.y))
	if u.condicion.tipo == "no_item_use_run":
		detail_line(DataRegistry.t("unlocks.per_run_note"), "DetailLabel")
