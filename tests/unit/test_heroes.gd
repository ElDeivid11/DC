extends TestCase
## Héroes: apariencia (datos, valores por defecto, guardado) y retratos en
## pixel art armados por capas (HeroPortrait).

func test_cada_opcion_arma_un_retrato() -> void:
	var base := DataRegistry.default_look("bjorn")
	for key in DataRegistry.look_keys():
		for i in DataRegistry.look_options(key):
			var look := base.duplicate()
			look[key] = i
			var img := HeroPortrait.image(look)
			eq(img.get_size(), Vector2i(HeroPortrait.SIZE, HeroPortrait.SIZE), "%s=%d: 48x48" % [key, i])
			check(not img.is_invisible(), "%s=%d: el retrato no sale vacío" % [key, i])

func test_cambiar_una_parte_cambia_el_retrato() -> void:
	var base := DataRegistry.default_look("bjorn")
	# Sin tocado (bajo la capucha el pelo no se ve).
	base["tocado"] = 0
	var a := HeroPortrait.image(base).get_data()
	for key: String in ["cara", "pelo", "color_piel", "color_pelo", "ojos", "ropa", "color_ropa"]:
		var look := base.duplicate()
		look[key] = (int(base[key]) + 1) % DataRegistry.look_options(key)
		check(HeroPortrait.image(look).get_data() != a, "cambiar %s cambia el retrato" % key)
	# El color de capa se ve en la capucha.
	var hooded := base.duplicate()
	hooded["tocado"] = 1
	var h := HeroPortrait.image(hooded).get_data()
	hooded["color_capa"] = (int(hooded.color_capa) + 1) % DataRegistry.look_options("color_capa")
	check(HeroPortrait.image(hooded).get_data() != h, "cambiar color_capa cambia la capucha")

func test_bajo_la_capucha_no_se_ve_el_pelo() -> void:
	var look := DataRegistry.default_look("bjorn")
	look["tocado"] = 1
	var a := HeroPortrait.image(look).get_data()
	look["pelo"] = (int(look.pelo) + 1) % DataRegistry.look_options("pelo")
	eq(HeroPortrait.image(look).get_data(), a, "con capucha, cambiar el pelo no cambia nada")

func test_tamanos_enteros_o_recorte() -> void:
	var look := DataRegistry.default_look("bjorn")
	eq(HeroPortrait.texture(look, 96).get_size(), Vector2(96, 96), "96 = ×2")
	eq(HeroPortrait.texture(look, 192).get_size(), Vector2(192, 192), "192 = ×4")
	eq(HeroPortrait.texture(look, 64).get_size(), Vector2(48, 48), "64 entra ×1 (sin estirar)")
	eq(HeroPortrait.texture(look, 28).get_size(), Vector2(28, 28), "28: recorte de la cara")
	eq(HeroPortrait.texture(look, 44).get_size(), Vector2(44, 44), "44: recorte")

func test_apariencia_guardada_y_limites() -> void:
	MetaState.set_hero("bjorn", "  Ragnar  ", {"pelo": 999, "color_piel": -3, "barba": 1})
	eq(MetaState.hero_name("bjorn"), "Ragnar", "el nombre se guarda sin espacios")
	var look := MetaState.hero_look("bjorn")
	eq(int(look.pelo), DataRegistry.look_options("pelo") - 1, "índice alto: la última opción")
	eq(int(look.color_piel), 0, "índice negativo: la primera")
	eq(int(look.barba), 1, "lo elegido se respeta")
	eq(int(look.tocado), int(DataRegistry.default_look("bjorn").tocado), "lo no elegido sale de balance.json")
	var d := MetaState.to_dict()
	MetaState.reset()
	eq(MetaState.hero_name("bjorn"), "Bjorn", "sin guardar: el nombre de balance.json")
	MetaState.from_dict(d)
	eq(MetaState.hero_name("bjorn"), "Ragnar", "el nombre vuelve al cargar")
	MetaState.set_hero("bjorn", "", {})
	eq(MetaState.hero_name("bjorn"), "Bjorn", "nombre vacío: el de siempre")

func test_nombres_de_opciones() -> void:
	for key in DataRegistry.look_keys():
		check(DataRegistry.look_label(key) != key, "%s tiene nombre visible" % key)
		for i in DataRegistry.look_options(key):
			check(DataRegistry.look_value_name(key, i) != "", "%s=%d tiene nombre" % [key, i])
