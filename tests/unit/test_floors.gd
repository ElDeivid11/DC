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
				if not blocked.has(c) and not fd.solid.has(c):
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
	eq(fd.enemies.size(), 6, "un ejemplar de cada enemigo + variantes")
	eq(String(fd.enemy_at(Vector2i(9, 4)).get("species_id", "")), "esqueleto_guardian", "esqueleto en (9,4)")
	var boss := fd.enemy_at(Vector2i(12, 4))
	eq(String(boss.get("kind", "")), RunRules.BOSS, "el jefe está en la sala")
	check(bool(fd.enemy_at(Vector2i(4, 2)).get("dormant", false)), "hay un esqueleto dormido")

func test_sorteo_de_enemigos() -> void:
	# Pool: solo especies activas que no son jefe y cuyo rank_range se cruza.
	var pool := FloorGenerator.species_pool(8, 9)
	check(pool.has("esqueleto_esbirro") and pool.has("esqueleto_picaro"), "las básicas en el piso 1: %s" % [pool])
	check(not pool.has("esqueleto_guardian"), "la élite no baja hasta rango 8")
	check(not pool.has("nigromante"), "el jefe nunca sale como enemigo común")
	check(not pool.has("goblin"), "las inactivas no salen")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var deep := FloorGenerator.species_pool(2, 5)
	var counts := {}
	for i in 3000:
		var r := FloorGenerator.roll_enemy(rng, deep, 2, 5)
		var sp := DataRegistry.get_species(String(r.species_id))
		var rr: Array = sp.rank_range
		check(int(r.rank) >= maxi(2, int(rr[0])) and int(r.rank) <= mini(5, int(rr[1])), "rango dentro del cruce: %s" % [r])
		if String(sp.tier) == "elite":
			eq(String(r.kind), RunRules.ELITE, "una especie élite siempre es élite")
		counts[r.species_id] = int(counts.get(r.species_id, 0)) + 1
	# pesos 5 / 4 / 1.5 → el esbirro sale más que el guardián
	check(int(counts.get("esqueleto_esbirro", 0)) > int(counts.get("esqueleto_guardian", 0)) * 2, "respeta los pesos: %s" % [counts])

func test_dormidos_solo_si_la_especie_puede() -> void:
	for n in range(1, DataRegistry.floor_count() + 1):
		var fd := _gen(n, 70 + n)
		for e: Dictionary in fd.enemies:
			if e.kind == RunRules.BOSS:
				# El jefe duerme sobre su círculo hasta su presentación.
				check(bool(e.get("dormant", false)) and bool(e.get("intro", false)), "el jefe espera su presentación")
			elif bool(e.get("dormant", false)):
				check(float(DataRegistry.get_species(String(e.species_id)).dormant_chance) > 0.0, "%s no debería dormir" % e.species_id)

