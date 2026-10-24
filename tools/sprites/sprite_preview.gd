extends Node3D
## Vista previa de las hojas de sprites de enemigos en el juego (EnemySprite
## con su shader, luz de antorcha y niebla): una fila por especie, mirando a
## la cámara, a la derecha, de espaldas y a la izquierda. Sirve para revisar
## una hoja nueva (también las del arte definitivo) sin jugar.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     res://tools/sprites/sprite_preview.tscn -- --out=/tmp/sprites.png [--role=walk] [--frames=40]

const FACINGS: Array[float] = [0.0, 90.0, 180.0, -90.0]
const SPACING := 1.6
const ROW_DEPTH := 2.2

var _out := "user://sprite_preview.png"
var _role := "idle"
var _frames := 30

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--role="):
			_role = arg.substr(7)
		elif arg.begins_with("--frames="):
			_frames = int(arg.substr(9))
	FloorBuilder.ensure_psx_shader_globals()
	FloorBuilder.set_fog(30.0, 60.0)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.13, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.22, 0.24)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var ids: Array[String] = []
	for id in DataRegistry.species_ids():
		var sp := DataRegistry.get_species(id)
		if sp.has("visual") and (sp.visual as Dictionary).has("sprite"):
			ids.append(id)
	var width := (FACINGS.size() - 1) * SPACING
	for r in ids.size():
		var sp := DataRegistry.get_species(ids[r])
		for c in FACINGS.size():
			var s := EnemySprite.new()
			s.setup(sp.visual, Color.WHITE, (sp.visual as Dictionary).get("eye_color", Color.WHITE), r * 10 + c)
			s.position = Vector3(c * SPACING - width / 2.0, 0.0, -r * ROW_DEPTH)
			s.rotation_degrees.y = FACINGS[c]
			add_child(s)
			s.play_role(_role if s.has_role(_role) else "idle")
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.6, 5.5), Vector3(0, 0.6, -ids.size() * ROW_DEPTH / 2.0))
	var torch := FlickerLight.make(Color(1.0, 0.78, 0.5), 2.5, 14.0, 1.0, 0.0, 1.0)
	torch.position = Vector3(-1.0, 2.5, 4.0)
	add_child(torch)
	_capture.call_deferred()

func _capture() -> void:
	for _i in _frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("vista previa: ", _out)
	get_tree().quit()
