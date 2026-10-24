extends TestCase
## Hojas de sprites de enemigos (EnemySprite): que cada especie con
## visual.sprite tenga una animación para cada papel de visual.anims, cuadros
## dentro de la hoja y direcciones válidas. Vale igual para las hojas de
## prueba y para las del arte definitivo (mismo formato).

const DIRS: Array[String] = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]

func _species_with_sheet() -> Array[String]:
	var out: Array[String] = []
	for id in DataRegistry.species_ids():
		var sp := DataRegistry.get_species(id)
		if sp.has("visual") and (sp.visual as Dictionary).has("sprite"):
			out.append(id)
	return out

func test_hay_hojas() -> void:
	check(not _species_with_sheet().is_empty(), "al menos una especie con hoja de sprites")

func test_hojas_completas() -> void:
	for id in _species_with_sheet():
		var visual: Dictionary = DataRegistry.get_species(id).visual
		var data := EnemySprite.load_sheet(String(visual.sprite))
		check(not data.is_empty() and data.sheet != null, "%s: la hoja carga" % id)
		if data.is_empty() or data.sheet == null:
			continue
		var m: Dictionary = data.meta
		var sheet: Texture2D = data.sheet
		var frame: Array = m.frame
		var columns := int(m.columns)
		var rows := floori(float(sheet.get_height()) / float(frame[1]))
		check(columns * int(frame[0]) <= sheet.get_width(), "%s: columnas dentro de la hoja" % id)
		var anims: Dictionary = m.anims
		for role: String in (visual.anims as Dictionary).keys():
			check(anims.has(role), "%s: falta la animación del papel '%s'" % [id, role])
		for name: String in anims.keys():
			var a: Dictionary = anims[name]
			check(float(a.get("fps", 0.0)) > 0.0, "%s/%s: fps > 0" % [id, name])
			var dirs: Dictionary = a.dirs
			check(dirs.has("s"), "%s/%s: tiene la dirección s (de frente)" % [id, name])
			for d: String in dirs.keys():
				check(d in DIRS, "%s/%s: dirección '%s' válida" % [id, name, d])
				var frames: Array = dirs[d]
				check(not frames.is_empty(), "%s/%s/%s: tiene cuadros" % [id, name, d])
				for f: Variant in frames:
					check(int(f) >= 0 and int(f) < columns * rows, "%s/%s/%s: cuadro %d dentro de la hoja" % [id, name, d, int(f)])

func test_papeles_en_el_sprite() -> void:
	for id in _species_with_sheet():
		var visual: Dictionary = DataRegistry.get_species(id).visual
		var s := EnemySprite.new()
		s.setup(visual, Color.WHITE, Color.WHITE, 1)
		for role: String in (visual.anims as Dictionary).keys():
			if role != "death":
				check(s.has_role(role) and s.play_role(role) > 0.0, "%s: el sprite reproduce '%s'" % [id, role])
		s.play_role("death", "")
		check(s.is_dead(), "%s: después de death queda muerto" % id)
		s.free()
