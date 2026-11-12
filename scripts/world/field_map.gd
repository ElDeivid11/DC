class_name FieldMap
extends Node3D
## El mapa de mano (M): el héroe baja un poco la mirada y levanta un
## pergamino abierto entre dos varas, con lo descubierto del piso dibujado a
## tinta (MapParchment). Cuelga de la cámara (sigue al jugador sin pensar);
## RunController lo abre y lo cierra y bloquea el movimiento mientras tanto.
## Lo alumbra la antorcha de mano (de arriba); la niebla no lo toca. Valores
## en balance.json → render.map.

## Al terminar de abrirse (true) o de guardarse (false).
signal toggled(open: bool)

## Hoja de 4:3 (la textura es de 256×192).
const SHEET := Vector2(0.56, 0.42)
const ROD_R := 0.02
const SEGMENTS := Vector2i(16, 12)
## Sostenido frente a la cara (en coordenadas de la cámara) y guardado abajo.
const HELD := Vector3(0.0, -0.04, -0.68)
const HIDDEN := Vector3(0.0, -0.46, -0.34)
const HELD_TILT := -12.0
const HIDDEN_TILT := -75.0

var is_open := false
var cam: Camera3D
var sheet: MeshInstance3D
var _paper: PsxMaterial3D
var _tween: Tween
var _t := 0.0

func _init(p_cam: Camera3D = null) -> void:
	cam = p_cam
	visible = false
	position = HIDDEN
	rotation_degrees.x = HIDDEN_TILT
	sheet = MeshInstance3D.new()
	sheet.mesh = _sheet_mesh()
	_paper = FloorBuilder.make_psx_material(Color.WHITE.darkened(DataRegistry.bal_f("render.map.paper_shade", 0.25)))
	_paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	_paper.fog_mode = PsxMaterial3D.FogMode.DISABLED
	_paper.refresh_shader()
	sheet.material_override = _paper
	add_child(sheet)
	var wood := FloorBuilder.make_psx_material(UIStyle.BRONCE_OSC)
	wood.fog_mode = PsxMaterial3D.FogMode.DISABLED
	wood.refresh_shader()
	var brass := FloorBuilder.make_psx_material(UIStyle.BRONCE)
	brass.fog_mode = PsxMaterial3D.FogMode.DISABLED
	brass.refresh_shader()
	# Las dos varas donde se enrolla, con perillas de bronce.
	for side: float in [-1.0, 1.0]:
		var rod := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = ROD_R
		cyl.bottom_radius = ROD_R
		cyl.height = SHEET.y + 0.04
		cyl.radial_segments = 8
		cyl.rings = 1
		rod.mesh = cyl
		rod.material_override = wood
		rod.position = Vector3(side * (SHEET.x / 2.0 + ROD_R * 0.5), 0.0, ROD_R)
		add_child(rod)
		for end: float in [-1.0, 1.0]:
			var knob := MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = ROD_R * 1.5
			ball.height = ROD_R * 3.0
			ball.radial_segments = 8
			ball.rings = 4
			knob.mesh = ball
			knob.material_override = brass
			knob.position = rod.position + Vector3(0.0, end * (cyl.height / 2.0 + ROD_R), 0.0)
			add_child(knob)

## Hoja con una ondulación leve y los bordes que se curvan hacia las varas.
## Normales a mano (hacia la cámara), para la luz por vértice del PSX.
static func _sheet_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in SEGMENTS.y + 1:
		for i in SEGMENTS.x + 1:
			var u := float(i) / SEGMENTS.x
			var v := float(j) / SEGMENTS.y
			var e := (u - 0.5) * 2.0
			var z := ROD_R * pow(absf(e), 6.0) + 0.005 * sin(v * TAU + u * 3.0)
			var dzdx := ROD_R * 6.0 * pow(absf(e), 5.0) * signf(e) * 2.0 / SHEET.x
			var dzdy := -0.005 * TAU * cos(v * TAU + u * 3.0) / SHEET.y
			st.set_normal(Vector3(-dzdx, -dzdy, 1.0).normalized())
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3((u - 0.5) * SHEET.x, (0.5 - v) * SHEET.y, z))
	for j in SEGMENTS.y:
		for i in SEGMENTS.x:
			var a := j * (SEGMENTS.x + 1) + i
			var c := a + SEGMENTS.x + 1
			for k: int in [a, a + 1, c, a + 1, c + 1, c]:
				st.add_index(k)
	return st.commit()

## Abre el mapa con este dibujo (MapParchment.render).
func open(img: Image) -> void:
	_paper.albedo_texture = ImageTexture.create_from_image(img)
	if is_open:
		return
	is_open = true
	visible = true
	_animate(true)

func close() -> void:
	if not is_open:
		return
	is_open = false
	_animate(false)

## Sube la hoja (con un rebote leve) mientras la cámara mira hacia abajo; al
## guardarla, al revés y más rápido.
func _animate(opening: bool) -> void:
	if _tween:
		_tween.kill()
	var t := DataRegistry.bal_f("render.map.open_time", 0.32) if opening else DataRegistry.bal_f("render.map.close_time", 0.2)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position", HELD if opening else HIDDEN, t) \
		.set_trans(Tween.TRANS_BACK if opening else Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if opening else Tween.EASE_IN)
	_tween.tween_property(self, "rotation_degrees:x", HELD_TILT if opening else HIDDEN_TILT, t) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if opening else Tween.EASE_IN)
	if cam:
		_tween.tween_property(cam, "rotation_degrees:x", -DataRegistry.bal_f("render.map.pitch", 24.0) if opening else 0.0, t) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.chain().tween_callback(func() -> void:
		visible = is_open
		toggled.emit(is_open))

## Mientras está abierto, la hoja respira apenas (las manos no son de piedra).
func _process(delta: float) -> void:
	if not is_open or (_tween and _tween.is_running()):
		return
	_t += delta
	position = HELD + Vector3(sin(_t * 0.9) * 0.002, sin(_t * 1.7) * 0.003, 0.0)
