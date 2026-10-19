extends TestCase
## FloorGenerator: semilla reproducible, conectividad, jefe/salida, rangos
## por piso y tabla de objetos que solo incluye desbloqueados.

func _gen(n: int, s: int, pool: Array[String] = ["pocion_menor", "venda", "antorcha_vieja"]) -> FloorData:
	return FloorGenerator.generate(n, s, pool)

func test_misma_semilla_mismo_piso() -> void:
	var a := _gen(2, 99)
	var b := _gen(2, 99)
	eq(a.cells, b.cells, "misma grilla")
	eq(a.start_cell, b.start_cell, "mismo inicio")
	eq(a.exit_cell, b.exit_cell, "misma salida")
	eq(a.chests, b.chests, "mismos cofres")
	var ea: Array = a.enemies.map(func(e: Dictionary) -> String: return "%s@%s" % [e.species_id, e.cell])
	var eb: Array = b.enemies.map(func(e: Dictionary) -> String: return "%s@%s" % [e.species_id, e.cell])
	eq(ea, eb, "mismos enemigos")
	var c := _gen(2, 100)
	check(c.cells != a.cells, "otra semilla da otro mapa")

func test_tamano_crece_por_piso() -> void:
	for n in range(1, DataRegistry.floor_count() + 1):
		var fd := _gen(n, 7)
		eq(fd.width, int(DataRegistry.get_floor(n).size), "tamaño del piso %d" % n)
	check(_gen(5, 7).floor_cells().size() > _gen(1, 7).floor_cells().size(), "el piso 5 es más grande que el 1")

func test_todo_es_alcanzable_con_cofres_bloqueando() -> void:
	for s in [1, 2, 3, 4, 5, 6, 7, 8]:
		for n in [1, 3, 5]:
			var fd := _gen(n, s)
			var blocked := {}
			for c in fd.chests:
				blocked[c] = true
			var reach := fd.distances_from(fd.start_cell, blocked)
			for c in fd.floor_cells():
				if not blocked.has(c):
					check(reach.has(c), "semilla %d piso %d: celda %s inalcanzable" % [s, n, c])
			check(reach.has(fd.exit_cell), "semilla %d piso %d: salida alcanzable" % [s, n])

func test_jefe_junto_a_la_salida() -> void:
	for s in [11, 12, 13]:
		var fd := _gen(1, s)
		var bosses := fd.enemies.filter(func(e: Dictionary) -> bool: return e.kind == RunRules.BOSS)
		eq(bosses.size(), 1, "un jefe por piso")
		var b: Dictionary = bosses[0]
		var bc: Vector2i = b.cell
		eq(absi(bc.x - fd.exit_cell.x) + absi(bc.y - fd.exit_cell.y), 1, "el jefe custodia la salida")
		check(fd.boss_room.has_point(fd.exit_cell), "la salida está en la sala del jefe")
		eq(int(b.rank), int(DataRegistry.get_floor(1).boss.rank), "rango del jefe según floors.json")

func test_enemigos_con_rango_del_piso() -> void:
	for n in range(1, DataRegistry.floor_count() + 1):
		var def := DataRegistry.get_floor(n)
		var fd := _gen(n, 31 + n)
		var normals := fd.enemies.filter(func(e: Dictionary) -> bool: return e.kind != RunRules.BOSS)
		check(normals.size() <= int(def.enemies), "piso %d: no más enemigos que los pedidos" % n)
		check(normals.size() >= int(def.enemies) / 2.0, "piso %d: al menos la mitad de los pedidos (%d)" % [n, normals.size()])
		for e: Dictionary in normals:
			check(int(e.rank) >= int(def.rank_min) and int(e.rank) <= int(def.rank_max), "piso %d: rango %d fuera de %d–%d" % [n, e.rank, def.rank_min, def.rank_max])
			check(not fd.is_wall(e.cell), "enemigo sobre una pared")

func test_objetos_solo_del_pool() -> void:
	var fd := _gen(3, 5, ["venda"] as Array[String])
	check(not fd.items.is_empty(), "hay objetos sueltos")
	for it: Dictionary in fd.items:
		eq(String(it.item_id), "venda", "solo objetos disponibles")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var counts := {}
	for i in 2000:
		var id := FloorGenerator.roll_item(rng, ["pocion_menor", "sello_retiro"] as Array[String])
		counts[id] = int(counts.get(id, 0)) + 1
	# pesos 10 vs 2 → ~83% pociones
	check(int(counts.get("pocion_menor", 0)) > int(counts.get("sello_retiro", 0)) * 3, "la tabla respeta los pesos: %s" % [counts])

func test_sala_de_pruebas_igual_al_prototipo() -> void:
	var fd := FloorGenerator.test_room()
	eq(fd.width, 15, "ancho 15")
	eq(fd.height, 9, "alto 9")
	eq(fd.start_cell, Vector2i(2, 4), "inicio del prototipo")
	eq(fd.enemies.size(), 5, "los 5 enemigos conocidos")
	eq(String(fd.enemy_at(Vector2i(9, 4)).get("species_id", "")), "esqueleto_guardian", "esqueleto en (9,4)")
