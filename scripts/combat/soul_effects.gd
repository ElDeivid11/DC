class_name SoulEffects
extends RefCounted
## Textos de las almas: qué hace una activa, una pasiva o un efecto de
## sinergia, y los modificadores de estadísticas. Los efectos se suman en
## SoulBuild y se aplican en CombatCore / GameState; sumar un tipo nuevo =
## agregarlo a DataRegistry.SOUL_EFFECTS + aplicarlo + su texto en
## data/texts.json ("effect.<tipo>").

## Efectos que se muestran en % (valor × 100).
const PERCENT: Array[String] = [
	"defend_bonus_multiplier", "lifesteal_pct", "crit_chance", "coin_bonus_pct",
	"bleed_lifesteal_pct", "bleed_apply_mult", "crit_damage_bonus", "crit_marks",
	"defend_counter", "shield_mult", "execute_threshold_bonus", "drain_bonus_pct",
	"mark_bonus", "xp_bonus_pct",
]

## Suma de un tipo de efecto entre las almas del personaje (pasivas,
## afinidades y pactos).
static func total(member: Dictionary, effect_type: String) -> float:
	return SoulBuild.total(member.get("souls", []), effect_type)

## Texto corto de qué hace un efecto: "(-1 daño recibido)".
static func effect_hint(effect: Dictionary) -> String:
	var type := String(effect.get("type", ""))
	var key := "effect." + type
	if not DataRegistry.has_text(key):
		return ""
	if not String(DataRegistry.texts[key]).contains("%"):
		return DataRegistry.t(key)
	var v := float(effect.get("value", 0))
	var shown: int = roundi(v * 100.0) if PERCENT.has(type) else roundi(v)
	return DataRegistry.t(key, [shown])

## Los efectos de una lista [{type, value}] separados por " ".
static func effects_text(effects: Array) -> String:
	var parts: Array[String] = []
	for e: Dictionary in effects:
		parts.append(effect_hint(e))
	return " ".join(parts)

## "ATK +2 · HP máx. +2" (o "" si no tiene).
static func modifiers_text(mods: Dictionary) -> String:
	var parts: Array[String] = []
	for k: Variant in mods.keys():
		var key := "stat." + String(k)
		var label := DataRegistry.t(key) if DataRegistry.has_text(key) else String(k)
		parts.append("%s +%s" % [label, str(mods[k])])
	return " · ".join(parts)

## Qué hace una activa. Con un CombatCore y el índice del alma, con las
## cifras de ese héroe (ataque, ESP, sinergias); sin él, en % del poder.
static func active_text(active: Dictionary, core: CombatCore = null, i := -1) -> String:
	var known := core != null and i >= 0 and i < core.soul_count()
	var poder := float(active.get("poder", 1.0))
	var dmg := str(core.ability_hit(i)) if known else DataRegistry.t("active.power_rel", [roundi(poder * 100.0)])
	var txt := ""
	match String(active.get("tipo", "")):
		"golpe":
			txt = DataRegistry.t("active.golpe", [dmg])
			if float(active.get("critico", 0.0)) > 0.0:
				txt += DataRegistry.t("active.critico", [roundi(float(active.critico) * 100.0)])
		"multigolpe":
			txt = DataRegistry.t("active.multigolpe", [core.ability_hits(i) if known else int(active.get("golpes", 1)), dmg])
		"sangrado":
			txt = DataRegistry.t("active.sangrado", [dmg, core.ability_bleed(i) if known else int(active.get("sangrado", 0))])
		"aturdir":
			txt = DataRegistry.t("active.aturdir", [dmg, core.ability_stun(i) if known else int(active.get("turnos", 1))])
		"drenar":
			var cura := float(active.get("cura", 0.0)) + (core._fx("drain_bonus_pct") if known else 0.0)
			txt = DataRegistry.t("active.drenar", [dmg, roundi(cura * 100.0)])
		"escudo":
			txt = DataRegistry.t("active.escudo", [str(core.ability_shield(i)) if known else DataRegistry.t("active.power_rel", [roundi(poder * 100.0)])])
		"marca":
			var m := float(active.get("marca", 0.0)) + (core._fx("mark_bonus") if known else 0.0)
			txt = DataRegistry.t("active.marca", [dmg, roundi(m * 100.0)])
		"debilitar":
			txt = DataRegistry.t("active.debilitar", [dmg, roundi(float(active.get("debilita", 0.0)) * 100.0), int(active.get("turnos", 1))])
		"ejecutar":
			var umbral := core.execute_threshold(i) if known else float(active.get("umbral", 0.0))
			txt = DataRegistry.t("active.ejecutar", [dmg, UIFormat.mult(float(active.get("mult", 2.0))), roundi(umbral * 100.0)])
	return txt

## "Recarga: cada 3 turnos" (con las sinergias del héroe si hay núcleo).
static func recharge_text(active: Dictionary, core: CombatCore = null, i := -1) -> String:
	var r := core.recharge(i) if core != null and i >= 0 and i < core.soul_count() else int(active.get("recarga", 1))
	return DataRegistry.t("active.recarga_1") if r <= 1 else DataRegistry.t("active.recarga", [r])
