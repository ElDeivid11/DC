extends Node
## Herramienta de desarrollo: abre una escena, espera N frames y guarda una
## captura PNG. Necesita un display real o virtual (Xvfb), no --headless:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     res://tools/screenshot.tscn -- --scene=res://scenes/Hub.tscn --out=/tmp/hub.png --frames=60
## Opcional:
##   --call=metodo[:arg]  se llama sobre la escena a mitad de la espera
##   --screen=ClaseUI     abre esa pantalla (class_name) encima de la escena
##                        (si tiene `run` y la escena es la run, se la pasa)
##   --tab=N              con --screen: abre la pestaña N (Estado)
##   --demo               carga datos de ejemplo en MetaState (no se guardan)
##   --run                arranca una run de ejemplo (objetos, un alma, nivel 3)
##   --ui-scale=1.5       escala de UI (como en Opciones)
##   --enemies=sprite|model  enemigos en pixel art o modelo 3D (como en Opciones)
##   --summary            deja terminada una run de ejemplo (para RunSummary.tscn)
##   --test-room          la run arranca en la sala de pruebas (un enemigo de cada)
##   --floor=N            la run arranca en el piso N (semilla fija: revisar biomas)
##   --combat=metodo[:a,b][;otro]  casi al final, llama eso sobre el combate abierto
##                        (p. ej. _show_abilities, _show_items, debug_lose,
##                        _damage_member:1,99, _choose_replacement:bjorn)
##   --face-chest         pone al jugador frente a un cofre (placa de interacción)
##   --message=texto      casi al final, muestra ese mensaje en el HUD
##   --party3             suma un tercer héroe (copia de Elena) a la run de
##                        ejemplo: para revisar el combate con tres tarjetas

var _scene_path := "res://scenes/ui/UIGallery.tscn"
var _out := "user://screenshot.png"
var _frames := 30
var _call := ""
var _screen := ""
var _tab := -1
var _combat_call := ""
var _message := ""
var _face_chest := false
var _scene: Node

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			_scene_path = arg.substr(8)
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--frames="):
			_frames = int(arg.substr(9))
		elif arg.begins_with("--call="):
			_call = arg.substr(7)
		elif arg.begins_with("--screen="):
			_screen = arg.substr(9)
		elif arg.begins_with("--tab="):
			_tab = int(arg.substr(6))
		elif arg.begins_with("--combat="):
			_combat_call = arg.substr(9)
		elif arg.begins_with("--message="):
			_message = arg.substr(10)
		elif arg == "--face-chest":
			_face_chest = true
		elif arg == "--party3" and GameState.party.size() >= 2:
			var third: Dictionary = (GameState.party[1] as Dictionary).duplicate(true)
			third["id"] = "tercero"
			third["name"] = "Ilsa"
			GameState.party.append(third)
		elif arg == "--demo":
			_demo_meta()
		elif arg == "--run":
			_demo_run()
		elif arg == "--summary":
			_demo_summary()
		elif arg == "--test-room":
			GameState.new_run(1, true)
		elif arg.begins_with("--floor="):
			GameState.new_run(4242, false)
			GameState.floor_n = int(arg.substr(8))
		elif arg.begins_with("--ui-scale="):
			MetaState.settings["ui_scale"] = float(arg.substr(11))
			GameSettings.apply(MetaState.settings, get_tree())
		elif arg.begins_with("--enemies="):
			MetaState.settings["enemy_style"] = arg.substr(10)
	var packed: PackedScene = load(_scene_path)
	_scene = packed.instantiate()
	get_tree().root.add_child.call_deferred(_scene)
	_capture.call_deferred()

func _capture() -> void:
	for i in _frames:
		await get_tree().process_frame
		if i == int(_frames / 3.0) and _screen != "":
			for c: Dictionary in ProjectSettings.get_global_class_list():
				if c["class"] == _screen:
					var screen: Node = (load(String(c["path"])) as GDScript).new()
					if "run" in screen and _scene is RunController:
						screen.set("run", _scene)
					var layer := CanvasLayer.new()
					layer.layer = 20
					get_tree().root.add_child(layer)
					layer.add_child(screen)
					if _tab >= 0 and screen.get("tabs") is UITabs:
						(screen.get("tabs") as UITabs).select(_tab)
		if i == int(_frames / 2.0) and _call != "":
			var parts := _call.split(":")
			if _scene.has_method(parts[0]):
				if parts.size() > 1:
					# "true"/"false" y los enteros llegan como texto: se convierten.
					var arg: Variant = parts[1]
					if parts[1] == "true" or parts[1] == "false":
						arg = parts[1] == "true"
					elif parts[1].is_valid_int():
						arg = int(parts[1])
					_scene.call(parts[0], arg)
				else:
					_scene.call(parts[0])
		if i == int(_frames / 2.0) - 1 and _face_chest:
			_put_in_front_of_chest()
		if i == _frames - 6:
			if _message != "":
				EventBus.hud_message.emit(_message)
			if _combat_call != "":
				_call_on_combat()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out)
	print("captura: ", _out, " (", error_string(err), ")")
	get_tree().quit()

