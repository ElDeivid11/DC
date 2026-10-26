// Sprite de pixel art de un enemigo (EnemySprite): un cuadro de la hoja sobre
// un quad que mira a la cámara. Lo iluminan las luces del mundo (antorchas)
// como a un HD-2D, con la MISMA niebla PSX que el resto (globals psx_fog_*,
// ver addons/psx/shaders/psx.gdshaderinc): a lo lejos se funde con el fondo.
// Los ojos (máscara `glow`) brillan con su color sin luz ni niebla: dos puntos
// en la oscuridad que se ven antes que el cuerpo.
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
// Golpe recibido: el sprite se pone blanco (0..1).
uniform float flash = 0.0;
// Luz propia mínima: que la silueta se lea aunque no la alumbre nada.
uniform float self_light = 0.12;
// Luz pareja (sprites de píxel gordo): todo el cuadro recibe la misma luz,
// que calcula EnemySprite en el centro del sprite (ambiente + luces cerca),
// en lineal. Así cada color queda plano, como en un sprite de 8/16 bits.
uniform bool flat_light = false;
uniform vec3 flat_color = vec3(1.0);

varying float v_fog;

void vertex() {
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_fog = psx_fog_near != psx_fog_far ?
		psx_fog_color.a * clamp((d - psx_fog_near) / (psx_fog_far - psx_fog_near), 0.0, 1.0) :
		0.0;
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
	vec3 albedo = mix(c.rgb * tint.rgb, vec3(1.0), flash);
	// Igual que el material PSX sombreado: con niebla total el color es
	// exactamente el de la niebla (el albedo se apaga y entra por emisión).
	if (flat_light) {
		// Sin albedo las luces de la escena no suman nada: todo entra por
		// emisión con la luz que calculó EnemySprite.
		ALBEDO = vec3(0.0);
		EMISSION = (albedo * (flat_color + vec3(self_light)) + vec3(flash) * 0.5) * (1.0 - v_fog) + psx_fog_color.rgb * v_fog;
	} else {
		ALBEDO = albedo * (1.0 - v_fog);
		EMISSION = (albedo * self_light + vec3(flash) * 0.5) * (1.0 - v_fog) + psx_fog_color.rgb * v_fog;
	}
	if (texture(glow, uv).r > 0.5) {
		ALBEDO = vec3(0.0);
		EMISSION = eye_color * eye_energy;
	}
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}
