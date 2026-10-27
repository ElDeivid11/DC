class_name MapParchment
extends RefCounted
## El dibujo del mapa de mano (M): un pergamino con lo descubierto del piso a
## tinta, Norte arriba. FieldMap lo pega en su malla y la leyenda del HUD usa
## los mismos sellos. Solo lo visitado: el piso de las celdas recorridas va
## lavado, los muros que las tocan, rayados, y el borde de cada muro, en una
## línea de tinta. Los marcadores son sellos de 5×5 (el del jugador gira con
## el rumbo). Colores de UIStyle (tintas oscuras sobre vitela clara).

const SIZE := Vector2i(256, 192)
const MARGIN := 14
## Ventana en celdas: lo visitado (+1 de borde) entre MIN_CELLS y MAX_CELLS;
## en pisos grandes la ventana se centra en el jugador.
const MIN_CELLS := Vector2i(14, 10)
const MAX_CELLS := Vector2i(28, 20)
const MAX_CELL_PX := 16
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Sellos de 5×5 ("#" = tinta). El del jugador mira al Norte.
const STAMPS := {
	"player": ["..#..", "..#..", ".###.", ".###.", "#####"],
	"enemy": ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
	"boss": [".###.", "#####", "#.#.#", "#####", ".#.#."],
	"chest": [".....", ".###.", "#####", "##.##", "#####"],
	"item": ["..#..", ".###.", "#####", ".###.", "..#.."],
	"door": ["#####", "#.#.#", "#.#.#", "#.#.#", "#####"],
	"exit": ["....#", "...##", "..###", ".####", "#####"],
	"exit_open": ["....#", "...##", "..###", ".####", "#####"],
}
## Romanos y la N de la rosa de los vientos (3×5 y 4×5).
const GLYPHS := {
	"I": ["###", ".#.", ".#.", ".#.", "###"],
	"V": ["#.#", "#.#", "#.#", "#.#", ".#."],
	"X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
	"N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
}
## Vitela ya pintada por semilla (pintarla cuesta: se hace una vez por piso).
static var _paper_cache: Dictionary = {}

## Orden de la leyenda del HUD (sello, clave de texto).
const LEGEND: Array = [
	["player", "map.you"], ["enemy", "map.enemy"], ["boss", "map.boss"],
	["chest", "map.chest"], ["item", "map.item"], ["door", "map.door"],
	["exit", "map.exit"], ["exit_open", "map.exit_open"],
]

static func ink() -> Color:
	return UIStyle.BRONCE_OSC.lerp(UIStyle.TINTA, 0.35)

static func stamp_color(kind: String) -> Color:
	match kind:
		"player":
			return UIStyle.RUBRICA
		"enemy":
			return UIStyle.TINTA
		"boss":
			return UIStyle.SANGRE_OSC
		"chest", "item":
			return UIStyle.MONEDA_OSC
		"door", "exit":
			return UIStyle.HIERRO_OSC
		"exit_open":
			return UIStyle.BRASA_OSC
	return ink()