## Llama métodos del combate abierto (RunController.combat), separados por
## ";". Los argumentos van separados por comas; los números pasan como int.
func _call_on_combat() -> void:
	var combat: Variant = _scene.get("combat")
	if not combat is Node:
		return
	for one in _combat_call.split(";"):
		var parts := one.split(":")
		var args: Array = []
		if parts.size() > 1:
			for a in parts[1].split(","):
				var v: Variant = a
				if a.is_valid_int():
					v = int(a)
				args.append(v)
		(combat as Node).callv(parts[0], args)

## Frente a un cofre: busca una celda libre al lado y mira hacia él.
func _put_in_front_of_chest() -> void:
	var chests: Variant = _scene.get("chest_nodes")
	if not chests is Dictionary:
		return
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for c: Variant in (chests as Dictionary).keys():
		var cell: Vector2i = c
		for i in dirs.size():
			var stand := cell - dirs[i]
			if not bool(_scene.call("is_wall", stand)) and not bool(_scene.call("get_enemy_at", stand)):
				_scene.call("debug_teleport", "%d,%d,%d" % [stand.x, stand.y, i])
				return

func _demo_meta() -> void:
	MetaState.coins = 1240
	MetaState.upgrades = {"vitalidad": 3, "fuerza": 1, "botin": 2}
	MetaState.bestiary = {
		"esqueleto_esbirro": {"seen": true, "kills": 7, "first_kill_run": 1, "souls_taken": 1},
		"esqueleto_picaro": {"seen": true, "kills": 3, "first_kill_run": 2, "souls_taken": 0},
		"esqueleto_guardian": {"seen": true, "kills": 0, "first_kill_run": 0, "souls_taken": 0},
	}
	MetaState.progress["kills_by_species"] = {"esqueleto_esbirro": 7, "esqueleto_picaro": 3}
	MetaState.progress["best_floor"] = 2
	MetaState.progress["flee_total"] = 1
	MetaState.unlocked = {}
	MetaState.stats = MetaState.default_stats()
	MetaState.stats.merge({"runs": 4, "deaths": 3, "retreats": 1, "total_kills": 10, "best_floor": 2, "total_time_sec": 3720.0, "coins_earned_total": 1600,
		"last_run": {"outcome": "muerte", "floor": 2, "kills": 6, "coins": 86, "cause": "Esqueleto arquero", "time_sec": 912.0}}, true)

func _demo_run() -> void:
	GameState.new_run(777, false)
	GameState.inventory.append_array(["venda", "antorcha_vieja", "talisman_hueso"])
	GameState.add_soul("bjorn", DataRegistry.make_soul("esqueleto_picaro", 8, "Esqueleto arquero"))
	GameState.party[1]["hp"] = 9
	GameState.add_coins(37, "kills")
	# Nivel 3 para los dos (y algo de EXP); Bjorn ya repartió algunos puntos.
	GameState.add_xp(RunRules.xp_to_next(1) + RunRules.xp_to_next(2) + 10)
	GameState.apply_points(GameState.party[0], {"vit": 2, "atq": 2, "def": 1})

func _demo_summary() -> void:
	SaveSystem.save_path = "user://screenshot_save.json" # no tocar el guardado real
	_demo_meta()
	_demo_run()
	GameState.max_floor = 3
	GameState.floor_n = 3
	GameState.elapsed_sec = 1452.0
	GameState.kills_by_species = {"esqueleto_esbirro": 4, "esqueleto_picaro": 2, "esqueleto_guardian": 1}
	GameState.kills_total = 7
	GameState.coin_breakdown = {"kills": 42, "boss": 25, "chests": 18}
	GameState.bosses_defeated = [1]
	GameState.end_run("muerte", "Esqueleto guardián")
