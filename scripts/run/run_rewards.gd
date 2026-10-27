class_name RunRewards
extends RefCounted
## Calcula TODO lo que una run le deja al estado persistente, sin aplicarlo:
## monedas desglosadas (kills, jefes, cofres, primeras kills, bonus de Botín,
## lo que se pierde al morir), especies nuevas del bestiario, desbloqueos
## ganados y el progreso acumulado resultante. RunSummary lo muestra y luego
## llama a MetaState.apply_run_result(result) una sola vez.
##
## Es una función pura sobre (snapshot de la run, MetaState): testeable sin
## escenas (tests/unit/test_rewards.gd).

static func compute(snap: Dictionary, meta: Node) -> Dictionary:
	var breakdown: Dictionary = snap.get("coin_breakdown", {})
	var kills_coins := int(breakdown.get("kills", 0))
	var boss_coins := int(breakdown.get("boss", 0))
	var chest_coins := int(breakdown.get("chests", 0))

	# Primera kill de especie: bonus una sola vez en toda la partida.
	var new_species: Array = []
	var first_kill_coins := 0
	var kill_ids: Array = (snap.get("kills_by_species", {}) as Dictionary).keys()
	kill_ids.sort()
	for sid: Variant in kill_ids:
		if meta.call("has_killed", String(sid)):
			continue
		var sp := DataRegistry.get_species(String(sid))
		var rank := int(sp.get("rank", 10))
		var bonus := RunRules.first_kill_bonus(rank)
		first_kill_coins += bonus
		new_species.append({"id": sid, "name": sp.get("display_name", sid), "rank": rank, "bonus": bonus})

	var subtotal := kills_coins + boss_coins + chest_coins + first_kill_coins
	var botin_pct := float(meta.call("upgrade_bonus", "coin_bonus_pct"))
	var botin_bonus := roundi(float(subtotal) * botin_pct / 100.0)
	var gross := subtotal + botin_bonus
	var outcome := String(snap.get("outcome", "muerte"))
	var keep := RunRules.keep_fraction(outcome)
	var total := floori(float(gross) * keep)

	# La sala de pruebas es una herramienta de debug: no deja nada.
	var test_room := bool(snap.get("test_room", false))
	if test_room:
		total = 0

	var meta_progress: Dictionary = meta.get("progress")
	var progress_after := UnlockEvaluator.merged_progress(meta_progress, snap, total)
	var new_unlocks: Array[String] = []
	if not test_room:
		new_unlocks = UnlockEvaluator.evaluate(DataRegistry.unlocks, progress_after, snap, meta.get("unlocked"))

	return {
		"snapshot": snap,
		"outcome": outcome,
		"test_room": test_room,
		"coins": {
			"kills": kills_coins,
			"boss": boss_coins,
			"chests": chest_coins,
			"first_kill": first_kill_coins,
			"subtotal": subtotal,
			"botin_pct": botin_pct,
			"botin_bonus": botin_bonus,
			"gross": gross,
			"keep_fraction": keep,
			"lost": gross - total if not test_room else 0,
			"total": total,
		},
		"new_species": new_species,
		"new_unlocks": new_unlocks,
		"progress_after": progress_after if not test_room else meta_progress.duplicate(true),
	}
