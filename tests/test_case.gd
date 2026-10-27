class_name TestCase
extends RefCounted
## Base mínima de tests: cada script de tests/unit/ extiende esto y define
## funciones test_*(). TestRunner las corre una por una y junta los fallos.

var failures: Array[String] = []
var current := ""

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current, msg])

func eq(actual: Variant, expected: Variant, msg := "") -> void:
	if typeof(actual) != typeof(expected) and not (_is_number(actual) and _is_number(expected)):
		failures.append("%s: %s esperaba %s (%s), obtuvo %s (%s)" % [current, msg, expected, type_string(typeof(expected)), actual, type_string(typeof(actual))])
	elif actual != expected:
		failures.append("%s: %s esperaba %s, obtuvo %s" % [current, msg, expected, actual])

func near(actual: float, expected: float, msg := "", eps := 0.0001) -> void:
	if absf(actual - expected) > eps:
		failures.append("%s: %s esperaba ≈%s, obtuvo %s" % [current, msg, expected, actual])

## Snapshot de run mínimo (mismo formato que GameState.snapshot()), con los
## campos que el test quiera pisar.
static func snap(overrides: Dictionary = {}) -> Dictionary:
	var s := {
		"outcome": "muerte",
		"cause": "",
		"floor_n": 1,
		"max_floor": 1,
		"time_sec": 60.0,
		"seed": 1,
		"test_room": false,
		"coin_breakdown": {"kills": 0, "boss": 0, "chests": 0},
		"run_coins": 0,
		"kills_by_species": {},
		"kills_total": 0,
		"seen_species": {},
		"souls_taken": [],
		"souls_taken_by_species": {},
		"items_used": {},
		"flee_count": 0,
		"bosses_defeated": [],
		"boss_species": [],
		"party": [],
	}
	for k: Variant in overrides.keys():
		s[k] = overrides[k]
	return s

static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
