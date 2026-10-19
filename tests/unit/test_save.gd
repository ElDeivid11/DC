extends TestCase
## SaveSystem: guardar → reiniciar → cargar, copia .bak y migraciones.
## TestRunner apunta SaveSystem.save_path a user://test_save.json.

func _clean() -> void:
	for p: String in [SaveSystem.save_path, SaveSystem.save_path + ".bak", SaveSystem.save_path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func _write_raw(text: String) -> void:
	var f := FileAccess.open(SaveSystem.save_path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func test_guardar_reiniciar_cargar() -> void:
	_clean()
	MetaState.reset()
	MetaState.coins = 123
	MetaState.upgrades = {"fuerza": 2}
	MetaState.unlocked = {"u_piso_3": true}
	MetaState.bestiary = {"esqueleto_esbirro": {"seen": true, "kills": 4, "first_kill_run": 1, "souls_taken": 1}}
	check(SaveSystem.save_meta(), "guardar debe funcionar: " + SaveSystem.last_error)
	MetaState.reset()
	eq(MetaState.coins, 0, "reset borra en memoria")
	check(SaveSystem.load_meta(), "cargar debe encontrar el guardado")
	eq(MetaState.coins, 123, "monedas")
	eq(MetaState.upgrade_level("fuerza"), 2, "nivel de mejora")
	check(MetaState.is_unlocked("u_piso_3"), "desbloqueo")
	eq(int(MetaState.bestiary_entry("esqueleto_esbirro").kills), 4, "bestiario")
	check(not FileAccess.file_exists(SaveSystem.save_path + ".tmp"), "no queda el .tmp")
	_clean()

func test_principal_roto_usa_bak() -> void:
	_clean()
	MetaState.reset()
	MetaState.coins = 10
	SaveSystem.save_meta()
	MetaState.coins = 20
	SaveSystem.save_meta() # el de 10 pasa a .bak
	check(FileAccess.file_exists(SaveSystem.save_path + ".bak"), "debe existir la copia .bak")
	_write_raw("{ esto no es json")
	MetaState.reset()
	check(SaveSystem.load_meta(), "debe recuperar desde .bak")
	eq(MetaState.coins, 10, "monedas del .bak")
	_clean()

func test_migracion_desde_v0() -> void:
	_clean()
	var migrated := SaveSystem.migrate({"coins": 50, "upgrades": {"vitalidad": 1}})
	eq(int(migrated.version), MetaState.SAVE_VERSION, "versión final")
	eq(int(migrated.meta.coins), 50, "datos conservados")
	_write_raw(JSON.stringify({"coins": 77, "upgrades": {"botin": 3}}))
	MetaState.reset()
	check(SaveSystem.load_meta(), "carga un guardado v0")
	eq(MetaState.coins, 77, "monedas v0")
	eq(MetaState.upgrade_level("botin"), 3, "mejoras v0")
	_clean()

func test_version_futura_no_se_pisa() -> void:
	_clean()
	_write_raw(JSON.stringify({"version": 99, "meta": {"coins": 5}}))
	SaveSystem.load_meta()
	check(SaveSystem.read_only, "queda en solo lectura")
	check(not SaveSystem.save_meta(), "no debe sobrescribir un guardado más nuevo")
	SaveSystem.read_only = false
	_clean()

func test_sin_guardado_valores_por_defecto() -> void:
	_clean()
	MetaState.coins = 999
	check(not SaveSystem.load_meta(), "no hay guardado")
	eq(MetaState.coins, 0, "valores por defecto")
