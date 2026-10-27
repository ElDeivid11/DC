extends TestCase
## Integridad del contenido de almas (para que agregar almas, pactos o
## especies mal falle acá y no en una run): que todo se pueda conseguir, que
## los niveles de afinidad y los pactos sean alcanzables con los espacios que
## hay, que cada efecto y cada activa tengan su texto, y que existan los topes.

## Almas que pueden salir en una run: las que sueltan las especies que
## aparecen en los pisos, las de los jefes y las que ofrecen sus elecciones.
func _obtainable() -> Dictionary:
	var out := {}
	for sp_id in DataRegistry.species_ids():
		for sid: Variant in DataRegistry.get_species(sp_id).almas:
			out[String(sid)] = true
	for n in range(1, DataRegistry.floor_count() + 1):
		out[String((DataRegistry.get_floor(n).boss as Dictionary).soul_id)] = true
	return out

## Las que se pueden tener ANTES del último jefe (su alma es el trofeo final:
## la run termina ahí).
func _usable() -> Dictionary:
	var out := _obtainable()
	out.erase(String((DataRegistry.get_floor(DataRegistry.floor_count()).boss as Dictionary).soul_id))
	return out

func _max_capacity() -> int:
	return DataRegistry.bal_i("soul_capacity", 3) + RunRules.level_soul_slots(RunRules.max_level())

func test_cada_alma_se_puede_conseguir() -> void:
	var ok := _obtainable()
	for sid: String in DataRegistry.souls.keys():
		check(ok.has(sid), "%s: alguna especie activa o algún jefe la suelta" % sid)
		check(not (DataRegistry.get_soul(sid).afinidades as Array).is_empty(), "%s: tiene afinidad" % sid)

func test_especie_y_alma_coinciden() -> void:
	for sp_id: String in DataRegistry.species.keys():
		for sid: Variant in DataRegistry.get_species(sp_id).almas:
			eq(String(DataRegistry.get_soul(String(sid)).species), sp_id, "%s figura en %s y dice ser de esa especie" % [sid, sp_id])
	for sp_id in DataRegistry.species_ids():
		var sp := DataRegistry.get_species(sp_id)
		if String(sp.tier) != "jefe":
			check((sp.almas as Array).size() >= 2, "%s: al menos dos almas para elegir" % sp_id)

func test_afinidades_alcanzables() -> void:
	var usable := _usable()
	var cap := _max_capacity()
	for af in DataRegistry.affinity_ids():
		var levels: Array = DataRegistry.get_affinity(af).niveles
		var top := int((levels[levels.size() - 1] as Dictionary).cantidad)
		var n := 0
		for sid: String in usable.keys():
			if (DataRegistry.get_soul(sid).afinidades as Array).has(af):
				n += 1
		check(n >= top, "%s: hay %d almas para su último nivel (pide %d)" % [af, n, top])
		check(top <= cap, "%s: su último nivel (%d) entra en los espacios máximos (%d)" % [af, top, cap])
		check(int((levels[0] as Dictionary).cantidad) <= DataRegistry.bal_i("soul_capacity", 3), "%s: el primer nivel entra con los espacios del principio" % af)

func test_pactos_alcanzables() -> void:
	var usable := _usable()
	var in_pact := {}
	for pid: String in DataRegistry.pacts.keys():
		var pair: Array = DataRegistry.get_pact(pid).almas
		for sid: Variant in pair:
			check(usable.has(String(sid)), "pacto %s: %s se consigue antes del último jefe" % [pid, sid])
			in_pact[String(sid)] = true
		check(not (DataRegistry.get_pact(pid).efectos as Array).is_empty(), "pacto %s: tiene efecto" % pid)
	# Al menos la mitad de las almas entra en algún pacto.
	check(in_pact.size() * 2 >= DataRegistry.souls.size(), "%d de %d almas en algún pacto" % [in_pact.size(), DataRegistry.souls.size()])

func test_textos_de_efectos_y_activas() -> void:
	for type in DataRegistry.SOUL_EFFECTS:
		check(DataRegistry.has_text("effect." + type), "effect.%s tiene texto" % type)
	for tipo: String in DataRegistry.ACTIVE_TYPES.keys():
		check(DataRegistry.has_text("active." + tipo), "active.%s tiene texto" % tipo)
		# Y su descripción no sale vacía.
		var a := {"tipo": tipo, "poder": 1.0, "recarga": 2, "golpes": 2, "sangrado": 2, "turnos": 1, "cura": 0.5, "marca": 0.5, "debilita": 0.3, "umbral": 0.3, "mult": 2.0}
		check(SoulEffects.active_text(a) != "", "active.%s se describe" % tipo)

func test_topes_definidos() -> void:
	for name: String in ["sangrado", "robo_de_vida", "robo_de_vida_sangrado", "critico_mult", "escudo_pct_hp", "marca", "debilita", "aturdir_turnos"]:
		check(DataRegistry.bal("combat.topes." + name) != null, "combat.topes.%s en balance.json" % name)
	check(DataRegistry.bal_i("almas.recarga_minima", 0) >= 2, "recarga mínima de 2 o más (si no, Atacar sobra)")
