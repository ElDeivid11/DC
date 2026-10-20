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
	title_label.text = DataRegistry.t("unlocks.title_count", [available, ids.size()])
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
		var status := ""
		var variation := "DimLabel"
		if it.unlock_id == null:
			status = DataRegistry.t("unlocks.from_start")
			variation = "GoodLabel"
		elif MetaState.is_unlocked(String(it.unlock_id)):
			status = "✓ " + DataRegistry.t("unlocks.unlocked")
			variation = "GoodLabel"
		else:
			var u := DataRegistry.get_unlock(String(it.unlock_id))
			var p := UnlockEvaluator.progress_of(u, MetaState.progress)
			status = "???" if _hidden(id) else "%d/%d" % [p.x, p.y]
			variation = "AccentLabel" if p.x > 0 else "DimLabel"
		add_row("???" if _hidden(id) else String(it.nombre), [[status, variation, 140]], _rank(id) == 2)

func _show_detail(index: int) -> void:
	var id := ids[index]
	var it := DataRegistry.get_item(id)
	# Retrato: en silueta si el objeto todavía es secreto, apagado si está bloqueado.
	var pic := UIPortrait.for_item(id, 96)
	detail_box.add_child(pic)
	if _hidden(id):
		pic.set_silhouette(true)
	elif _rank(id) == 2:
		pic.set_dimmed(true)
	if _hidden(id):
		detail.set_title("???")
		detail_line(DataRegistry.t("unlocks.hidden_text"), "DimLabel")
		return
	detail.set_title(String(it.nombre))
	detail_line(String(it.descripcion))
	detail_line(DataRegistry.t("item.type." + String(it.tipo)), "DetailLabel")
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
