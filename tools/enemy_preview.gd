extends Node3D
## Herramienta de desarrollo: todos los enemigos activos en fila, de frente
## (arriba) y de perfil (abajo), sin niebla ni pixelado, para revisar modelos,
## proporciones y animaciones. Con tools/screenshot.tscn:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     res://tools/screenshot.tscn -- --scene=res://tools/enemy_preview.tscn \
##     --out=/tmp/enemigos.png --frames=40 --call=show_role:attack
## Papeles: idle, combat, walk, attack, hit, death, spawn, dormant, ability, taunt.

const SPACING := 1.7

var visuals: Array[EnemyVisual] = []

func _ready() -> void:
	FloorBuilder.ensure_psx_shader_globals()
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
	var width := (ids.size() - 1) * SPACING
	for i in ids.size():
		var sp := DataRegistry.get_species(ids[i])
		if not sp.has("visual"):
			continue
		var visual: Dictionary = sp.visual
		for row in 2:
			var v := EnemyVisual.new()
			v.setup(visual, Color.WHITE, visual.eye_color, i)
			v.position = Vector3(i * SPACING - width / 2.0, 0, -row * 2.2)
			v.rotation_degrees.y = 0.0 if row == 0 else 90.0 # de frente / perfil
			add_child(v)
			v.play_role("idle")
			visuals.append(v)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.position = Vector3(0, 1.6, 5.2 + width * 0.5)
	cam.rotation_degrees.x = -10.0
	add_child(cam)
	cam.current = true

## Para --call: show_role:attack (todos a la vez, en el cuadro 0 del papel).
func show_role(role: String) -> void:
	for v in visuals:
		v.play_role(role, role)