## El pergamino entero. markers: {Vector2i: tipo} (RunController.map_markers).
static func render(fd: FloorData, visited: Dictionary, cell: Vector2i, facing: int, markers: Dictionary, floor_n := 1, paper_seed := 0) -> Image:
	if not _paper_cache.has(paper_seed):
		var paper := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
		_paper(paper, paper_seed)
		_frame(paper)
		_paper_cache.clear()
		_paper_cache[paper_seed] = paper
	var img := Image.new()
	img.copy_from(_paper_cache[paper_seed] as Image)
	var view := window(visited, cell)
	var area := SIZE - Vector2i(MARGIN, MARGIN) * 2
	var px := clampi(mini(floori(float(area.x) / view.size.x), floori(float(area.y) / view.size.y)), 3, MAX_CELL_PX)
	var origin := Vector2i(MARGIN, MARGIN) + Vector2i((Vector2(area - view.size * px) / 2.0).floor())
	var wash := UIStyle.HUESO.lerp(UIStyle.CENIZA, 0.4)
	var hatch := UIStyle.HUESO.lerp(UIStyle.BRONCE_OSC, 0.45)
	var line := maxi(1, floori(px / 6.0))
	# Piso lavado y muros rayados.
	for y in range(view.position.y, view.end.y):
		for x in range(view.position.x, view.end.x):
			var c := Vector2i(x, y)
			var p := origin + (c - view.position) * px
			if visited.has(c) and not fd.is_wall(c):
				img.fill_rect(Rect2i(p, Vector2i(px, px)), wash)
			elif fd.is_wall(c) and _touches(visited, fd, c):
				for j in px:
					for i in px:
						if posmod(p.x + i - p.y - j, 3) == 0:
							img.set_pixel(p.x + i, p.y + j, hatch)
	# El borde de los muros, a tinta.
	for c: Vector2i in visited.keys():
		if fd.is_wall(c) or not view.has_point(c):
			continue
		var p := origin + (c - view.position) * px
		for d in DIRS:
			if not fd.is_wall(c + d):
				continue
			match d:
				Vector2i(0, -1):
					img.fill_rect(Rect2i(p.x, p.y, px, line), ink())
				Vector2i(0, 1):
					img.fill_rect(Rect2i(p.x, p.y + px - line, px, line), ink())
				Vector2i(-1, 0):
					img.fill_rect(Rect2i(p.x, p.y, line, px), ink())
				Vector2i(1, 0):
					img.fill_rect(Rect2i(p.x + px - line, p.y, line, px), ink())
	var scale := maxi(1, floori(px / 7.0))
	var inset := Vector2i.ONE * floori((px - 5 * scale) / 2.0)
	for c: Vector2i in markers.keys():
		var kind := String(markers[c])
		if view.has_point(c) and STAMPS.has(kind):
			_stamp(img, kind, origin + (c - view.position) * px + inset, scale)
	if view.has_point(cell):
		_stamp(img, "player", origin + (cell - view.position) * px + inset, scale, facing)
	_cartouche(img, UIFormat.roman(floor_n), Vector2i(floori(SIZE.x / 2.0), 1))
	_cartouche(img, "N", Vector2i(SIZE.x - MARGIN - 8, 1))
	return img

## Qué parte del piso entra: lo visitado (+1 de borde), entre MIN_CELLS y
## MAX_CELLS celdas; si no entra todo, centrada en el jugador.
static func window(visited: Dictionary, cell: Vector2i) -> Rect2i:
	var lo := cell
	var hi := cell
	for c: Vector2i in visited.keys():
		lo = lo.min(c)
		hi = hi.max(c)
	var box := Rect2i(lo - Vector2i.ONE, hi - lo + Vector2i(3, 3))
	var size := box.size.clamp(MIN_CELLS, MAX_CELLS)
	var pos := Vector2i.ZERO
	for axis in 2:
		if box.size[axis] <= MAX_CELLS[axis]:
			pos[axis] = box.position[axis] - floori((size[axis] - box.size[axis]) / 2.0)
		else:
			pos[axis] = clampi(cell[axis] - floori(size[axis] / 2.0), box.position[axis], box.end[axis] - size[axis])
	return Rect2i(pos, size)

## Un sello de la leyenda: el sello sobre una teja de vitela con filete, a
## escala entera.
static func stamp_chip(kind: String, scale := 2) -> Image:
	var img := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	img.fill(UIStyle.HUESO)
	for i in 9:
		for p: Vector2i in [Vector2i(i, 0), Vector2i(i, 8), Vector2i(0, i), Vector2i(8, i)]:
			img.set_pixelv(p, UIStyle.BRONCE_OSC)
	_stamp(img, kind, Vector2i(2, 2), 1)
	img.resize(9 * scale, 9 * scale, Image.INTERPOLATE_NEAREST)
	return img

