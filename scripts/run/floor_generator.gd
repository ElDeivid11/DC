class_name FloorGenerator
extends RefCounted
## Genera pisos con semilla (misma semilla + mismo piso = mismo mapa, para
## reproducir bugs). Algoritmo: salas rectangulares sin solaparse + pasillos
## en L que las unen (árbol de "sala más cercana" + algunos lazos extra).
## La salida va en la sala más lejana del inicio, custodiada por el jefe.
## Los cofres bloquean su celda, así que solo se aceptan si no cortan ningún
## camino (se comprueba con BFS).
##
## Se evaluó addons/dungeon_crawler_3d: trabaja con escenas de salas 3D
## prearmadas, conectores y su propio grafo; adoptarlo obligaba a rehacer la
## construcción del mapa (LevelBlock + grilla lógica). Ver
## docs/ESTADO_TECNICO_PROTOTIPO.md.

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const PROPS: Array[String] = ["Crate_1", "Barrel_1", "Crate_2", "Barrel_2_keg", "Crate_1_open", "Barrel_Stand", "Crate_Broken"]

static func generate(floor_n: int, run_seed: int, item_pool: Array[String]) -> FloorData:
	var def := DataRegistry.get_floor(floor_n)
	var gen := DataRegistry.floor_generation
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, floor_n])

	var fd := FloorData.new()
	fd.floor_n = floor_n
	var size := int(def.get("size", 25))
	fd.fill(size, size, FloorData.WALL)

	_place_rooms(fd, rng, gen)
	_connect_rooms(fd, rng)

	var start_room := fd.rooms[0]
	fd.start_cell = _center(start_room)
	fd.start_facing = _best_facing(fd, fd.start_cell)

	var dist := fd.distances_from(fd.start_cell)
	_place_boss_and_exit(fd, dist, def)
	var blocked := {fd.exit_cell: true}
	_place_chests(fd, rng, int(def.get("chests", 2)), blocked)
	for c in fd.chests:
		blocked[c] = true
	_place_enemies(fd, rng, def, dist, blocked, int(gen.get("min_enemy_distance_from_start", 5)))
	_place_items(fd, rng, int(def.get("floor_items", 2)), item_pool, blocked)
	_place_decor(fd, rng, float(gen.get("props_per_room", 1.0)), blocked)
	_place_torches(fd, rng, int(DataRegistry.get_theme(floor_n).get("antorcha_cada", 5)))
	return fd

## La sala 15x9 del prototipo, con columnas y props en los mismos lugares y
## un ejemplar de cada enemigo (incluido el jefe, quieto al fondo y sin
## salida que abrir): para validar combate, almas y animaciones a mano.
static func test_room() -> FloorData:
	var fd := FloorData.new()
	fd.is_test_room = true
	fd.floor_n = 1
	fd.fill(15, 9, FloorData.WALL)
	for y in range(1, 8):
		for x in range(1, 14):
			fd.set_cell(Vector2i(x, y), FloorData.FLOOR)
	fd.rooms = [Rect2i(1, 1, 13, 7)]
	for c in fd.floor_cells():
		fd.ceilings[c] = DataRegistry.bal_f("render.boss_room_height", 3.0)
	fd.start_cell = Vector2i(2, 4)
	fd.start_facing = 1
	# [celda, especie, rango, tipo, dormido]. El orden importa: el Hub usa los
	# tres primeros de fondo.
	var layout: Array = [
		[Vector2i(9, 4), "esqueleto_guardian", 5, RunRules.ELITE, false],
		[Vector2i(12, 4), "nigromante", 7, RunRules.BOSS, false],
		[Vector2i(12, 2), "esqueleto_esbirro", 9, RunRules.NORMAL, false],
		[Vector2i(12, 6), "esqueleto_picaro", 8, RunRules.NORMAL, false],
		[Vector2i(4, 2), "esqueleto_esbirro", 8, RunRules.NORMAL, true],
		[Vector2i(4, 6), "esqueleto_picaro", 7, RunRules.NORMAL, false],
	]
	for i in layout.size():
		var row: Array = layout[i]
		var e := make_enemy(row[0], String(row[1]), String(row[3]), int(row[2]))
		e["dormant"] = bool(row[4])
		e["variant_seed"] = i * 7919
		if e.kind == RunRules.BOSS:
			_apply_boss_def(e, DataRegistry.get_floor(1).get("boss", {}))
		fd.enemies.append(e)
	fd.pillars = [Vector3(7 * 2.0 + 0.6, 0, 2 * 2.0 + 0.6), Vector3(7 * 2.0 + 0.6, 0, 6 * 2.0 + 0.6)]
	fd.props = [
		{"prop": "Crate_1", "pos": Vector3(3 * 2.0 + 0.5, 0, 2 * 2.0 + 0.5), "rot": 15.0},
		{"prop": "Barrel_1", "pos": Vector3(7 * 2.0 + 0.5, 0, 4 * 2.0 - 0.5), "rot": -20.0},
		{"prop": "Crate_2", "pos": Vector3(11 * 2.0 - 0.5, 0, 4 * 2.0 + 0.5), "rot": 40.0},
	]
	fd.torches = [
		{"cell": Vector2i(4, 1), "dir": 0},
		{"cell": Vector2i(8, 7), "dir": 2},
		{"cell": Vector2i(13, 4), "dir": 1},
		{"cell": Vector2i(1, 6), "dir": 3},
	]
	fd.exit_cell = Vector2i(-1, -1)
	return fd

