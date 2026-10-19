extends TestCase
## DataRegistry: carga, validación y fórmulas base.

func test_datos_sin_errores() -> void:
	eq(DataRegistry.errors.size(), 0, "errores de datos: %s" % [DataRegistry.errors])

func test_stats_for_rank_igual_al_prototipo() -> void:
	# Mismos números que Main.stats_for_rank() del prototipo.
	eq(DataRegistry.stats_for_rank(9), {"hp": 14, "atk": 3, "ability_damage": 3}, "rango 9")
	eq(DataRegistry.stats_for_rank(4), {"hp": 24, "atk": 8, "ability_damage": 10}, "rango 4")
	eq(DataRegistry.stats_for_rank(10), {"hp": 12, "atk": 2, "ability_damage": 1}, "rango 10")

func test_json_roto_dice_la_linea() -> void:
	var reg: Node = (load("res://autoload/DataRegistry.gd") as GDScript).new()
	var d: Dictionary = reg.call("parse_json_text", "{\n\"a\": 1,\n\"b\": }", "prueba.json")
	var errs: PackedStringArray = reg.get("errors")
	check(d.is_empty(), "un JSON roto no debe devolver datos")
	check(errs.size() == 1 and errs[0].contains("prueba.json línea 3"), "el error debe decir archivo y línea: %s" % [errs])
	reg.free()

func test_campo_faltante_se_reporta() -> void:
	var reg: Node = (load("res://autoload/DataRegistry.gd") as GDScript).new()
	reg.call("reload")
	var items: Dictionary = reg.get("items")
	(items["venda"] as Dictionary).erase("tipo")
	reg.set("errors", PackedStringArray())
	reg.call("_validate_items")
	var errs: PackedStringArray = reg.get("errors")
	check(errs.size() == 1 and errs[0].contains("'venda': falta el campo 'tipo'"), "mensaje claro: %s" % [errs])
	reg.free()

func test_make_soul_usa_el_rango_del_monstruo() -> void:
	var soul := DataRegistry.make_soul("goblin", 9, "Goblin explorador")
	eq(int(soul.active.damage), 3, "daño de la activa en rango 9")
	eq(int(soul.source_rank), 9, "rango de origen")
	eq(String(soul.passive.effect.type), "damage_reduction_flat", "pasiva")
	var strong := DataRegistry.make_soul("goblin", 2, "Jefe")
	check(int(strong.active.damage) > int(soul.active.damage), "un alma de rango más fuerte pega más")

func test_especies_de_debil_a_fuerte() -> void:
	var ids := DataRegistry.species_ids()
	eq(ids[0], "goblin", "la más débil primero")
	eq(ids[ids.size() - 1], "esqueleto_guardian", "la más fuerte al final")

func test_textos() -> void:
	var key := "no.existe" + ".nunca"
	eq(DataRegistry.t(key), "[no.existe.nunca]", "clave faltante visible")
