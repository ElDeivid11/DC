extends Node
## Guarda/carga MetaState en user://save.json.
##
## - Escritura atómica: se escribe "save.json.tmp" y recién después se
##   renombra sobre "save.json" (un corte de luz a mitad de escritura no deja
##   el guardado a medias).
## - Antes de reemplazar, el guardado anterior se copia a "save.json.bak". Si
##   el principal está roto al cargar, se usa el .bak.
## - Cada archivo lleva "version". Al cargar uno viejo se migra paso a paso
##   (_migrate) hasta MetaState.SAVE_VERSION.
## - Autoguardado: al terminar la run (RunSummary) y al comprar mejoras.

const DEFAULT_PATH := "user://save.json"

var save_path := DEFAULT_PATH
## Último problema al guardar/cargar (vacío = todo bien). Se muestra en debug.
var last_error := ""
## Si el guardado es de una versión MÁS NUEVA que el juego, no se pisa.
var read_only := false
## Los tests provocan errores a propósito (guardado roto, versión futura):
## con esto en false no ensucian el log de verificación.
var log_problems := true

func _ready() -> void:
	load_meta()

func save_meta() -> bool:
	if read_only:
		last_error = "Guardado de una versión más nueva: no se sobrescribe."
		return false
	var data := {
		"version": MetaState.SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"meta": MetaState.to_dict(),
	}
	return write_json_atomic(save_path, data)

## Carga el guardado (o el .bak si el principal está roto). Sin guardado,
## MetaState queda con valores por defecto. Devuelve true si cargó algo.
func load_meta() -> bool:
	last_error = ""
	read_only = false
	for path: String in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var data := read_json(path)
		if data.is_empty():
			continue
		var migrated := migrate(data)
		if migrated.is_empty():
			continue
		MetaState.from_dict(migrated.meta)
		if path != save_path:
			_warn("guardado principal dañado, se cargó la copia .bak")
		return true
	MetaState.reset()
	return false

## Borra el guardado (y su copia) y vuelve a los valores por defecto.
func reset_save() -> void:
	for path: String in [save_path, save_path + ".bak", save_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	read_only = false
	MetaState.reset()
	save_meta()

# --- Archivo ------------------------------------------------------------------

func write_json_atomic(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "No se pudo escribir %s (%s)" % [tmp, error_string(FileAccess.get_open_error())]
		_warn(last_error, true)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

	var abs_path := ProjectSettings.globalize_path(path)
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(abs_path, abs_path + ".bak")
	var err := DirAccess.rename_absolute(abs_tmp, abs_path)
	if err != OK:
		# Algunos sistemas no renombran encima de un archivo existente.
		DirAccess.remove_absolute(abs_path)
		err = DirAccess.rename_absolute(abs_tmp, abs_path)
	if err != OK:
		last_error = "No se pudo reemplazar %s (%s)" % [path, error_string(err)]
		_warn(last_error, true)
		return false
	last_error = ""
	return true

## Devuelve {} si el archivo no existe o no es JSON válido (con last_error).
func read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		last_error = "%s está vacío o no se puede leer" % path
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		last_error = "%s línea %d: %s" % [path, json.get_error_line() + 1, json.get_error_message()]
		_warn(last_error)
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		last_error = "%s: formato inesperado" % path
		return {}
	var d: Dictionary = json.data
	return d

# --- Migraciones --------------------------------------------------------------

## Lleva un guardado de cualquier versión anterior a la actual. Devuelve {}
## si es de una versión más nueva (y marca read_only para no pisarlo).
func migrate(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	var version := int(d.get("version", 0))
	if version > MetaState.SAVE_VERSION:
		last_error = "El guardado es de una versión más nueva (%d > %d)" % [version, MetaState.SAVE_VERSION]
		_warn(last_error)
		read_only = true
		return {}
	while version < MetaState.SAVE_VERSION:
		match version:
			0:
				d = _migrate_0_to_1(d)
			_:
				last_error = "No hay migración desde la versión %d" % version
				_warn(last_error, true)
				return {}
		version = int(d.version)
	if typeof(d.get("meta")) != TYPE_DICTIONARY:
		last_error = "Guardado sin bloque 'meta'"
		return {}
	return d

## v0 = formato sin "version" (todo el estado suelto en la raíz). Se envuelve
## en "meta". Sirve de plantilla para futuras migraciones.
func _migrate_0_to_1(d: Dictionary) -> Dictionary:
	if d.has("meta"):
		d["version"] = 1
		return d
	return {"version": 1, "saved_at": "", "meta": d}

func _warn(msg: String, is_error := false) -> void:
	if not log_problems:
		return
	if is_error:
		push_error("SaveSystem: " + msg)
	else:
		push_warning("SaveSystem: " + msg)
