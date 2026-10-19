extends Node
## Herramienta de desarrollo: abre una escena, espera N frames y guarda una
## captura PNG. Necesita un display real o virtual (Xvfb), no --headless:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     res://tools/screenshot.tscn -- --scene=res://scenes/Hub.tscn --out=/tmp/hub.png --frames=60
## Opcional:
##   --call=metodo[:arg]  se llama sobre la escena a mitad de la espera
##   --screen=ClaseUI     abre esa pantalla (class_name) encima de la escena
##   --demo               carga datos de ejemplo en MetaState (no se guardan)
##   --run                arranca una run de ejemplo (objetos y un alma)

var _scene_path := "res://scenes/ui/UIGallery.tscn"
var _out := "user://screenshot.png"
var _frames := 30
var _call := ""
var _screen := ""
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
		elif arg == "--demo":
			_demo_meta()
		elif arg == "--run":
			_demo_run()
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
					var layer := CanvasLayer.new()
					layer.layer = 20
					get_tree().root.add_child(layer)
					layer.add_child(screen)
		if i == int(_frames / 2.0) and _call != "":
			var parts := _call.split(":")
			if _scene.has_method(parts[0]):
				if parts.size() > 1:
					_scene.call(parts[0], parts[1])
				else:
					_scene.call(parts[0])
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out)
	print("captura: ", _out, " (", error_string(err), ")")
	get_tree().quit()

func _demo_meta() -> void:
	MetaState.coins = 1240
	MetaState.upgrades = {"vitalidad": 3, "fuerza": 1, "botin": 2}
	MetaState.bestiary = {
		"goblin": {"seen": true, "kills": 7, "first_kill_run": 1, "souls_taken": 1},
		"rata_cripta": {"seen": true, "kills": 3, "first_kill_run": 2, "souls_taken": 0},
		"goblin_archer": {"seen": true, "kills": 0, "first_kill_run": 0, "souls_taken": 0},
	}
	MetaState.progress["kills_by_species"] = {"goblin": 7, "rata_cripta": 3}
	MetaState.progress["best_floor"] = 2
	MetaState.progress["flee_total"] = 1
	MetaState.unlocked = {}
	MetaState.stats = MetaState.default_stats()
	MetaState.stats.merge({"runs": 4, "deaths": 3, "retreats": 1, "total_kills": 10, "best_floor": 2, "total_time_sec": 3720.0, "coins_earned_total": 1600,
		"last_run": {"outcome": "muerte", "floor": 2, "kills": 6, "coins": 86, "cause": "Goblin arquero", "time_sec": 912.0}}, true)

func _demo_run() -> void:
	GameState.new_run(777, false)
	GameState.inventory.append_array(["venda", "antorcha_vieja", "talisman_goblin"])
	GameState.add_soul("bjorn", DataRegistry.make_soul("goblin", 9, "Goblin explorador"))
	GameState.party[1]["hp"] = 9
	GameState.add_coins(37, "kills")
