extends Node
## Carga TODOS los datos de juego de res://data/*.json al arrancar y los valida.
## Nada de números de balance, especies, objetos ni textos hardcodeados en
## escenas/scripts: todo se pide acá (get_species(), bal("coins.kill_base"),
## t("hub.start"), ...).
##
## Si un JSON está roto o le falta un campo, NO se intenta arrancar igual: cada
## problema queda en `errors` con archivo/campo/línea, se imprime con
## push_error, y Boot muestra una pantalla con la lista (falla ruidosa).

const DATA_DIR := "res://data/"

# Tipos de efecto/condición que el código sabe resolver. Agregar uno nuevo =
# sumarlo acá + su "case" donde se aplica (y su texto de hint).
const PASSIVE_EFFECTS: Array[String] = [
	"damage_reduction_flat", "defend_bonus_multiplier", "damage_bonus_flat",
	"lifesteal_pct", "crit_chance", "coin_bonus_pct", "thorns_flat",
]
const ITEM_EFFECTS: Array[String] = ["curar", "antorcha", "sello_retiro", "ataque_run", "huida_garantizada", "capacidad_alma"]
const ITEM_TYPES: Array[String] = ["consumible", "pasivo"]
const UPGRADE_EFFECTS: Array[String] = ["max_hp_flat", "atk_flat", "coin_bonus_pct", "start_item", "soul_chance_pct"]
const UNLOCK_CONDITIONS: Array[String] = [
	"kill_species_total", "reach_floor", "defeat_boss", "win_run",
	"flee_count", "no_item_use_run", "coins_total",
]

var species: Dictionary = {}
var souls: Dictionary = {}
var items: Dictionary = {}
var upgrades: Dictionary = {}
var unlocks: Dictionary = {}
var floors: Array = []
var floor_generation: Dictionary = {}
var balance: Dictionary = {}
var texts: Dictionary = {}

## Problemas encontrados al cargar/validar. Vacío = datos OK.
var errors: PackedStringArray = PackedStringArray()

func _ready() -> void:
	reload()

func reload() -> void:
	errors.clear()
	species = _load_dict("species.json")
	souls = _load_dict("souls.json")
	items = _load_dict("items.json")
	upgrades = _load_dict("upgrades.json")
	unlocks = _load_dict("unlocks.json")
	balance = _load_dict("balance.json")
	texts = _load_dict("texts.json")
	var floors_file := _load_dict("floors.json")
	floors = floors_file.get("floors", [])
	floor_generation = floors_file.get("generation", {})

	_validate_species()
	_validate_souls()
	_validate_items()
	_validate_unlocks()
	_validate_upgrades()
	_validate_floors()
	_validate_balance()
	_validate_texts()

	for e in errors:
		push_error("DataRegistry: " + e)

# --- Acceso -----------------------------------------------------------------

func get_species(id: String) -> Dictionary:
	var d: Dictionary = species.get(id, {})
	return d

func get_soul(id: String) -> Dictionary:
	var d: Dictionary = souls.get(id, {})
	return d

func get_item(id: String) -> Dictionary:
	var d: Dictionary = items.get(id, {})
	return d

func get_upgrade(id: String) -> Dictionary:
	var d: Dictionary = upgrades.get(id, {})
	return d

func get_unlock(id: String) -> Dictionary:
	var d: Dictionary = unlocks.get(id, {})
	return d

## n empieza en 1 (piso 1 = floors[0]).
func get_floor(n: int) -> Dictionary:
	if n < 1 or n > floors.size():
		return {}
	var d: Dictionary = floors[n - 1]
	return d

func floor_count() -> int:
	return floors.size()

## Especies ordenadas de más débil (rango 10) a más fuerte (rango 1), que es
## el orden natural del bestiario y de aparición.
func species_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: String in species.keys():
		ids.append(k)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ra: int = species[a].rank
		var rb: int = species[b].rank
		return ra > rb if ra != rb else a < b
	)
	return ids

## Valor de balance.json por ruta con puntos, p. ej. bal("coins.kill_base").
func bal(path: String, default: Variant = null) -> Variant:
	var node: Variant = balance
	for part in path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(part):
			return default
		node = (node as Dictionary)[part]
	return node

