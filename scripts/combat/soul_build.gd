class_name SoulBuild
extends RefCounted
## Sinergias de las almas que lleva el héroe (data/sinergias.json):
##  - AFINIDADES: cada alma tiene una o dos (hueso, sangre, sombra, espíritu,
##    acero, fortuna). Juntar varias almas de la misma afinidad activa sus
##    niveles (p. ej. 2 y 4 almas); los niveles se acumulan.
##  - PACTOS: dos almas concretas juntas dan un efecto propio.
## effects() suma todo (pasivas + niveles + pactos) en {tipo: valor}, que es
## lo que leen CombatCore (en combate) y GameState (monedas, EXP, almas).
## Sin estado: todo se calcula a partir de la lista de almas.

## {afinidad: cuántas almas la tienen} (solo las que aparecen).
static func affinity_counts(souls: Array) -> Dictionary:
	var counts := {}
	for soul: Dictionary in souls:
		for a: Variant in soul.get("afinidades", []):
			counts[String(a)] = int(counts.get(String(a), 0)) + 1
	return counts

## Cuántos niveles de la afinidad alcanza esa cantidad de almas (0 = ninguno).
static func tier_reached(affinity_id: String, count: int) -> int:
	var reached := 0
	for lv: Dictionary in DataRegistry.get_affinity(affinity_id).get("niveles", []):
		if count >= int(lv.cantidad):
			reached += 1
	return reached

## Una fila por afinidad presente: {id, count, tier, next (almas para el
## siguiente nivel, 0 = completa)}, de más a menos almas.
static func affinity_rows(souls: Array) -> Array:
	var counts := affinity_counts(souls)
	var rows: Array = []
	for id in DataRegistry.affinity_ids():
		if not counts.has(id):
			continue
		var n := int(counts[id])
		var levels: Array = DataRegistry.get_affinity(id).get("niveles", [])
		var tier := tier_reached(id, n)
		var next := int((levels[tier] as Dictionary).cantidad) if tier < levels.size() else 0
		rows.append({"id": id, "count": n, "tier": tier, "next": next})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.count) > int(b.count) if int(a.count) != int(b.count) else int(a.tier) > int(b.tier))
	return rows

static func _soul_ids(souls: Array) -> Dictionary:
	var ids := {}
	for soul: Dictionary in souls:
		ids[String(soul.get("id", ""))] = true
	return ids

## Pactos completos (las dos almas puestas).
static func active_pacts(souls: Array) -> Array[String]:
	var have := _soul_ids(souls)
	var out: Array[String] = []
	for id: String in DataRegistry.pacts.keys():
		var pair: Array = DataRegistry.pacts[id].almas
		if have.has(String(pair[0])) and have.has(String(pair[1])):
			out.append(id)
	return out

## Pactos a medias: {id, have, missing} con una de las dos almas puestas.
static func partial_pacts(souls: Array) -> Array:
	var have := _soul_ids(souls)
	var out: Array = []
	for id: String in DataRegistry.pacts.keys():
		var pair: Array = DataRegistry.pacts[id].almas
		var a := have.has(String(pair[0]))
		var b := have.has(String(pair[1]))
		if a != b:
			out.append({"id": id, "have": String(pair[0] if a else pair[1]), "missing": String(pair[1] if a else pair[0])})
	return out

## Pactos en los que entra un alma (por id de plantilla).
static func pacts_with(soul_id: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in DataRegistry.pacts.keys():
		if (DataRegistry.pacts[id].almas as Array).has(soul_id):
			out.append(id)
	return out

## Todos los efectos sumados: pasivas + niveles de afinidad + pactos.
static func effects(souls: Array) -> Dictionary:
	var fx := {}
	for soul: Dictionary in souls:
		var passive: Variant = soul.get("passive")
		if passive is Dictionary:
			_add(fx, (passive as Dictionary).get("effect", {}))
	var counts := affinity_counts(souls)
	for id: String in counts.keys():
		var levels: Array = DataRegistry.get_affinity(id).get("niveles", [])
		for i in tier_reached(id, int(counts[id])):
			for e: Dictionary in (levels[i] as Dictionary).efectos:
				_add(fx, e)
	for id in active_pacts(souls):
		for e: Dictionary in DataRegistry.get_pact(id).efectos:
			_add(fx, e)
	return fx

## De dónde sale un efecto (el aviso «salta una sinergia» del combate):
## [{kind: "pact"|"affinity"|"passive", name, group, icon, ramp}], primero
## los pactos, después los niveles de afinidad y las pasivas.
static func sources(souls: Array, type: String) -> Array:
	var out: Array = []
	for id in active_pacts(souls):
		var pact := DataRegistry.get_pact(id)
		if _has_type(pact.efectos, type):
			out.append({"kind": "pact", "name": String(pact.nombre), "group": "", "icon": "almas", "ramp": "alma"})
	var counts := affinity_counts(souls)
	for id in DataRegistry.affinity_ids():
		if not counts.has(id):
			continue
		var af := DataRegistry.get_affinity(id)
		var levels: Array = af.get("niveles", [])
		for i in tier_reached(id, int(counts[id])):
			var lv: Dictionary = levels[i]
			if _has_type(lv.efectos, type):
				out.append({"kind": "affinity", "name": String(lv.nombre), "group": String(af.nombre), "icon": String(af.icono), "ramp": String(af.rampa)})
	for soul: Dictionary in souls:
		var passive: Variant = soul.get("passive")
		if passive is Dictionary and String(((passive as Dictionary).get("effect", {}) as Dictionary).get("type", "")) == type:
			out.append({"kind": "passive", "name": String((passive as Dictionary).get("name", "")), "group": "", "icon": "almas", "ramp": "alma"})
	return out

static func _has_type(list: Array, type: String) -> bool:
	for e: Dictionary in list:
		if String(e.get("type", "")) == type:
			return true
	return false

static func _add(fx: Dictionary, e: Dictionary) -> void:
	var type := String(e.get("type", ""))
	if type != "":
		fx[type] = float(fx.get(type, 0.0)) + float(e.get("value", 0.0))

static func total(souls: Array, type: String) -> float:
	return float(effects(souls).get(type, 0.0))

## Qué cambiaría en las sinergias si se agrega `soul` (reemplazando la de
## replace_index, o sumándola con -1): {tiers: [{id, tier}] niveles nuevos,
## lost: [...] niveles que se pierden, pacts: [...] pactos nuevos,
## pacts_lost: [...]}. Lo usa la revelación del alma para avisar.
static func diff_if_added(souls: Array, soul: Dictionary, replace_index := -1) -> Dictionary:
	var after := souls.duplicate()
	if replace_index >= 0 and replace_index < after.size():
		after[replace_index] = soul
	else:
		after.append(soul)
	var before_counts := affinity_counts(souls)
	var after_counts := affinity_counts(after)
	var gained: Array = []
	var lost: Array = []
	for id in DataRegistry.affinity_ids():
		var t0 := tier_reached(id, int(before_counts.get(id, 0)))
		var t1 := tier_reached(id, int(after_counts.get(id, 0)))
		if t1 > t0:
			gained.append({"id": id, "tier": t1})
		elif t1 < t0:
			lost.append({"id": id, "tier": t0})
	var p0 := active_pacts(souls)
	var p1 := active_pacts(after)
	var new_pacts: Array = []
	var lost_pacts: Array = []
	for id in p1:
		if not p0.has(id):
			new_pacts.append(id)
	for id in p0:
		if not p1.has(id):
			lost_pacts.append(id)
	return {"tiers": gained, "lost": lost, "pacts": new_pacts, "pacts_lost": lost_pacts}