## rank < 0 = el rango base de la especie. Una especie de tier "elite" ya es
## élite por sí misma (modelo propio): no lleva sufijo, tinte ni escala extra;
## eso queda para las básicas que salen como variante élite.
static func make_enemy(cell: Vector2i, species_id: String, kind: String, rank := -1) -> Dictionary:
	var sp := DataRegistry.get_species(species_id)
	var visual: Dictionary = sp.get("visual", {})
	var e := {
		"cell": cell,
		"species_id": species_id,
		"rank": int(sp.rank) if rank < 0 else rank,
		"kind": kind,
		"display_name": String(sp.display_name),
		"soul_id": String(sp.soul_id),
		"scale_mult": 1.0,
		"tint": Color.WHITE,
		"eye_color": visual.get("eye_color", Color.WHITE),
		"facing": 2,
		"stunned": 0,
		"dormant": false,
		"variant_seed": cell.x * 31 + cell.y * 17,
	}
	if kind == RunRules.ELITE and String(sp.get("tier", "basico")) != "elite":
		e["display_name"] = DataRegistry.t("enemy.elite_name", [sp.display_name])
		e["scale_mult"] = DataRegistry.bal_f("enemies.elite_scale", 1.15)
		var tint: Array = DataRegistry.bal("enemies.elite_tint", [1.0, 0.9, 0.78])
		e["tint"] = Color(float(tint[0]), float(tint[1]), float(tint[2]))
		# Ojos ámbar: la élite se reconoce en la oscuridad antes de verla entera.
		e["eye_color"] = Color.html(String(DataRegistry.bal("enemies.elite_eye", "#ffb040")))
	return e

## Especies que pueden salir como enemigo común entre los rangos dados:
## activas, que no sean jefe, con peso > 0 y cuyo rank_range se cruce.
static func species_pool(rank_min: int, rank_max: int) -> Array[String]:
	var pool: Array[String] = []
	for sid in DataRegistry.species_ids():
		var sp := DataRegistry.get_species(sid)
		if String(sp.tier) == "jefe" or float(sp.peso) <= 0.0:
			continue
		var rr: Array = sp.rank_range
		if int(rr[0]) <= rank_max and int(rr[1]) >= rank_min:
			pool.append(sid)
	return pool

## Sorteo de un enemigo común: especie ponderada por "peso", rango al azar en
## el cruce (rank_range de la especie ∩ rango del piso) y tipo: las especies
## "elite" siempre lo son; las básicas, con enemies.elite_chance.
## Devuelve {species_id, rank, kind}. Lo usan el generador y tools/balance_sim.
static func roll_enemy(rng: RandomNumberGenerator, pool: Array[String], rank_min: int, rank_max: int) -> Dictionary:
	var total := 0.0
	for sid in pool:
		total += float(DataRegistry.get_species(sid).peso)
	var chosen := pool[pool.size() - 1]
	var pick := rng.randf() * total
	for sid in pool:
		pick -= float(DataRegistry.get_species(sid).peso)
		if pick < 0.0:
			chosen = sid
			break
	var sp := DataRegistry.get_species(chosen)
	var rr: Array = sp.rank_range
	var rank := rng.randi_range(maxi(int(rr[0]), rank_min), mini(int(rr[1]), rank_max))
	var kind := RunRules.NORMAL
	if String(sp.tier) == "elite":
		kind = RunRules.ELITE
	elif rng.randf() < DataRegistry.bal_f("enemies.elite_chance", 0.1):
		kind = RunRules.ELITE
	return {"species_id": chosen, "rank": rank, "kind": kind}