func bal_f(path: String, default: float = 0.0) -> float:
	return float(bal(path, default))

func bal_i(path: String, default: int = 0) -> int:
	return int(bal(path, default))

## Stats de un monstruo según su rango (10 = más débil, 1 = más fuerte).
## Mismos números que el prototipo, ahora con los coeficientes en balance.json.
func stats_for_rank(rank: int) -> Dictionary:
	var steps := 11 - rank
	return {
		"hp": bal_i("stats_for_rank.hp_base", 10) + steps * bal_i("stats_for_rank.hp_per_rank", 2),
		"atk": bal_i("stats_for_rank.atk_base", 1) + steps * bal_i("stats_for_rank.atk_per_rank", 1),
		"ability_damage": int(steps * bal_f("stats_for_rank.ability_per_rank", 1.5)),
	}

## Arma el alma concreta que suelta un monstruo de rango `rank`: copia de la
## plantilla de souls.json + el daño de la activa según ESE rango + de dónde
## salió (para mostrarlo en menús). Estructura igual a la del prototipo:
## {active:{name,damage}, passive:{name,description,effect}|null, stat_modifiers}.
func make_soul(soul_id: String, rank: int, source_name: String) -> Dictionary:
	var soul: Dictionary = get_soul(soul_id).duplicate(true)
	if soul.is_empty():
		return {}
	var active: Dictionary = soul.active
	active["damage"] = stats_for_rank(rank).ability_damage
	soul["id"] = soul_id
	soul["source_species"] = source_name
	soul["source_rank"] = rank
	return soul

# --- Textos -----------------------------------------------------------------

func has_text(key: String) -> bool:
	return texts.has(key)

## Todo texto visible pasa por acá (data/texts.json), para poder pulirlo en un
## solo lugar. Si falta la clave se ve "[clave]" (y tools/lint lo detecta).
func t(key: String, args: Array = []) -> String:
	if not texts.has(key):
		return "[%s]" % key
	var s: String = texts[key]
	return s % args if not args.is_empty() else s

# --- Carga ------------------------------------------------------------------

func _load_dict(file: String) -> Dictionary:
	var path := DATA_DIR + file
	if not FileAccess.file_exists(path):
		_err("%s: el archivo no existe" % path)
		return {}
	var json := JSON.new()
	var parse_err := json.parse(FileAccess.get_file_as_string(path))
	if parse_err != OK:
		_err("%s línea %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		_err("%s: la raíz debería ser un objeto { }" % path)
		return {}
	var d: Dictionary = json.data
	return d

func _err(msg: String) -> void:
	errors.append(msg)

## Chequea que d[field] exista y sea del tipo pedido. `nullable` acepta null.
func _req(file: String, id: String, d: Dictionary, field: String, type: int, nullable := false) -> bool:
	if not d.has(field):
		_err("%s → '%s': falta el campo '%s'" % [file, id, field])
		return false
	var v: Variant = d[field]
	if nullable and v == null:
		return true
	if typeof(v) != type:
		_err("%s → '%s': el campo '%s' debería ser %s y es %s" % [file, id, field, type_string(type), type_string(typeof(v))])
		return false
	return true

func _to_color(v: Variant) -> Color:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]))
	if typeof(v) == TYPE_STRING:
		return Color.html(String(v))
	return Color.WHITE

# --- Validación (y normalización: números de JSON vienen como float) --------

func _validate_species() -> void:
	const F := "species.json"
	for id: String in species.keys():
		var s: Dictionary = species[id]
		_req(F, id, s, "display_name", TYPE_STRING)
		if _req(F, id, s, "rank", TYPE_FLOAT):
			s["rank"] = int(s.rank)
			if s.rank < 1 or s.rank > 10:
				_err("%s → '%s': rank debe estar entre 1 y 10" % [F, id])
		if _req(F, id, s, "soul_id", TYPE_STRING) and not souls.has(s.soul_id):
			_err("%s → '%s': soul_id '%s' no existe en souls.json" % [F, id, s.soul_id])
		if s.has("model_path"):
			if not ResourceLoader.exists(String(s.model_path)):
				_err("%s → '%s': el modelo '%s' no existe" % [F, id, s.model_path])
			s["model_scale"] = float(s.get("model_scale", 1.0))
		elif s.has("color_a") and s.has("color_b"):
			s["color_a"] = _to_color(s.color_a)
			s["color_b"] = _to_color(s.color_b)
		else:
			_err("%s → '%s': necesita model_path o color_a/color_b" % [F, id])
		s["family"] = String(s.get("family", id))
		s["description"] = String(s.get("description", ""))

