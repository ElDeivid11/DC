extends TestCase
## GameSettings.ui_factor: el píxel de arte del kit (2 px de UI) mide siempre
## un número entero de píxeles de pantalla.

func test_tabla_de_factores() -> void:
	# [ventana, escala, factor esperado]
	var cases: Array = [
		[Vector2(1280, 720), 0.8, 1.0], [Vector2(1280, 720), 1.0, 1.0], [Vector2(1280, 720), 1.25, 1.5],
		[Vector2(1920, 1080), 0.8, 0.6667], [Vector2(1920, 1080), 1.0, 1.0], [Vector2(1920, 1080), 1.25, 1.3333],
		[Vector2(1366, 768), 0.8, 0.9375], [Vector2(1366, 768), 1.0, 0.9375], [Vector2(1366, 768), 1.25, 1.4063],
	]
	for c: Array in cases:
		var win: Vector2 = c[0]
		var f := GameSettings.ui_factor(win, float(c[1]))
		check(absf(f - float(c[2])) < 0.001, "%s × %s → %s (se esperaba %s)" % [win, c[1], f, c[2]])
		var stretch := minf(win.x / 1280.0, win.y / 720.0)
		var art := f * stretch * UIStyle.PIXEL_SCALE
		check(absf(art - roundf(art)) < 0.001, "píxel de arte entero en %s × %s" % [win, c[1]])

func test_paso_mas_cercano() -> void:
	eq(GameSettings.nearest_step(1.5), 1.25, "1,5 → Grande")
	eq(GameSettings.nearest_step(0.85), 0.8, "0,85 → Compacta")
	eq(GameSettings.nearest_step(1.0), 1.0, "1,0 → Normal")
	eq(GameSettings.nearest_step(1.1), 1.0, "1,1 → Normal")