## Datos del jefe de floors.json sobre un enemigo ya armado.
static func _apply_boss_def(boss: Dictionary, b: Dictionary) -> void:
	boss["rank"] = int(b.get("rank", boss.rank))
	boss["display_name"] = String(b.get("display_name", boss.display_name))
	boss["soul_id"] = String(b.get("soul_id", boss.soul_id))
	boss["scale_mult"] = float(b.get("scale_mult", 1.0))
	boss["tint"] = b.get("tint", Color.WHITE)
	if b.has("eye_color"):
		boss["eye_color"] = b.eye_color

# --- Pasos --------------------------------------------------------------------------

static func _place_rooms(fd: FloorData, rng: RandomNumberGenerator, gen: Dictionary) -> void:
	var rmin := int(gen.get("room_min", 3))
	var rmax := int(gen.get("room_max", 7))
	var target := maxi(4, int(float(fd.width * fd.height) / float(gen.get("cells_per_room", 65))))
	for _attempt in int(gen.get("room_attempts", 400)):
		if fd.rooms.size() >= target:
			break
		var w := rng.randi_range(rmin, rmax)
		var h := rng.randi_range(rmin, rmax)
		var x := rng.randi_range(1, fd.width - w - 1)
		var y := rng.randi_range(1, fd.height - h - 1)
		var rect := Rect2i(x, y, w, h)
		var ok := true
		for other in fd.rooms:
			if other.grow(1).intersects(rect):
				ok = false
				break
		if not ok:
			continue
		fd.rooms.append(rect)
		for cy in range(rect.position.y, rect.end.y):
			for cx in range(rect.position.x, rect.end.x):
				fd.set_cell(Vector2i(cx, cy), FloorData.FLOOR)

static func _connect_rooms(fd: FloorData, rng: RandomNumberGenerator) -> void:
	var connected: Array[int] = [0]
	for i in range(1, fd.rooms.size()):
		var best := 0
		var best_d := INF
		for j in connected:
			var d := Vector2(_center(fd.rooms[i]) - _center(fd.rooms[j])).length()
			if d < best_d:
				best_d = d
				best = j
		_carve_corridor(fd, rng, _center(fd.rooms[i]), _center(fd.rooms[best]))
		connected.append(i)
	# Algunos lazos extra: un roguelike sin ciclos se siente como un pasillo.
	for _k in int(fd.rooms.size() / 4.0):
		var a := rng.randi_range(0, fd.rooms.size() - 1)
		var b := rng.randi_range(0, fd.rooms.size() - 1)
		if a != b:
			_carve_corridor(fd, rng, _center(fd.rooms[a]), _center(fd.rooms[b]))

static func _carve_corridor(fd: FloorData, rng: RandomNumberGenerator, a: Vector2i, b: Vector2i) -> void:
	var corner := Vector2i(b.x, a.y) if rng.randf() < 0.5 else Vector2i(a.x, b.y)
	for seg: Array in [[a, corner], [corner, b]]:
		var from: Vector2i = seg[0]
		var to: Vector2i = seg[1]
		var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
		var c := from
		fd.set_cell(c, FloorData.FLOOR)
		while c != to:
			c += step
			fd.set_cell(c, FloorData.FLOOR)

static func _center(r: Rect2i) -> Vector2i:
	return r.get_center()

## Mira hacia donde hay más espacio abierto (así el primer cuadro muestra la sala).
static func _best_facing(fd: FloorData, cell: Vector2i) -> int:
	var best := 1
	var best_run := -1
	for i in DIRS.size():
		var run := 0
		var c := cell + DIRS[i]
		while not fd.is_wall(c) and run < 6:
			run += 1
			c += DIRS[i]
		if run > best_run:
			best_run = run
			best = i
	return best

