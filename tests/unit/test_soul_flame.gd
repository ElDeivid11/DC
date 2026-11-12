extends TestCase
## El alma a la vista: cada enemigo guarda un alma concreta desde que
## aparece, su llama tiene el color de la afinidad de esa alma y está
## dibujada en la hoja de cada especie (canal de alma de la máscara de brillo).

func test_cada_afinidad_tiene_su_llama() -> void:
	var seen := {}
	for af in DataRegistry.affinity_ids():
		var hex := String(DataRegistry.get_affinity(af).get("llama", ""))
		check(Color.html_is_valid(hex), "%s: color de llama" % af)
		check(not seen.has(hex), "%s: su llama no se repite" % af)
		seen[hex] = true

func test_cada_alma_tiene_color() -> void:
	for sid: String in DataRegistry.souls.keys():
		check(DataRegistry.soul_flame_color(sid) != Color.BLACK, "%s: llama con color" % sid)
	eq(DataRegistry.soul_flame_color(""), Color.BLACK, "sin alma, apagada")

func test_los_enemigos_guardan_un_alma_de_su_especie() -> void:
	for n in [1, 3, 5]:
		var fd := FloorGenerator.generate(n, 21, [])
		for e: Dictionary in fd.enemies:
			var sid := String(e.get("soul_id", ""))
			check(sid != "", "piso %d: %s guarda un alma" % [n, e.display_name])
			if e.kind != RunRules.BOSS:
				check((DataRegistry.get_species(String(e.species_id)).almas as Array).has(sid), "piso %d: el alma es de su especie" % n)

func test_si_la_suelta_es_la_que_se_le_ve() -> void:
	GameState.new_run(3, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	eq(GameState.roll_soul("esqueleto_esbirro", 9, RunRules.NORMAL, rng, true, "esbirro_terco"), "esbirro_terco", "suelta la que guardaba")
	var any := GameState.roll_soul("esqueleto_esbirro", 9, RunRules.NORMAL, rng, true)
	check((DataRegistry.get_species("esqueleto_esbirro").almas as Array).has(any), "sin alma fija, una de su especie")

func test_la_llama_esta_en_las_hojas() -> void:
	# Canal de alma = 64 en la máscara de brillo (ojos 255, espíritu 128).
	for id in DataRegistry.species_ids():
		var sp := DataRegistry.get_species(id)
		if not sp.has("visual") or not (sp.visual as Dictionary).has("sprite"):
			continue
		var data := EnemySprite.load_sheet(String(sp.visual.sprite))
		check(data.get("glow") != null, "%s: máscara de brillo" % id)
		if data.get("glow") == null:
			continue
		var img := (data.glow as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		var soul := 0
		for y in img.get_height():
			for x in img.get_width():
				var v := roundi(img.get_pixel(x, y).r * 255.0)
				if v > 40 and v < 100:
					soul += 1
		check(soul > 200, "%s: la llama del alma está dibujada (%d px)" % [id, soul])
