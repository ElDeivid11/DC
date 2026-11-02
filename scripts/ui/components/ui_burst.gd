class_name UIBurst
extends Control
## Estallido de píxeles (golpes, críticos, muertes, curas, premios):
## cuadrados de 1–2 píxeles de arte con velocidad, gravedad y vida, en la
## grilla de píxel de arte; se apagan a saltos y el nodo se borra solo.
## Colores de UIStyle. Lo usan CombatFx y la tragaperras de los cofres.

const GRAVITY := 900.0
var parts: Array[Dictionary] = []
var target := Vector2.INF
var up := false

## Un estallido en `at` (coordenadas del padre, que debería cubrir la
## pantalla). target: si se da, los píxeles viajan hasta ahí (robo de vida,
## monedas); up: flotan hacia arriba sin caer (curas, almas).
static func make(at: Vector2, colors: Array[Color], count: int, speed := 260.0, p_target := Vector2.INF, p_up := false, rng: RandomNumberGenerator = null) -> UIBurst:
	var b := UIBurst.new()
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	b.setup(at, colors, count, speed, p_target, p_up, rng)
	return b

func setup(at: Vector2, colors: Array[Color], count: int, speed: float, p_target: Vector2, p_up: bool, rng: RandomNumberGenerator) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	target = p_target
	up = p_up
	for i in count:
		var ang := rng.randf_range(-PI, PI) if not up else rng.randf_range(-PI * 0.85, -PI * 0.15)
		var spd := speed * rng.randf_range(0.35, 1.0)
		var life := rng.randf_range(0.35, 0.7) if target == Vector2.INF else rng.randf_range(0.5, 0.8)
		parts.append({
			"p": at + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)),
			"v": Vector2(cos(ang), sin(ang)) * spd,
			"c": colors[i % colors.size()],
			"s": float(UIStyle.PIXEL_SCALE * (2 if rng.randf() < 0.35 else 1)),
			"life": life, "max": life,
		})

func _process(delta: float) -> void:
	var alive := false
	for q: Dictionary in parts:
		var life := float(q.life) - delta
		q["life"] = life
		if life <= 0.0:
			continue
		alive = true
		var v: Vector2 = q.v
		var p: Vector2 = q.p
		if target != Vector2.INF and float(q.max) - life > 0.12:
			# Viaja hacia el destino y se apaga al llegar.
			v = v.lerp((target - p).normalized() * 700.0, minf(1.0, delta * 7.0))
			if p.distance_to(target) < 14.0:
				q["life"] = 0.0
		elif up:
			v *= maxf(0.0, 1.0 - delta * 2.5)
			v.y -= 60.0 * delta
		else:
			v.y += GRAVITY * delta
		q["v"] = v
		q["p"] = p + v * delta
	if not alive:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	for q: Dictionary in parts:
		var life := float(q.life)
		if life <= 0.0:
			continue
		var f := life / float(q.max)
		var c: Color = q.c
		# Se apagan a saltos (3 tonos), no en fundido.
		c.a = 1.0 if f > 0.5 else (0.6 if f > 0.25 else 0.3)
		var s := float(q.s)
		var p := ((q.p as Vector2) / UIStyle.PIXEL_SCALE).floor() * UIStyle.PIXEL_SCALE
		draw_rect(Rect2(p, Vector2(s, s)), c)