static func _room_index_of(fd: FloorData, cell: Vector2i) -> int:
	for i in fd.rooms.size():
		if fd.rooms[i].has_point(cell):
			return i
	return -1

static func _place_boss_and_exit(fd: FloorData, dist: Dictionary, def: Dictionary) -> void:
	var boss_i := 1 if fd.rooms.size() > 1 else 0
	var far := -1
	for i in range(1, fd.rooms.size()):
		var d := int(dist.get(_center(fd.rooms[i]), -1))
		if d > far:
			far = d
			boss_i = i
	fd.boss_room = fd.rooms[boss_i]
	var tall := DataRegistry.bal_f("render.boss_room_height", 3.0)
	for y in range(fd.boss_room.position.y, fd.boss_room.end.y):
		for x in range(fd.boss_room.position.x, fd.boss_room.end.x):
			fd.ceilings[Vector2i(x, y)] = tall
	var exit := _center(fd.boss_room)
	var exit_d := -1
	for y in range(fd.boss_room.position.y, fd.boss_room.end.y):
		for x in range(fd.boss_room.position.x, fd.boss_room.end.x):
			var c := Vector2i(x, y)
			if int(dist.get(c, -1)) > exit_d:
				exit_d = int(dist.get(c, -1))
				exit = c
	fd.exit_cell = exit
	# El jefe se para en la celda anterior a la salida, sobre el camino.
	var boss_cell := exit
	for d in DIRS:
		var n := exit + d
		if not fd.is_wall(n) and int(dist.get(n, -1)) == exit_d - 1:
			boss_cell = n
			break
	var b: Dictionary = def.get("boss", {})
	var boss := make_enemy(boss_cell, String(b.species), RunRules.BOSS)
	_apply_boss_def(boss, b)
	# Mira hacia el camino por el que llega el equipo.
	for i in DIRS.size():
		if int(dist.get(boss_cell + DIRS[i], -1)) == int(dist.get(boss_cell, 0)) - 1:
			boss["facing"] = i
			break
	fd.enemies.append(boss)

static func _is_connected(fd: FloorData, blocked: Dictionary) -> bool:
	var reach := fd.distances_from(fd.start_cell, blocked)
	for c in fd.floor_cells():
		if not blocked.has(c) and not reach.has(c):
			return false
	return true

static func _place_chests(fd: FloorData, rng: RandomNumberGenerator, count: int, blocked: Dictionary) -> void:
	var candidates: Array[Vector2i] = []
	for i in range(1, fd.rooms.size()):
		var r := fd.rooms[i]
		if r == fd.boss_room:
			continue
		for c: Vector2i in [r.position, Vector2i(r.end.x - 1, r.position.y), Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]:
			candidates.append(c)
	_shuffle(candidates, rng)
	var test := blocked.duplicate()
	for c in candidates:
		if fd.chests.size() >= count:
			break
		if test.has(c) or fd.enemy_at(c).size() > 0 or c == fd.start_cell:
			continue
		test[c] = true
		if _is_connected(fd, test):
			fd.chests.append(c)
		else:
			test.erase(c)

static func _place_enemies(fd: FloorData, rng: RandomNumberGenerator, def: Dictionary, dist: Dictionary, blocked: Dictionary, min_dist: int) -> void:
	var pool := species_pool(int(def.rank_min), int(def.rank_max))
	if pool.is_empty():
		return
	var candidates: Array[Vector2i] = []
	for c in fd.floor_cells():
		if blocked.has(c) or fd.boss_room.has_point(c) or int(dist.get(c, 0)) < min_dist:
			continue
		candidates.append(c)
	_shuffle(candidates, rng)
	var placed := 0
	for c in candidates:
		if placed >= int(def.get("enemies", 6)):
			break
		var near := false
		for e: Dictionary in fd.enemies:
			var ec: Vector2i = e.cell
			if absi(ec.x - c.x) + absi(ec.y - c.y) <= 2:
				near = true
				break
		if near:
			continue
		var roll := roll_enemy(rng, pool, int(def.rank_min), int(def.rank_max))
		var e := make_enemy(c, String(roll.species_id), String(roll.kind), int(roll.rank))
		e["facing"] = rng.randi_range(0, 3)
		# Dormido: tirado en el piso como un montón de huesos hasta que el
		# equipo se acerca (o lo pisa).
		e["dormant"] = rng.randf() < float(DataRegistry.get_species(String(roll.species_id)).dormant_chance)
		e["variant_seed"] = rng.randi()
		fd.enemies.append(e)
		placed += 1

