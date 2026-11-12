extends Node
## Corre todos los tests unitarios de tests/unit/ (scripts que extienden
## TestCase, funciones test_*). Sale con código 0 si todo pasó, 1 si no.
##   godot --headless --path . res://tests/TestRunner.tscn
##
## Cada test corre aislado: antes se guarda el estado de MetaState/GameState
## y la ruta de guardado, y después se restauran (los tests de guardado usan
## user://test_save.json, nunca el guardado real).

const UNIT_DIR := "res://tests/unit"

func _ready() -> void:
	# Si un test revienta a mitad de camino, que no quede colgado.
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		printerr("TEST FAIL: timeout del runner (¿un test lanzó un error?)")
		get_tree().quit(1)
	)
	var total := 0
	var failed: Array[String] = []
	SaveSystem.log_problems = false
	var files := DirAccess.get_files_at(UNIT_DIR)
	for f in files:
		if not f.ends_with(".gd"):
			continue
		var script: GDScript = load(UNIT_DIR.path_join(f))
		if script == null or not script.can_instantiate():
			failed.append("%s no compila" % f)
			continue
		var suite: TestCase = script.new()
		for method in suite.get_method_list():
			var mname: String = method.name
			if not mname.begins_with("test_"):
				continue
			total += 1
			suite.current = "%s::%s" % [f.get_basename(), mname]
			var meta_backup: Dictionary = MetaState.to_dict()
			var save_path_backup: String = SaveSystem.save_path
			SaveSystem.save_path = "user://test_save.json"
			var before := suite.failures.size()
			suite.call(mname)
			SaveSystem.save_path = save_path_backup
			SaveSystem.read_only = false
			MetaState.from_dict(meta_backup)
			GameState.active = false
			GameState.ended = false
			if suite.failures.size() > before:
				for i in range(before, suite.failures.size()):
					failed.append(suite.failures[i])
	for msg in failed:
		printerr("TEST FAIL: ", msg)
	print("tests: %d ejecutados, %d fallos" % [total, failed.size()])
	get_tree().quit(1 if not failed.is_empty() or total == 0 else 0)
