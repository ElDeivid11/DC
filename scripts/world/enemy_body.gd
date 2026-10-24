class_name EnemyBody
extends Node3D
## Lo que el juego ve de un enemigo en el mundo, sea un modelo 3D animado
## (EnemyVisual) o un sprite de pixel art (EnemySprite). RunController y el
## combate solo usan esta interfaz: papeles de animación (idle, combat, walk,
## attack, hit, death, spawn, dormant, ability, taunt), su luz propia y si ya
## murió. El nodo mira hacia +Z (como los modelos); RunController lo gira.

@warning_ignore("unused_signal")
signal finished_role(role: String)

## Papeles que se repiten (los demás suenan una vez y vuelven a `then`).
const LOOPING: Array[String] = ["idle", "combat", "walk", "dormant"]

var current_role := ""
## Luz propia (solo si visual.light existe; p. ej. el aura del nigromante).
var light: FlickerLight = null

## def = species.visual (ya validado por DataRegistry); tint = color
## multiplicador; eye = color de los ojos (y de la luz propia, si tiene).
func setup(_def: Dictionary, _tint: Color, _eye: Color, _variant_seed: int) -> void:
	pass

## Reproduce un papel. Los de una sola vez vuelven solos a `then` al terminar
## ("" = quedarse en el último cuadro, como la muerte). Devuelve la duración
## (0 = ese papel no existe).
func play_role(_role: String, _then := "idle") -> float:
	return 0.0

## Cambia a qué papel vuelve el clip en curso cuando termina.
func set_then(_role: String) -> void:
	pass

func has_role(_role: String) -> bool:
	return false

func is_dead() -> bool:
	return false

## Luz propia de visual.light (color mezclado con el de los ojos).
func _add_own_light(def: Dictionary, eye: Color) -> void:
	if not def.has("light"):
		return
	var l: Dictionary = def.light
	light = FlickerLight.make(eye.lerp(l.get("color", eye), 0.5), float(l.get("energy", 1.0)), float(l.get("range", 3.0)), 1.0, 0.1, 8.0)
	# visual.light.pos (opcional): dónde va la luz, en metros del modelo.
	light.position = _vec3(l.pos) if l.has("pos") else Vector3(0, 1.4, 0.4)
	add_child(light)

## [x, y, z] de los JSON (floats) -> Vector3; cualquier otra cosa, cero.
static func _vec3(v: Variant) -> Vector3:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() == 3:
		var a: Array = v
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO

## Mancha de sombra redonda con trama Bayer (recorte, sin mezcla alfa: no hay
## problemas de orden de dibujo, y es como lo hacía PS1).
static var _shadow_mat: PsxMaterial3D = null

static func _make_blob_shadow(diameter: float) -> MeshInstance3D:
	if _shadow_mat == null:
		const SIZE := 16
		const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		for y in SIZE:
			for x in SIZE:
				var d := Vector2(x + 0.5 - SIZE / 2.0, y + 0.5 - SIZE / 2.0).length() / (SIZE / 2.0)
				var a := clampf(1.0 - d, 0.0, 1.0) * 1.6
				var on := a > (BAYER[(x % 4) + (y % 4) * 4] + 0.5) / 16.0
				img.set_pixel(x, y, Color(0, 0, 0, 1.0 if on else 0.0))
		_shadow_mat = FloorBuilder.make_psx_material(Color(0.02, 0.02, 0.02), ImageTexture.create_from_image(img))
		_shadow_mat.transparency_mode = 1 # Cutout
		_shadow_mat.shading_mode = 0 # Unshaded
		_shadow_mat.refresh_shader()
	var quad := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(diameter, diameter)
	quad.mesh = plane
	quad.material_override = _shadow_mat
	quad.position.y = 0.02
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return quad
