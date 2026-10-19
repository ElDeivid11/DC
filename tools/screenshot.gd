extends Node
## Herramienta de desarrollo: abre una escena, espera N frames y guarda una
## captura PNG. Necesita un display real o virtual (Xvfb), no --headless:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     res://tools/screenshot.tscn -- --scene=res://scenes/Hub.tscn --out=/tmp/hub.png --frames=60
## Opcional: --call=metodo (se llama sobre la escena antes de capturar).

var _scene_path := "res://scenes/ui/UIGallery.tscn"
var _out := "user://screenshot.png"
var _frames := 30
var _call := ""
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
	var packed: PackedScene = load(_scene_path)
	_scene = packed.instantiate()
	get_tree().root.add_child.call_deferred(_scene)
	_capture.call_deferred()

func _capture() -> void:
	for i in _frames:
		await get_tree().process_frame
		if i == int(_frames / 2.0) and _call != "" and _scene.has_method(_call):
			_scene.call(_call)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out)
	print("captura: ", _out, " (", error_string(err), ")")
	get_tree().quit()
