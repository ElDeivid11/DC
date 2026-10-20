class_name RunRules
extends RefCounted
## Fórmulas de balance de la run. Todos los números salen de data/balance.json
## (vía DataRegistry); acá solo está la forma de combinarlos. Sin estado, para
## poder testearlas sueltas (tests/unit/test_rules.gd).

const NORMAL := "normal"
const ELITE := "elite"
const BOSS := "boss"

## Coste del siguiente nivel = coste_base × nivel siguiente. -1 = al tope.
static func upgrade_cost(upgrade: Dictionary, current_level: int) -> int:
	if upgrade.is_empty() or current_level >= int(upgrade.max_nivel):
		return -1
	return int(upgrade.coste_base) * (current_level + 1)

## HP/ataque de un enemigo según rango y tipo (élite y jefe multiplican).
static func enemy_stats(rank: int, kind: String) -> Dictionary:
	var s := DataRegistry.stats_for_rank(rank)
	var mult := 1.0
	if kind == ELITE:
		mult = DataRegistry.bal_f("enemies.elite_stat_mult", 1.25)
	elif kind == BOSS:
		mult = DataRegistry.bal_f("enemies.boss_stat_mult", 1.5)
	return {
		"hp": roundi(float(s.hp) * mult),
		"atk": roundi(float(s.atk) * mult),
		"ability_damage": int(s.ability_damage),
	}

## Monedas por matar: (kill_base − rango); élite ×elite_mult; jefe = 25 × piso.
static func kill_coins(rank: int, kind: String, floor_n: int) -> int:
	if kind == BOSS:
		return DataRegistry.bal_i("coins.boss_per_floor", 25) * maxi(floor_n, 1)
	var c := maxi(DataRegistry.bal_i("coins.kill_base", 11) - rank, 1)
	if kind == ELITE:
		c *= DataRegistry.bal_i("coins.elite_mult", 2)
	return c

## Bonus de primera kill de una especie (una sola vez en toda la partida).
static func first_kill_bonus(rank: int) -> int:
	return DataRegistry.bal_i("coins.first_kill_mult", 10) * (11 - rank)

static func chest_coins(floor_n: int, rng: RandomNumberGenerator) -> int:
	var base := DataRegistry.bal_i("coins.chest_per_floor", 6) * maxi(floor_n, 1)
	return base + rng.randi_range(0, int(float(base) / 2.0))

## Probabilidad de que suelte alma. Jefe 100%; élite fija; normal = base ×
## factor de rango (más fuerte → más chance). Sabiduría suma puntos porcentuales.
static func soul_drop_chance(rank: int, kind: String, wisdom_pct: float) -> float:
	var extra := wisdom_pct / 100.0
	var chance: float
	match kind:
		BOSS:
			return clampf(DataRegistry.bal_f("soul_drop.boss", 1.0), 0.0, 1.0)
		ELITE:
			chance = DataRegistry.bal_f("soul_drop.elite", 0.25) + extra
		_:
			var factor := 1.0 + float(10 - rank) * DataRegistry.bal_f("soul_drop.rank_factor_per_rank", 0.1)
			chance = DataRegistry.bal_f("soul_drop.normal_base", 0.08) * factor + extra
	return clampf(chance, 0.0, 1.0)

## Huir: base ± per_rank por cada rango de diferencia entre el enemigo y el
## rango medio del piso (enemigo más débil que la media → más fácil huir).
static func flee_chance(enemy_rank: int, floor_n: int) -> float:
	var fl := DataRegistry.get_floor(floor_n)
	var ref := 7.0
	if not fl.is_empty():
		ref = (float(fl.rank_min) + float(fl.rank_max)) / 2.0
	var chance := DataRegistry.bal_f("flee.base", 0.5) + DataRegistry.bal_f("flee.per_rank", 0.1) * (float(enemy_rank) - ref)
	return clampf(chance, DataRegistry.bal_f("flee.min", 0.1), DataRegistry.bal_f("flee.max", 0.9))

# --- Niveles y estadísticas (por expedición: se reinician en cada run) ----------

## Las 6 estadísticas que se suben con puntos al subir de nivel (la gráfica
## hexagonal de Estado sigue este orden).
const STATS: Array[String] = ["vit", "atq", "def", "esp", "agi", "sue"]

## EXP que da un enemigo: base + (10 − rango) × por_rango; élite y jefe
## multiplican. La recibe entero cada personaje vivo.
static func kill_xp(rank: int, kind: String) -> int:
	var xp := DataRegistry.bal_f("leveling.xp_kill_base", 3.0) + float(10 - rank) * DataRegistry.bal_f("leveling.xp_per_rank", 1.0)
	if kind == ELITE:
		xp *= DataRegistry.bal_f("leveling.xp_elite_mult", 1.5)
	elif kind == BOSS:
		xp *= DataRegistry.bal_f("leveling.xp_boss_mult", 4.0)
	return maxi(roundi(xp), 1)

static func max_level() -> int:
	return DataRegistry.bal_i("leveling.max_level", 10)

## EXP que falta para pasar de `level` al siguiente (0 = nivel máximo).
static func xp_to_next(level: int) -> int:
	var table: Array = DataRegistry.bal("leveling.xp_to_next", [])
	if level >= max_level() or level < 1 or level > table.size():
		return 0
	return int(table[level - 1])

## Almas extra por nivel: +1 cada `soul_slot_every` niveles (nivel 2, 4, 6…).
static func level_soul_slots(level: int) -> int:
	var every := DataRegistry.bal_i("leveling.soul_slot_every", 2)
	return floori(level / float(every)) if every > 0 else 0

## Efecto de los puntos de una estadística. Los totales se redondean (los
## valores por punto pueden ser fraccionarios: 3 puntos de ATQ = +1 de ataque).
static func stat_hp(vit: int) -> int:
	return roundi(vit * DataRegistry.bal_f("stats.vit_hp", 1.0))

static func stat_atk(atq: int) -> int:
	return roundi(atq * DataRegistry.bal_f("stats.atq_atk", 0.34))

static func stat_def(def: int) -> int:
	return floori(def * DataRegistry.bal_f("stats.def_reduction", 0.25))

static func stat_esp(esp: int) -> int:
	return roundi(esp * DataRegistry.bal_f("stats.esp_ability", 0.5))

static func stat_crit(agi: int) -> float:
	return agi * DataRegistry.bal_f("stats.agi_crit", 0.015)

static func stat_flee(agi: int) -> float:
	return agi * DataRegistry.bal_f("stats.agi_flee", 0.015)

static func stat_soul(sue: int) -> float:
	return sue * DataRegistry.bal_f("stats.sue_soul", 0.005)

static func stat_coins(sue: int) -> float:
	return sue * DataRegistry.bal_f("stats.sue_coins", 0.02)

## Fracción de monedas de la run que se conserva según cómo terminó.
static func keep_fraction(outcome: String) -> float:
	if outcome == "retiro" or outcome == "victoria":
		return 1.0
	return clampf(DataRegistry.bal_f("coins.coin_keep_on_death", 0.5), 0.0, 1.0)