func _validate_souls() -> void:
	const F := "souls.json"
	for id: String in souls.keys():
		var s: Dictionary = souls[id]
		if _req(F, id, s, "active", TYPE_DICTIONARY):
			_req(F, id, s.active, "name", TYPE_STRING)
		if _req(F, id, s, "passive", TYPE_DICTIONARY, true) and s.passive != null:
			var p: Dictionary = s.passive
			_req(F, id, p, "name", TYPE_STRING)
			_req(F, id, p, "description", TYPE_STRING)
			if _req(F, id, p, "effect", TYPE_DICTIONARY):
				var t_: String = String(p.effect.get("type", ""))
				if not PASSIVE_EFFECTS.has(t_):
					_err("%s → '%s': efecto de pasiva desconocido '%s'" % [F, id, t_])
		_req(F, id, s, "stat_modifiers", TYPE_DICTIONARY)
		if _req(F, id, s, "species", TYPE_STRING) and not species.has(s.species):
			_err("%s → '%s': species '%s' no existe" % [F, id, s.species])

func _validate_items() -> void:
	const F := "items.json"
	for id: String in items.keys():
		var it: Dictionary = items[id]
		_req(F, id, it, "nombre", TYPE_STRING)
		_req(F, id, it, "descripcion", TYPE_STRING)
		if _req(F, id, it, "tipo", TYPE_STRING) and not ITEM_TYPES.has(String(it.tipo)):
			_err("%s → '%s': tipo '%s' desconocido (usa %s)" % [F, id, it.tipo, ITEM_TYPES])
		if _req(F, id, it, "efecto", TYPE_DICTIONARY):
			var e: Dictionary = it.efecto
			if not ITEM_EFFECTS.has(String(e.get("tipo", ""))):
				_err("%s → '%s': efecto '%s' desconocido" % [F, id, e.get("tipo", "")])
			e["valor"] = float(e.get("valor", 0))
			e["en_combate"] = bool(e.get("en_combate", false))
			e["fuera_combate"] = bool(e.get("fuera_combate", false))
		if _req(F, id, it, "peso_aparicion", TYPE_FLOAT):
			it["peso_aparicion"] = int(it.peso_aparicion)
		if _req(F, id, it, "unlock_id", TYPE_STRING, true) and it.unlock_id != null and not unlocks.has(it.unlock_id):
			_err("%s → '%s': unlock_id '%s' no existe en unlocks.json" % [F, id, it.unlock_id])
		it["id"] = id

func _validate_unlocks() -> void:
	const F := "unlocks.json"
	for id: String in unlocks.keys():
		var u: Dictionary = unlocks[id]
		_req(F, id, u, "nombre", TYPE_STRING)
		_req(F, id, u, "descripcion", TYPE_STRING)
		if _req(F, id, u, "condicion", TYPE_DICTIONARY):
			var c: Dictionary = u.condicion
			if not UNLOCK_CONDITIONS.has(String(c.get("tipo", ""))):
				_err("%s → '%s': condición '%s' desconocida (usa %s)" % [F, id, c.get("tipo", ""), UNLOCK_CONDITIONS])
			if typeof(c.get("parametros", {})) != TYPE_DICTIONARY:
				_err("%s → '%s': 'parametros' debe ser un objeto" % [F, id])
		if _req(F, id, u, "recompensa", TYPE_STRING) and not items.has(u.recompensa):
			_err("%s → '%s': recompensa '%s' no existe en items.json" % [F, id, u.recompensa])
		u["oculto"] = bool(u.get("oculto", false))
		u["id"] = id