static func _stamp(img: Image, kind: String, at: Vector2i, scale: int, turns := 0) -> void:
	var rows: Array = STAMPS[kind]
	var color := stamp_color(kind)
	for y in 5:
		for x in 5:
			# Giro de a 90° en sentido horario (0 N, 1 E, 2 S, 3 O).
			var sx := x
			var sy := y
			for _t in posmod(turns, 4):
				var tx := sy
				sy = 4 - sx
				sx = tx
			if String(rows[sy])[sx] != "#":
				continue
			img.fill_rect(Rect2i(at + Vector2i(x, y) * scale, Vector2i(scale, scale)), color)

## Vitela clara en tres tonos con vetas, y el borde quemado.
static func _paper(img: Image, paper_seed: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = paper_seed
	noise.frequency = 0.035
	var grain := RandomNumberGenerator.new()
	grain.seed = paper_seed
	var tones: Array[Color] = [UIStyle.HUESO, UIStyle.HUESO.lerp(UIStyle.CENIZA, 0.3), UIStyle.HUESO.lerp(UIStyle.CENIZA, 0.55)]
	for y in SIZE.y:
		for x in SIZE.x:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var t := clampi(int((n + grain.randf_range(-0.08, 0.08)) * 3.4) - 1, 0, 2)
			var c := tones[t]
			var edge := mini(mini(x, y), mini(SIZE.x - 1 - x, SIZE.y - 1 - y))
			var burn := float(edge) + n * 5.0
			if burn < 3.0:
				c = UIStyle.BRONCE_OSC
			elif burn < 5.5:
				c = UIStyle.BRONCE
			img.set_pixel(x, y, c)

## Doble filete a tinta alrededor del mapa.
static func _frame(img: Image) -> void:
	for inset: int in [6, 9]:
		var r := Rect2i(inset, inset, SIZE.x - inset * 2, SIZE.y - inset * 2)
		img.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, 1), ink())
		img.fill_rect(Rect2i(r.position.x, r.end.y - 1, r.size.x, 1), ink())
		img.fill_rect(Rect2i(r.position.x, r.position.y, 1, r.size.y), ink())
		img.fill_rect(Rect2i(r.end.x - 1, r.position.y, 1, r.size.y), ink())

## Cartela sobre el filete de arriba con texto de GLYPHS a ×2, centrada en x.
static func _cartouche(img: Image, text: String, top_center: Vector2i) -> void:
	var w := 0
	for ch in text:
		if GLYPHS.has(ch):
			w += ((GLYPHS[ch] as Array)[0] as String).length() * 2 + 2
	w = maxi(w - 2, 1)
	var box := Rect2i(top_center.x - floori(w / 2.0) - 4, top_center.y + 1, w + 8, 16)
	img.fill_rect(box, UIStyle.HUESO)
	img.fill_rect(Rect2i(box.position.x, box.position.y, box.size.x, 1), ink())
	img.fill_rect(Rect2i(box.position.x, box.end.y - 1, box.size.x, 1), ink())
	img.fill_rect(Rect2i(box.position.x, box.position.y, 1, box.size.y), ink())
	img.fill_rect(Rect2i(box.end.x - 1, box.position.y, 1, box.size.y), ink())
	var x := box.position.x + 4
	for ch in text:
		if not GLYPHS.has(ch):
			continue
		var rows: Array = GLYPHS[ch]
		for gy in rows.size():
			var row := String(rows[gy])
			for gx in row.length():
				if row[gx] == "#":
					img.fill_rect(Rect2i(x + gx * 2, box.position.y + 3 + gy * 2, 2, 2), UIStyle.RUBRICA_OSC if ch == "N" else ink())
		x += (rows[0] as String).length() * 2 + 2

static func _touches(visited: Dictionary, fd: FloorData, c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			if visited.has(n) and not fd.is_wall(n):
				return true
	return false
