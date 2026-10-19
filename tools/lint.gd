extends Node
## Carga TODOS los scripts y escenas propios del proyecto (no los addons ni
## los packs originales) para que Godot los compile/parsee. Con override.cfg
## (ver tools/verify.sh) cualquier warning de GDScript sale como SCRIPT ERROR
## en el log. También revisa que cada texto pedido con DataRegistry.t("...")
## exista en data/texts.json.

const ROOTS: Array[String] = ["res://autoload", "res://scripts", "res://scenes", "res://tests", "res://tools", "res://ui"]

var failures := 0

func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		printerr("TEST FAIL: timeout del lint")
		get_tree().quit(1)
	)
	var files: Array[String] = []
	for root in ROOTS:
		_collect(root, files)
	var self_path: String = (get_script() as Script).resource_path
	for path in files:
		if path == self_path:
			continue # recargar el script que está corriendo rompe su propia ejecución
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res == null:
			printerr("TEST FAIL: no se pudo cargar ", path)
			failures += 1
		elif res is GDScript and not (res as GDScript).can_instantiate() and not _is_static_only(path):
			printerr("TEST FAIL: script no instanciable ", path)
			failures += 1
	_check_text_keys(files)
	print("lint: %d archivos revisados, %d fallos" % [files.size(), failures])
	get_tree().quit(1 if failures > 0 else 0)

func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for f in dir.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".tres"):
			out.append(dir_path.path_join(f))

## Los scripts "abstractos" o solo-estáticos no tienen por qué instanciarse.
func _is_static_only(path: String) -> bool:
	var src := FileAccess.get_file_as_string(path)
	return src.contains("@abstract")

## Todo texto de UI pasa por DataRegistry.t("clave"): si la clave no existe en
## data/texts.json, se ve "[clave]" en pantalla. Esto lo detecta antes.
func _check_text_keys(files: Array[String]) -> void:
	var regex := RegEx.new()
	regex.compile("\\bt\\(\"([a-z][a-z0-9_.]*)\"")
	for path in files:
		if not path.ends_with(".gd"):
			continue
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if line.strip_edges().begins_with("#"):
				continue # los comentarios pueden mencionar t("...") de ejemplo
			for m in regex.search_all(line):
				var key := m.get_string(1)
				if not DataRegistry.has_text(key):
					printerr("TEST FAIL: texto '%s' usado en %s no existe en data/texts.json" % [key, path])
					failures += 1
