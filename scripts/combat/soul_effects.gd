class_name SoulEffects
extends RefCounted
## Sistema de pasivas por "tipo de efecto" (heredado del prototipo): cada
## pasiva tiene effect: {"type": "...", "value": ...}. Sumar un tipo nuevo =
## agregarlo a DataRegistry.PASSIVE_EFFECTS + su "case" donde se aplica
## (CombatManager) + su texto en data/texts.json ("effect.<tipo>"), sin tocar
## los datos viejos.
##
## Tipos: damage_reduction_flat, defend_bonus_multiplier, damage_bonus_flat,
## lifesteal_pct, crit_chance, coin_bonus_pct, thorns_flat.

## Busca entre las almas de un personaje la primera pasiva del tipo pedido y
## devuelve su efecto (con "_passive_name" para loguearlo). {} si no tiene.
static func get_passive_effect(member: Dictionary, effect_type: String) -> Dictionary:
	for soul: Dictionary in member.get("souls", []):
		var passive: Variant = soul.get("passive")
		if passive == null:
			continue
		var effect: Dictionary = (passive as Dictionary).get("effect", {})
		if effect.get("type", "") == effect_type:
			var result: Dictionary = effect.duplicate()
			result["_passive_name"] = (passive as Dictionary).name
			return result
	return {}

## Suma de todas las pasivas de ese tipo que lleva el personaje (si tiene
## dos almas con el mismo efecto, se acumulan).
static func total(member: Dictionary, effect_type: String) -> float:
	var sum := 0.0
	for soul: Dictionary in member.get("souls", []):
		var passive: Variant = soul.get("passive")
		if passive == null:
			continue
		var effect: Dictionary = (passive as Dictionary).get("effect", {})
		if effect.get("type", "") == effect_type:
			sum += float(effect.get("value", 0))
	return sum

## Texto corto de qué hace mecánicamente una pasiva: "(-1 daño recibido)".
static func effect_hint(effect: Dictionary) -> String:
	var type := String(effect.get("type", ""))
	var key := "effect." + type
	if not DataRegistry.has_text(key):
		return ""
	var v := float(effect.get("value", 0))
	var shown: int = roundi(v * 100.0) if type.ends_with("_pct") or type.ends_with("_chance") or type.ends_with("_multiplier") else roundi(v)
	return DataRegistry.t(key, [shown])

## "ATK +2 · HP máx. +2" (o "" si no tiene).
static func modifiers_text(mods: Dictionary) -> String:
	var parts: Array[String] = []
	for k: Variant in mods.keys():
		var key := "stat." + String(k)
		var label := DataRegistry.t(key) if DataRegistry.has_text(key) else String(k)
		parts.append("%s +%s" % [label, str(mods[k])])
	return " · ".join(parts)
