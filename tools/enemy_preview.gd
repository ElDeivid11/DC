extends Node3D
## Herramienta de desarrollo: todos los enemigos activos en fila, de frente
## (adelante) y de perfil (atrás), sin niebla ni pixelado, para revisar
## modelos, proporciones, armas y animaciones. Con tools/screenshot.tscn:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     res://tools/screenshot.tscn -- --scene=res://tools/enemy_preview.tscn \
##     --out=/tmp/enemigos.png --frames=40 [--preview-role=attack] [--preview-at=0.4] \
##     [--preview-cam=lejos|cerca|cara|arriba] [--preview-only=esqueleto_picaro]
## --preview-role: papel que hacen todos (idle, combat, walk, attack, hit,
##   death, spawn, dormant, ability, taunt). --preview-at: congela ese papel
##   en esa fracción del clip (0..1); sin él, se mueve. --preview-cam: lejos
##   (las dos filas, con las líneas de 1/2/3 m), cerca (fila de frente, a la
##   altura de los ojos del equipo), cara (primer plano del cráneo del
##   primero) o arriba (picado). --preview-only: una
##   sola especie, de frente y de perfil lado a lado (para mirar armas y manos).
## También con --call=show_role:attack (todos a la vez, en el cuadro 0).

const SPACING := 1.7

var visuals: Array[EnemyVisual] = []
var _role := "idle"
var _at := -1.0
var _cam_mode := "lejos"
var _only := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preview-role="):
			_role = a.substr(15)
		elif a.begins_with("--preview-at="):
			_at = clampf(float(a.substr(13)), 0.0, 1.0)
		elif a.begins_with("--preview-cam="):
			_cam_mode = a.substr(14)
		elif a.begins_with("--preview-only="):
			_only = a.substr(15)
	FloorBuilder.ensure_psx_shader_globals()
	FloorBuilder.set_fog_color(Color(0.18, 0.18, 0.2))
	FloorBuilder.set_fog(80.0, 120.0)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.18, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	add_child(sun)
	var ids := DataRegistry.species_ids()
	if _only != "":
		ids = [_only]
	var width := (ids.size() - 1) * SPACING
	for i in ids.size():
		var sp := DataRegistry.get_species(ids[i])
		if not sp.has("visual"):
			continue
		var visual: Dictionary = sp.visual
		for row in 2:
			var v := EnemyVisual.new()
			v.setup(visual, Color.WHITE, visual.eye_color, i)
			if _only != "":
				# Una sola especie: de frente y de perfil, lado a lado.
				v.position = Vector3(-0.75 + row * 1.5, 0, 0)
			else:
				v.position = Vector3(i * SPACING - width / 2.0, 0, -row * 2.2)
			v.rotation_degrees.y = 0.0 if row == 0 else 90.0 # de frente / perfil
			add_child(v)
			_play(v)
			visuals.append(v)
	if _only != "":
		width = 1.6
	# Referencias: techo normal (2 m), techo de la sala del jefe (3 m) y ojos
	# del equipo (1 m).
	for h: float in [1.0, FloorBuilder.WALL_HEIGHT, DataRegistry.bal_f("render.boss_room_height", 3.0)]:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width + SPACING, 0.015, 0.015)
		bar.mesh = box
		bar.position = Vector3(0, h, 0.6)
		bar.material_override = FloorBuilder.make_glow_material(Color(1, 0.3, 0.3) if h > 1.5 else Color(0.3, 1, 0.3))
		add_child(bar)
	var cam := Camera3D.new()
	match _cam_mode:
		"cerca":
			cam.fov = 34.0
			cam.position = Vector3(0, 1.0, 1.6 + width * 1.15)
			cam.rotation_degrees.x = 0.0
		"cara":
			# Primer plano de la cabeza del primero (ojos y cráneo).
			var head := Vector3(0, 1.55, 0)
			if not visuals.is_empty() and visuals[0].skeleton:
				var sk := visuals[0].skeleton
				var idx := sk.find_bone(String(EnemyVisual.DEFAULT_BONES.head))
				if idx >= 0:
					head = sk.global_transform * sk.get_bone_global_pose(idx).origin + Vector3(0, 0.08, 0)
			cam.fov = 24.0
			cam.position = head + Vector3(0, 0.02, 1.1)
		"arriba":
			cam.fov = 40.0
			cam.position = Vector3(0, 3.2, 2.8 + width * 0.6)
			cam.rotation_degrees.x = -32.0
		_:
			cam.fov = 40.0
			cam.position = Vector3(0, 1.6, 5.2 + width * 0.5)
			cam.rotation_degrees.x = -10.0
	add_child(cam)
	cam.current = true

## Arranca el papel elegido; con --preview-at lo deja quieto en ese cuadro.
func _play(v: EnemyVisual) -> void:
	var length := v.play_role(_role, _role)
	if length <= 0.0:
		v.play_role("idle")
		return
	if _at >= 0.0 and v.anim:
		v.anim.seek(floorf(_at * length * v.fps) / v.fps, true)
		v.set_process(false)

## Para --call: show_role:attack (todos a la vez, en el cuadro 0 del papel).
func show_role(role: String) -> void:
	for v in visuals:
		v.play_role(role, role)