func _validate_upgrades() -> void:
	const F := "upgrades.json"
	for id: String in upgrades.keys():
		var up: Dictionary = upgrades[id]
		_req(F, id, up, "nombre", TYPE_STRING)
		_req(F, id, up, "descripcion", TYPE_STRING)
		if _req(F, id, up, "efecto", TYPE_DICTIONARY):
			var e: Dictionary = up.efecto
			if not UPGRADE_EFFECTS.has(String(e.get("tipo", ""))):
				_err("%s → '%s': efecto '%s' desconocido" % [F, id, e.get("tipo", "")])
			e["valor"] = float(e.get("valor", 0))
			if e.get("tipo", "") == "start_item" and not items.has(String(e.get("item", ""))):
				_err("%s → '%s': item '%s' no existe" % [F, id, e.get("item", "")])
		if _req(F, id, up, "coste_base", TYPE_FLOAT):
			up["coste_base"] = int(up.coste_base)
		if _req(F, id, up, "max_nivel", TYPE_FLOAT):
			up["max_nivel"] = int(up.max_nivel)
		up["id"] = id

func _validate_floors() -> void:
	const F := "floors.json"
	if floors.is_empty():
		_err("%s: no hay pisos definidos en 'floors'" % F)
	for i in floors.size():
		var fl: Dictionary = floors[i]
		var id := "piso %d" % (i + 1)
		for field: String in ["size", "rank_min", "rank_max", "enemies", "chests", "floor_items"]:
			if _req(F, id, fl, field, TYPE_FLOAT):
				fl[field] = int(fl[field])
		fl["n"] = i + 1
		if fl.get("rank_min", 0) > fl.get("rank_max", 0):
			_err("%s → %s: rank_min no puede ser mayor que rank_max" % [F, id])
		var any_species := false
		for sid: String in species.keys():
			var r: int = int(species[sid].get("rank", 0))
			if r >= int(fl.get("rank_min", 0)) and r <= int(fl.get("rank_max", 0)):
				any_species = true
		if not any_species:
			_err("%s → %s: ninguna especie tiene rango entre %s y %s" % [F, id, fl.get("rank_min"), fl.get("rank_max")])
		if _req(F, id, fl, "boss", TYPE_DICTIONARY):
			var b: Dictionary = fl.boss
			_req(F, id, b, "display_name", TYPE_STRING)
			if _req(F, id, b, "species", TYPE_STRING) and not species.has(b.species):
				_err("%s → %s: jefe con especie '%s' inexistente" % [F, id, b.species])
			if _req(F, id, b, "soul_id", TYPE_STRING) and not souls.has(b.soul_id):
				_err("%s → %s: jefe con alma '%s' inexistente" % [F, id, b.soul_id])
			if _req(F, id, b, "rank", TYPE_FLOAT):
				b["rank"] = int(b.rank)
			b["scale_mult"] = float(b.get("scale_mult", 1.0))
			b["tint"] = _to_color(b.get("tint", [1, 1, 1]))

func _validate_balance() -> void:
	const F := "balance.json"
	if _req(F, "raíz", balance, "party", TYPE_ARRAY):
		var party: Array = balance.party
		if party.is_empty() or party.size() > 3:
			_err("%s: 'party' debe tener entre 1 y 3 personajes" % F)
		for m: Variant in party:
			if typeof(m) != TYPE_DICTIONARY:
				_err("%s: cada personaje de 'party' debe ser un objeto" % F)
				continue
			var md: Dictionary = m
			var mid := String(md.get("id", "?"))
			_req(F, mid, md, "id", TYPE_STRING)
			_req(F, mid, md, "name", TYPE_STRING)
			if _req(F, mid, md, "base_hp", TYPE_FLOAT):
				md["base_hp"] = int(md.base_hp)
			if _req(F, mid, md, "base_atk", TYPE_FLOAT):
				md["base_atk"] = int(md.base_atk)
	for path: String in ["floors_per_run", "inventory_capacity", "soul_capacity", "coins.kill_base", "coins.coin_keep_on_death", "soul_drop.normal_base"]:
		if bal(path) == null:
			_err("%s: falta '%s'" % [F, path])
	for it: Variant in bal("start_items", []):
		if not items.has(String(it)):
			_err("%s: start_items incluye '%s', que no existe" % [F, it])

func _validate_texts() -> void:
	for k: String in texts.keys():
		if typeof(texts[k]) != TYPE_STRING:
			_err("texts.json → '%s': debe ser texto" % k)