## Sala del jefe hecha a mano: está entera (el dibujo de floors.json, girado),
## apoyada en el mapa, con la puerta hacia un pasillo alcanzable desde el
## inicio; puerta, jefe y salida en el mismo eje; y adentro solo lo suyo.
func test_sala_del_jefe() -> void:
	var sides := {}
	for n in range(1, DataRegistry.floor_count() + 1):
		for seed_i in 6:
			var fd := _gen(n, 110 + n * 13 + seed_i)
			var tag := "piso %d semilla %d" % [n, seed_i]
			var r := fd.boss_room
			check(Rect2i(0, 0, fd.width, fd.height).encloses(r), tag + ": la sala entra en el mapa")
			var turns := posmod(fd.boss_door_dir - 0, 4)
			sides[turns] = true
			# El dibujo mira al norte (se entra hacia el norte); girado `turns`
			# cuartos de vuelta, se entra hacia DIRS[turns].
			var rows := FloorGenerator.boss_room_rows(turns)
			eq(Vector2i(rows[0].length(), rows.size()), r.size, tag + ": tamaño del dibujo girado")
			var braziers := 0
			for y in rows.size():
				for x in rows[y].length():
					var ch := rows[y][x]
					var c := r.position + Vector2i(x, y)
					eq(fd.is_wall(c), ch == "#" or ch == "T", "%s: celda %s ('%s')" % [tag, c, ch])
					if ch == "b":
						braziers += 1
					if ch == "b" or ch == "p":
						check(fd.solid.has(c), tag + ": brasero o columna bloquean")
			eq(fd.braziers.size(), braziers, tag + ": un brasero por cada b del dibujo")
			var inward: Vector2i = FloorGenerator.DIRS[fd.boss_door_dir]
			var porch := fd.boss_door - inward
			check(not r.has_point(porch) and not fd.is_wall(porch), tag + ": la puerta da a un pasillo")
			var reach := fd.distances_from(fd.start_cell)
			check(reach.has(porch), tag + ": la puerta se alcanza desde el inicio")
			check(int(reach.get(porch, 0)) >= 6, tag + ": el inicio queda lejos de la puerta")
			var boss: Dictionary = {}
			for e: Dictionary in fd.enemies:
				if e.kind == RunRules.BOSS:
					boss = e
				else:
					check(not r.has_point(e.cell), tag + ": ningún otro enemigo en la sala")
			var bc: Vector2i = boss.get("cell", Vector2i(-9, -9))
			eq(bc, fd.boss_circle, tag + ": el jefe duerme sobre el círculo")
			eq(fd.exit_cell, bc + inward, tag + ": la salida, justo detrás del jefe")
			var axis := bc - fd.boss_door
			check(axis.x * inward.y - axis.y * inward.x == 0, tag + ": puerta y jefe en el mismo eje")
			check(String(boss.get("epithet", "")) != "", tag + ": el jefe tiene epíteto")
			for c in fd.chests:
				check(not r.has_point(c), tag + ": sin cofres en la sala")
			for it: Dictionary in fd.items:
				check(not r.has_point(it.cell), tag + ": sin objetos sueltos en la sala")
			for p: Dictionary in fd.props:
				var pos: Vector3 = p.pos
				check(not r.has_point(Vector2i(floori(pos.x / FloorBuilder.CELL_SIZE), floori(pos.z / FloorBuilder.CELL_SIZE))), tag + ": sin cajas ni barriles en la sala")
	eq(sides.size(), 4, "la sala aparece en las cuatro orientaciones")

func test_elite_de_especie_sin_sufijo() -> void:
	var g := FloorGenerator.make_enemy(Vector2i(1, 1), "esqueleto_guardian", RunRules.ELITE, 4)
	eq(String(g.display_name), "Esqueleto guardián", "la élite por especie no lleva sufijo")
	eq(float(g.scale_mult), 1.0, "ni escala extra")
	eq(int(g.rank), 4, "rango pedido")
	var b := FloorGenerator.make_enemy(Vector2i(1, 1), "esqueleto_esbirro", RunRules.ELITE)
	check(String(b.display_name) != "Esqueleto esbirro", "la variante élite de una básica sí lleva sufijo")
	eq(int(b.rank), 9, "sin rango pedido = el de la especie")

func test_antorchas_en_paredes_y_separadas() -> void:
	for n in range(1, DataRegistry.floor_count() + 1):
		var fd := _gen(n, 90 + n)
		var every := int(DataRegistry.get_theme(n).antorcha_cada)
		check(fd.torches.size() >= 2, "piso %d: hay antorchas (%d)" % [n, fd.torches.size()])
		for i in fd.torches.size():
			var t: Dictionary = fd.torches[i]
			var c: Vector2i = t.cell
			check(not fd.is_wall(c), "antorcha en una celda de piso")
			check(fd.is_wall(c + FloorGenerator.DIRS[int(t.dir)]), "antorcha sobre una pared")
			# Las de la sala del jefe van donde dice su dibujo (las T).
			if fd.boss_room.has_point(c):
				continue
			for j in range(i + 1, fd.torches.size()):
				var o: Vector2i = (fd.torches[j] as Dictionary).cell
				check(absi(o.x - c.x) + absi(o.y - c.y) >= every, "piso %d: antorchas demasiado juntas" % n)
		check(fd.torches.any(func(t: Dictionary) -> bool: return fd.rooms[0].has_point(t.cell)), "piso %d: una en la sala de inicio" % n)
