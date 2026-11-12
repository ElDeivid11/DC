// Sprite de pixel art de un enemigo (EnemySprite): un cuadro de la hoja sobre
// un quad que mira a la cámara. Lo iluminan las luces del mundo (antorchas)
// como a un HD-2D, con la MISMA niebla PSX que el resto (globals psx_fog_*,
// ver addons/psx/shaders/psx.gdshaderinc): a lo lejos se funde con el fondo.
// Los ojos (máscara `glow` a 1) brillan con su color sin luz ni niebla: dos
// puntos en la oscuridad que se ven antes que el cuerpo. Lo «espiritual»
// (máscara a 0,5: un espectro, una llama, un aura) brilla igual pero con su
// gris por el color de ojos, así tiene tonos. El ALMA que guarda el enemigo
// (máscara a 0,25: la llama entre las costillas, la del báculo del jefe)
// brilla igual con el color de su afinidad y parpadea a saltos; apagada
// (murió o no guarda ninguna) es un hueco oscuro.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled, fog_disabled;

global uniform vec4 psx_fog_color;
global uniform float psx_fog_far;
global uniform float psx_fog_near;

uniform sampler2D sheet : source_color, filter_nearest, repeat_disable;
uniform sampler2D glow : hint_default_black, filter_nearest, repeat_disable;
// Cuadro actual en UV de la hoja: (u0, v0, ancho, alto).
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool flip_h = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 eye_color : source_color = vec3(1.0);
uniform float eye_energy = 1.4;
// Lo espiritual (máscara a 0,5) brilla menos que los ojos: se ve, pero no tapa.
uniform float spirit_energy = 0.6;
// El alma que guarda: color de su afinidad y energía (0 = apagada).
uniform vec3 soul_color : source_color = vec3(0.0);
uniform float soul_energy = 0.0;
// Golpe recibido: el sprite se pone blanco (0..1).
uniform float flash = 0.0;
// Luz propia mínima: que la silueta se lea aunque no la alumbre nada.
uniform float self_light = 0.12;
// Luz pareja (sprites de píxel gordo): todo el cuadro recibe la misma luz,
// que calcula EnemySprite en el centro del sprite (ambiente + luces cerca),
// en lineal. Así cada color queda plano, como en un sprite de 8/16 bits.
uniform bool flat_light = false;
uniform vec3 flat_color = vec3(1.0);
// Luz por píxel del sprite con su mapa de normales (RGB: x derecha, y arriba,
// z hacia la cámara; alfa < 0,75 = metal). EnemySprite pasa el ambiente y
// las luces más fuertes ya en el espacio del sprite (dirección hacia la luz y
// color por energía y atenuación, en lineal). La luz va en bandas, como un
// sombreado de pixel art, y cada píxel del sprite recibe una sola.
uniform bool use_normals = false;
uniform sampler2D normal_tex : hint_default_black, filter_nearest, repeat_disable;
uniform vec3 ambient = vec3(0.2);
uniform vec3 light_dir[4];
uniform vec3 light_col[4];
uniform int light_count = 0;
// Cuánto del color de la luz toma el sprite (1 = todo; 0 = solo cuánta luz).
uniform float tint_amount = 0.5;
// 1 / tamaño de la hoja en píxeles (para el halo de los ojos).
uniform vec2 texel = vec2(0.0);

varying float v_fog;

void vertex() {
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_fog = psx_fog_near != psx_fog_far ?
		psx_fog_color.a * clamp((d - psx_fog_near) / (psx_fog_far - psx_fog_near), 0.0, 1.0) :
		0.0;
}

// Bandas de luz: a pleno, media, poca, nada.
float band(float x) {
	return x > 0.7 ? 1.0 : (x > 0.35 ? 0.65 : (x > 0.08 ? 0.35 : 0.0));
}

