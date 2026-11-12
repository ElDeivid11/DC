extends TestCase
## MapParchment (el dibujo del mapa de mano): qué parte del piso entra, que
## solo se dibuje lo visitado y que el jugador quede marcado.

## La textura es de 8 bits por canal: se compara con tolerancia.
func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01

func _visit_all(fd: FloorData) -> Dictionary:
	var v := {}
	for c in fd.floor_cells():
		v[c] = true
	return v

func test_ventana_chica_al_principio() -> void:
	var cell := Vector2i(10, 10)
	var w := MapParchment.window({cell: true, cell + Vector2i(1, 0): true}, cell)
	eq(w.size, MapParchment.MIN_CELLS, "con poco visitado, la ventana mínima")
	check(w.has_point(cell), "el jugador entra")

func test_ventana_grande_sigue_al_jugador() -> void:
	var fd := FloorGenerator.generate(5, 3, [])
	var visited := _visit_all(fd)
	for c: Vector2i in [fd.start_cell, fd.exit_cell]:
		var w := MapParchment.window(visited, c)
		check(w.size.x <= MapParchment.MAX_CELLS.x and w.size.y <= MapParchment.MAX_CELLS.y, "no pasa del máximo")
		check(w.has_point(c), "el jugador %s entra en %s" % [c, w])

func test_dibuja_lo_visitado_y_al_jugador() -> void:
	var fd := FloorGenerator.test_room()
	var visited := _visit_all(fd)
	var cell := fd.start_cell
	var img := MapParchment.render(fd, visited, cell, 0, {}, 1, 7)
	eq(img.get_size(), MapParchment.SIZE, "tamaño de la textura")
	var player := 0
	var ink := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if _near(c, MapParchment.stamp_color("player")):
				player += 1
			elif _near(c, MapParchment.ink()):
				ink += 1
	check(player >= 9, "el jugador está marcado (%d px)" % player)
	check(ink > 200, "los muros van a tinta (%d px)" % ink)

func test_sin_visitar_no_hay_mapa() -> void:
	var fd := FloorGenerator.test_room()
	var full := MapParchment.render(fd, _visit_all(fd), fd.start_cell, 0, {}, 1, 7)
	var empty := MapParchment.render(fd, {}, fd.start_cell, 0, {}, 1, 7)
	var diff := 0
	for y in range(MapParchment.MARGIN, MapParchment.SIZE.y - MapParchment.MARGIN):
		for x in range(MapParchment.MARGIN, MapParchment.SIZE.x - MapParchment.MARGIN):
			if not full.get_pixel(x, y).is_equal_approx(empty.get_pixel(x, y)):
				diff += 1
	check(diff > 500, "lo visitado se dibuja (%d px distintos)" % diff)

func test_sellos_de_la_leyenda() -> void:
	for pair: Array in MapParchment.LEGEND:
		var kind := String(pair[0])
		check(MapParchment.STAMPS.has(kind), "%s tiene sello" % kind)
		check(DataRegistry.has_text(String(pair[1])), "%s tiene texto" % pair[1])
		eq(MapParchment.stamp_chip(kind).get_size(), Vector2i(18, 18), "teja de %s a ×2" % kind)