## Elección ponderada por peso_aparicion entre los objetos DISPONIBLES.
static func roll_item(rng: RandomNumberGenerator, item_pool: Array[String]) -> String:
	var total := 0
	for id in item_pool:
		total += int(DataRegistry.get_item(id).get("peso_aparicion", 0))
	if total <= 0:
		return ""
	var pick := rng.randi_range(1, total)
	for id in item_pool:
		pick -= int(DataRegistry.get_item(id).get("peso_aparicion", 0))
		if pick <= 0:
			return id
	return item_pool[item_pool.size() - 1]

static func _place_items(fd: FloorData, rng: RandomNumberGenerator, count: int, item_pool: Array[String], blocked: Dictionary) -> void:
	if item_pool.is_empty():
		return
	var candidates: Array[Vector2i] = []
	for i in range(1, fd.rooms.size()):
		var r := fd.rooms[i]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var c := Vector2i(x, y)
				if not blocked.has(c) and fd.enemy_at(c).is_empty():
					candidates.append(c)
	_shuffle(candidates, rng)
	for i in mini(count, candidates.size()):
		var id := roll_item(rng, item_pool)
		if id != "":
			fd.items.append({"cell": candidates[i], "item_id": id})

static func _place_decor(fd: FloorData, rng: RandomNumberGenerator, per_room: float, blocked: Dictionary) -> void:
	for r in fd.rooms:
		var n := int(per_room) + (1 if rng.randf() < fmod(per_room, 1.0) else 0)
		var corners: Array[Vector2i] = [r.position, Vector2i(r.end.x - 1, r.position.y), Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]
		var offsets: Array[Vector2] = [Vector2(0.5, 0.5), Vector2(1.5, 0.5), Vector2(0.5, 1.5), Vector2(1.5, 1.5)]
		var order: Array[int] = [0, 1, 2, 3]
		_shuffle(order, rng)
		for k in mini(n, 4):
			var i := order[k]
			var c := corners[i]
			if blocked.has(c) or c == fd.start_cell:
				continue
			fd.props.append({
				"prop": PROPS[rng.randi_range(0, PROPS.size() - 1)],
				"pos": Vector3(c.x * 2.0 + offsets[i].x, 0, c.y * 2.0 + offsets[i].y),
				"rot": rng.randf_range(-45.0, 45.0),
			})
		# Salas grandes: un par de columnas pegadas a esquinas internas.
		if r.size.x >= 5 and r.size.y >= 5 and rng.randf() < 0.6:
			fd.pillars.append(Vector3((r.position.x + 1) * 2.0 + 0.6, 0, (r.position.y + 1) * 2.0 + 0.6))
			fd.pillars.append(Vector3((r.end.x - 2) * 2.0 + 1.4, 0, (r.end.y - 2) * 2.0 + 1.4))

## Antorchas en las paredes, separadas al menos `every` pasos (Manhattan).
## Primero una en la sala de inicio y otra en la del jefe (que el comienzo y
## el final se vean), después el resto.
static func _place_torches(fd: FloorData, rng: RandomNumberGenerator, every: int) -> void:
	var start_room := fd.rooms[0] if not fd.rooms.is_empty() else Rect2i()
	var groups: Array = [[], [], []]
	for c in fd.floor_cells():
		for d in DIRS.size():
			if not fd.is_wall(c + DIRS[d]):
				continue
			var g := 2
			if start_room.has_point(c):
				g = 0
			elif fd.boss_room.has_point(c):
				g = 1
			(groups[g] as Array).append({"cell": c, "dir": d})
	for g: Array in groups:
		_shuffle(g, rng)
		for t: Dictionary in g:
			var c: Vector2i = t.cell
			var ok := true
			for other: Dictionary in fd.torches:
				var oc: Vector2i = other.cell
				if absi(oc.x - c.x) + absi(oc.y - c.y) < every:
					ok = false
					break
			if ok:
				fd.torches.append(t)

## Fisher-Yates con la rng del piso (determinista; Array.shuffle() no lo es).
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