vec3 sprite_light(vec2 uv, out vec3 spec) {
	vec4 nm = texture(normal_tex, uv);
	vec3 n = normalize(nm.rgb * 2.0 - 1.0);
	if (flip_h) {
		n.x = -n.x;
	}
	bool metal = nm.a < 0.75;
	vec3 lit = ambient;
	spec = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		if (i >= light_count) {
			break;
		}
		lit += light_col[i] * band(dot(n, light_dir[i]));
		// Destello del metal: el píxel que refleja la luz hacia la cámara.
		if (metal && dot(n, normalize(light_dir[i] + vec3(0.0, 0.0, 1.0))) > 0.93) {
			spec += light_col[i] * 0.8;
		}
	}
	float lum = dot(lit, vec3(1.0 / 3.0));
	return mix(vec3(lum), lit, tint_amount);
}

// Reflejo de los ojos y del alma: el hueso a 1-2 píxeles de una pupila (x)
// o de la llama del alma (y) toma un poco de su luz (las cuencas, negras,
// siguen negras).
vec2 glow_halo(vec2 uv) {
	vec2 halo = vec2(0.0);
	for (int dy = -2; dy <= 2; dy++) {
		for (int dx = -2; dx <= 2; dx++) {
			float g = texture(glow, uv + vec2(float(dx), float(dy)) * texel).r;
			if (g > 0.75) {
				halo.x = 0.12;
			} else if (g > 0.15 && g < 0.4) {
				halo.y = 0.22;
			}
		}
	}
	return halo;
}

// Parpadeo de llama: cambia de a saltos y distinto en cada fila de píxeles.
float soul_flicker(vec2 uv) {
	float row = texel.y > 0.0 ? floor(uv.y / texel.y) : 0.0;
	float n = fract(sin(floor(TIME * 9.0) * 12.9898 + row * 4.137) * 43758.5453);
	return 0.72 + 0.28 * n;
}

void fragment() {
	vec2 uv = UV;
	if (flip_h) {
		uv.x = 1.0 - uv.x;
	}
	uv = frame_rect.xy + uv * frame_rect.zw;
	vec4 c = texture(sheet, uv);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	float g = texture(glow, uv).r;
	bool held = g > 0.15 && g < 0.4;
	if (held && soul_energy <= 0.0) {
		// Sin alma: el hueco entre las costillas, casi negro.
		c.rgb = vec3(0.0103, 0.0052, 0.0144);
	}
	vec3 albedo = mix(c.rgb * tint.rgb, vec3(1.0), flash);
	// Igual que el material PSX sombreado: con niebla total el color es
	// exactamente el de la niebla (el albedo se apaga y entra por emisión).
	if (use_normals) {
		// Sin albedo las luces de la escena no suman nada: todo entra por
		// emisión con la luz que se calcula acá.
		vec3 spec;
		vec3 lit = sprite_light(uv, spec);
		vec2 h = glow_halo(uv);
		vec3 halo = albedo * (eye_color * eye_energy * h.x + soul_color * soul_energy * h.y);
		ALBEDO = vec3(0.0);
		EMISSION = (albedo * (lit + vec3(self_light)) + spec + halo + vec3(flash) * 0.5) * (1.0 - v_fog) + psx_fog_color.rgb * v_fog;
	} else if (flat_light) {
		ALBEDO = vec3(0.0);
		EMISSION = (albedo * (flat_color + vec3(self_light)) + vec3(flash) * 0.5) * (1.0 - v_fog) + psx_fog_color.rgb * v_fog;
	} else {
		ALBEDO = albedo * (1.0 - v_fog);
		EMISSION = (albedo * self_light + vec3(flash) * 0.5) * (1.0 - v_fog) + psx_fog_color.rgb * v_fog;
	}
	if (g > 0.75) {
		ALBEDO = vec3(0.0);
		EMISSION = eye_color * eye_energy;
	} else if (g > 0.4) {
		ALBEDO = vec3(0.0);
		EMISSION = dot(c.rgb, vec3(1.0 / 3.0)) * eye_color * eye_energy * spirit_energy + vec3(flash) * 0.5;
	} else if (held && soul_energy > 0.0) {
		ALBEDO = vec3(0.0);
		EMISSION = dot(c.rgb, vec3(1.0 / 3.0)) * soul_color * soul_energy * soul_flicker(uv) + vec3(flash) * 0.5;
	}
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}
