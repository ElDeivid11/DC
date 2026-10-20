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
	var soul := DataRegistry.make_soul("esqueleto_picaro", 9, "Esqueleto ballestero")
	eq(int(soul.active.damage), 3, "daño de la activa en rango 9")
	eq(int(soul.source_rank), 9, "rango de origen")
	eq(String(soul.passive.effect.type), "crit_chance", "pasiva")
	var strong := DataRegistry.make_soul("esqueleto_picaro", 2, "Jefe")
	check(int(strong.active.damage) > int(soul.active.damage), "un alma de rango más fuerte pega más")

func test_especies_de_debil_a_fuerte() -> void:
	var ids := DataRegistry.species_ids()
	eq(ids[0], "esqueleto_esbirro", "la más débil primero")
	eq(ids[ids.size() - 1], "nigromante", "la más fuerte al final")
	check(not ids.has("goblin"), "las inactivas no aparecen")
	check(DataRegistry.species_ids(true).has("goblin"), "...salvo que se pidan")

func test_textos() -> void:
	var key := "no.existe" + ".nunca"
	eq(DataRegistry.t(key), "[no.existe.nunca]", "clave faltante visible")

func test_visual_de_especie() -> void:
	var sp := DataRegistry.get_species("esqueleto_guardian")
	var v: Dictionary = sp.visual
	check(typeof(v.eye_color) == TYPE_COLOR, "eye_color normalizado a Color")
	eq(int(v.anim_fps), 12, "anim_fps entero")
	check(ResourceLoader.exists(String(v.weapon_l)), "el escudo existe")
	var reg: Node = (load("res://autoload/DataRegistry.gd") as GDScript).new()
	reg.call("reload")
	var species: Dictionary = reg.get("species")
	((species["esqueleto_esbirro"] as Dictionary).visual as Dictionary)["model_path"] = "res://no/existe.glb"
	reg.set("errors", PackedStringArray())
	reg.call("_validate_species")
	var errs: PackedStringArray = reg.get("errors")
	check(errs.size() == 1 and errs[0].contains("no/existe.glb"), "modelo inexistente se reporta: %s" % [errs])
	reg.free()

func test_tema_valida_texturas() -> void:
	var reg: Node = (load("res://autoload/DataRegistry.gd") as GDScript).new()
	reg.call("reload")
	var themes: Dictionary = reg.get("floor_themes")
	(themes["luna"] as Dictionary)["texturas"] = "res://assets/textures/luna"
	(themes["abismo"] as Dictionary)["texturas"] = "res://assets/textures/no_existe/"
	reg.set("errors", PackedStringArray())
	reg.call("_validate_themes", "floors.json")
	var errs: PackedStringArray = reg.get("errors")
	eq(String((themes["luna"] as Dictionary).texturas), "res://assets/textures/luna/", "se agrega la barra final")
	check(errs.size() == FloorBuilder.TEXTURE_SLOTS.size() and errs[0].contains("no_existe/wall_a.png"), "cada textura faltante se reporta: %s" % [errs])
	reg.free()
