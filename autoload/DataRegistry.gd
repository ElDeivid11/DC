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
const SPECIES_TIERS: Array[String] = ["basico", "elite", "jefe"]
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
## Biomas (floors.json → themes): niebla, ambiente, texturas, antorchas.
var floor_themes: Dictionary = {}
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
	floor_themes = floors_file.get("themes", {})

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

## Bioma del piso n (o el del piso 1 si n está fuera de rango: Hub, sala de pruebas).
func get_theme(n: int) -> Dictionary:
	var fl := get_floor(n)
	if fl.is_empty():
		fl = get_floor(1)
	var d: Dictionary = floor_themes.get(String(fl.get("theme", "")), {})
	return d

## Especies ordenadas de más débil (rango 10) a más fuerte (rango 1), que es
## el orden natural del bestiario y de aparición. Las marcadas "activo": false
## (prototipos sin licencia o sin modelo) quedan fuera salvo que se pidan.
func species_ids(include_inactive := false) -> Array[String]:
	var ids: Array[String] = []
	for k: String in species.keys():
		if include_inactive or bool(species[k].get("activo", true)):
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
	return parse_json_text(FileAccess.get_file_as_string(path), path)

## Parsea texto JSON; si está roto, anota en `errors` dónde (archivo/línea).
func parse_json_text(text: String, label: String) -> Dictionary:
	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK:
		_err("%s línea %d: %s" % [label, json.get_error_line() + 1, json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		_err("%s: la raíz debería ser un objeto { }" % label)
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
	# JSON trae números como float; tras normalizar pueden ser int. Ambos valen.
	if type == TYPE_FLOAT and typeof(v) == TYPE_INT:
		return true
	if typeof(v) != type:
		_err("%s → '%s': el campo '%s' debería ser %s y es %s" % [file, id, field, type_string(type), type_string(typeof(v))])
		return false
	return true

## Color en texto "#rrggbb" o [r, g, b] (o ya convertido, si se valida dos veces).
func _req_color(file: String, id: String, d: Dictionary, field: String) -> bool:
	if not d.has(field):
		_err("%s → '%s': falta el campo '%s'" % [file, id, field])
		return false
	var kind := typeof(d[field])
	if kind != TYPE_STRING and kind != TYPE_ARRAY and kind != TYPE_COLOR:
		_err("%s → '%s': el campo '%s' debería ser un color (\"#rrggbb\")" % [file, id, field])
		return false
	return true

func _to_color(v: Variant) -> Color:
	if typeof(v) == TYPE_COLOR: # ya normalizado (validar dos veces no rompe nada)
		return v
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
		s["activo"] = bool(s.get("activo", true))
		s["family"] = String(s.get("family", id))
		s["description"] = String(s.get("description", ""))
		var tier := String(s.get("tier", "basico"))
		if not SPECIES_TIERS.has(tier):
			_err("%s → '%s': tier '%s' desconocido (usa %s)" % [F, id, tier, SPECIES_TIERS])
		s["tier"] = tier
		s["peso"] = float(s.get("peso", 1.0))
		s["dormant_chance"] = clampf(float(s.get("dormant_chance", 0.0)), 0.0, 1.0)
		# Rango en el que puede aparecer en un piso. Sin rank_range = solo su rank.
		var rr: Variant = s.get("rank_range", [s.get("rank", 10), s.get("rank", 10)])
		if typeof(rr) != TYPE_ARRAY or (rr as Array).size() != 2:
			_err("%s → '%s': rank_range debe ser [min, max]" % [F, id])
			rr = [s.get("rank", 10), s.get("rank", 10)]
		var rr_a: Array = rr
		var r_lo := mini(int(rr_a[0]), int(rr_a[1]))
		var r_hi := maxi(int(rr_a[0]), int(rr_a[1]))
		if r_lo < 1 or r_hi > 10:
			_err("%s → '%s': rank_range debe estar entre 1 y 10" % [F, id])
		s["rank_range"] = [r_lo, r_hi]
		if s.has("visual"):
			_validate_visual(F, id, s)
		elif s.has("model_path"):
			if not ResourceLoader.exists(String(s.model_path)):
				_err("%s → '%s': el modelo '%s' no existe" % [F, id, s.model_path])
			s["model_scale"] = float(s.get("model_scale", 1.0))
		elif s.has("color_a") and s.has("color_b"):
			s["color_a"] = _to_color(s.color_a)
			s["color_b"] = _to_color(s.color_b)
		else:
			_err("%s → '%s': necesita visual, model_path o color_a/color_b" % [F, id])

## Bloque "visual" de una especie animada (EnemyVisual): modelo con esqueleto,
## armas en las manos, color de ojos y qué animación usar para cada papel.
func _validate_visual(F: String, id: String, s: Dictionary) -> void:
	if typeof(s.visual) != TYPE_DICTIONARY:
		_err("%s → '%s': 'visual' debe ser un objeto" % [F, id])
		return
	var v: Dictionary = s.visual
	if _req(F, id, v, "model_path", TYPE_STRING) and not ResourceLoader.exists(String(v.model_path)):
		_err("%s → '%s': el modelo '%s' no existe" % [F, id, v.model_path])
	for w: String in ["weapon_r", "weapon_l"]:
		if v.has(w) and not ResourceLoader.exists(String(v[w])):
			_err("%s → '%s': el arma '%s' no existe" % [F, id, v[w]])
	v["scale"] = float(v.get("scale", 1.0))
	v["head_scale"] = float(v.get("head_scale", 1.0))
	v["anim_fps"] = maxi(1, int(v.get("anim_fps", 12)))
	v["eye_color"] = _to_color(v.get("eye_color", "#ffffff"))
	v["shadow"] = float(v.get("shadow", 0.9))
	if typeof(v.get("anim_speed", {})) != TYPE_DICTIONARY:
		_err("%s → '%s': visual.anim_speed debe ser un objeto {papel: velocidad}" % [F, id])
		v.erase("anim_speed")
	elif v.has("anim_speed"):
		var sp: Dictionary = v.anim_speed
		for role: String in sp.keys():
			sp[role] = clampf(float(sp[role]), 0.1, 10.0)
	if v.has("bone_scale"):
		if typeof(v.bone_scale) != TYPE_DICTIONARY:
			_err("%s → '%s': visual.bone_scale debe ser un objeto {hueso: escala}" % [F, id])
			v.erase("bone_scale")
		else:
			var bs: Dictionary = v.bone_scale
			for bone: String in bs.keys():
				bs[bone] = clampf(float(bs[bone]), 0.2, 3.0)
	if v.has("light"):
		if typeof(v.light) != TYPE_DICTIONARY:
			_err("%s → '%s': visual.light debe ser un objeto" % [F, id])
			v.erase("light")
		else:
			var l: Dictionary = v.light
			l["color"] = _to_color(l.get("color", "#ffffff"))
			l["energy"] = float(l.get("energy", 1.0))
			l["range"] = float(l.get("range", 3.0))
	if _req(F, id, v, "anims", TYPE_DICTIONARY):
		var anims: Dictionary = v.anims
		for role: String in ["idle", "death"]:
			if not anims.has(role):
				_err("%s → '%s': visual.anims necesita '%s'" % [F, id, role])
		for role: String in anims.keys():
			var a: Variant = anims[role]
			if typeof(a) != TYPE_STRING and typeof(a) != TYPE_ARRAY:
				_err("%s → '%s': visual.anims.%s debe ser texto o lista" % [F, id, role])

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
	_validate_themes(F)
	for i in floors.size():
		var fl: Dictionary = floors[i]
		var id := "piso %d" % (i + 1)
		for field: String in ["size", "rank_min", "rank_max", "enemies", "chests", "floor_items"]:
			if _req(F, id, fl, field, TYPE_FLOAT):
				fl[field] = int(fl[field])
		fl["n"] = i + 1
		if _req(F, id, fl, "theme", TYPE_STRING) and not floor_themes.has(fl.theme):
			_err("%s → %s: el tema '%s' no existe en 'themes'" % [F, id, fl.theme])
		if fl.get("rank_min", 0) > fl.get("rank_max", 0):
			_err("%s → %s: rank_min no puede ser mayor que rank_max" % [F, id])
		var any_species := false
		for sid: String in species.keys():
			var sp: Dictionary = species[sid]
			if not bool(sp.get("activo", true)) or String(sp.get("tier", "")) == "jefe" or float(sp.get("peso", 0.0)) <= 0.0:
				continue
			var rr: Array = sp.get("rank_range", [0, 0])
			if int(rr[0]) <= int(fl.get("rank_max", 0)) and int(rr[1]) >= int(fl.get("rank_min", 0)):
				any_species = true
		if not any_species:
			_err("%s → %s: ninguna especie activa puede aparecer entre los rangos %s y %s" % [F, id, fl.get("rank_min"), fl.get("rank_max")])
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
			if b.has("eye_color"):
				b["eye_color"] = _to_color(b.eye_color)

func _validate_themes(F: String) -> void:
	for id: String in floor_themes.keys():
		var th: Dictionary = floor_themes[id]
		_req(F, id, th, "nombre", TYPE_STRING)
		if _req(F, id, th, "texturas", TYPE_STRING):
			# Carpeta con "/" final (FloorBuilder le pega el nombre del archivo)
			# y las 5 texturas presentes: si falta una, el piso sale gris.
			var dir := String(th.texturas)
			if not dir.ends_with("/"):
				dir += "/"
			th["texturas"] = dir
			for slot in FloorBuilder.TEXTURE_SLOTS:
				if not ResourceLoader.exists(dir + slot + ".png"):
					_err("%s → tema '%s': falta la textura '%s%s.png'" % [F, id, dir, slot])
		for c: String in ["niebla", "ambiente", "antorcha"]:
			if _req_color(F, id, th, c):
				th[c] = _to_color(th[c])
		for n: String in ["niebla_cerca", "niebla_lejos", "ambiente_energia", "variante_pared", "variante_piso"]:
			if _req(F, id, th, n, TYPE_FLOAT):
				th[n] = float(th[n])
		if float(th.get("niebla_cerca", 0.0)) >= float(th.get("niebla_lejos", 1.0)):
			_err("%s → tema '%s': niebla_cerca debe ser menor que niebla_lejos" % [F, id])
		if _req(F, id, th, "antorcha_cada", TYPE_FLOAT):
			th["antorcha_cada"] = maxi(2, int(th.antorcha_cada))
		if th.has("luna"):
			var m: Dictionary = th.luna
			m["color"] = _to_color(m.get("color", "#ffffff"))
			m["energia"] = float(m.get("energia", 0.3))
		th["id"] = id

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
	for path: String in ["leveling.max_level", "leveling.points_per_level", "leveling.soul_slot_every", "leveling.xp_kill_base",
			"stats.vit_hp", "stats.atq_atk", "stats.def_reduction", "stats.esp_ability", "stats.agi_crit", "stats.agi_flee", "stats.sue_soul", "stats.sue_coins"]:
		if bal(path) == null:
			_err("%s: falta '%s'" % [F, path])
	var curve: Variant = bal("leveling.xp_to_next")
	if typeof(curve) != TYPE_ARRAY or (curve as Array).size() < bal_i("leveling.max_level", 10) - 1:
		_err("%s: leveling.xp_to_next debe ser una lista con la EXP de cada nivel (max_level − 1 valores)" % F)
	else:
		var c: Array = curve
		for i in c.size():
			c[i] = maxi(1, int(c[i]))
	for it: Variant in bal("start_items", []):
		if not items.has(String(it)):
			_err("%s: start_items incluye '%s', que no existe" % [F, it])

func _validate_texts() -> void:
	for k: String in texts.keys():
		if typeof(texts[k]) != TYPE_STRING:
			_err("texts.json → '%s': debe ser texto" % k)
