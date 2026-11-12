
global uniform float psx_affine_strength;
global uniform float psx_precision_uv;
global uniform float psx_precision_xy;
global uniform float psx_precision_z;

// PARCHE (dungeon crawler): eran `instance uniform` (multiplicadores por
// instancia). El juego no los usa y cada instancia gastaba 3 lugares del
// buffer de variables globales (4096 en Compatibilidad): con ~400 mallas en
// un piso grande se agotaba. Ver docs/ESTADO_TECNICO_PROTOTIPO.md.
const float i_precision_uv = 1.0;
const float i_precision_xy = 1.0;
const float i_precision_z = 1.0;

uniform bool u_vertex_color_use_as_albedo = true;

uniform sampler2D u_albedo_texture: hint_default_white, filter_nearest;
uniform vec4 u_albedo_color: source_color = vec4(1.0);

varying vec3 v_vertex_color;
varying vec4 v_clip;
// PARCHE (dungeon crawler): w de CLIP para el mapeo afín (v_clip está en
// espacio de vista y su w siempre vale 1). Ver docs/ESTADO_TECNICO_PROTOTIPO.md.
varying float v_w;
varying vec2 v_uv;
varying vec2 v_uv2;

#if (!defined ALPHA_DISABLED) && (defined ALPHA_SCISSOR)
uniform float u_alpha_scissor_threshold: hint_range(0.0, 1.0, 0.01) = 0.5;
#endif

#if defined EMISSION_ADD
uniform vec3 u_emission: source_color = vec3(0.0, 0.0, 0.0);
uniform float u_emission_energy_multiplier = 1.0;
uniform bool u_emission_on_uv2 = false;
uniform sampler2D u_emission_texture: hint_default_black, filter_nearest;
#elif defined EMISSION_MULTIPLY
uniform vec3 u_emission: source_color = vec3(0.0, 0.0, 0.0);
uniform float u_emission_energy_multiplier = 1.0;
uniform bool u_emission_on_uv2 = false;
uniform sampler2D u_emission_texture: hint_default_black, filter_nearest;
#endif

#if (defined VERTEX_FOG_ENABLED) || (defined VERTEX_FOG_ALWAYS)
global uniform vec4 psx_fog_color;
global uniform float psx_fog_far;
global uniform float psx_fog_near;

varying float v_fog_strength;
varying vec3 v_fog_color;
#endif


void vertex() {
    v_vertex_color = COLOR.rgb;

#if !defined BILLBOARD_DISABLED
#if defined BILLBOARD_KEEP_SCALE
	mat3 model_basis = mat3(MODEL_MATRIX[0].xyz, MODEL_MATRIX[1].xyz, MODEL_MATRIX[2].xyz);
	bool mirrored = determinant(model_basis) < 0.0;
	vec3 model_scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	) * (mirrored ? -1.0 : 1.0);
#else
	vec3 model_scale = vec3(1.0);
#endif

#if (defined BILLBOARD_ENABLED) || (defined BILLBOARD_PARTICLES)
	MODELVIEW_MATRIX = mat4(
		vec4(model_scale.x, 0.0, 0.0, 0.0),
		vec4(0.0, model_scale.y, 0.0, 0.0),
		vec4(0.0, 0.0, model_scale.z, 0.0),
		MODELVIEW_MATRIX[3]
	);
	MODELVIEW_NORMAL_MATRIX = mat3(
		MODELVIEW_MATRIX[0].xyz,
		MODELVIEW_MATRIX[1].xyz,
		MODELVIEW_MATRIX[2].xyz
	);

#elif defined BILLBOARD_FIXED_Y
	vec3 vr = vec3(1.0, 0.0, 0.0);
	vec3 vu = VIEW_MATRIX[1].xyz;

	MODELVIEW_MATRIX = mat4(
		vec4(vr, 0.0),
		vec4(vu, 0.0),
		vec4(cross(vr, vu), 0.0),
		MODELVIEW_MATRIX[3]
	) * mat4(
		vec4(model_scale.x, 0, 0, 0),
		vec4(0, model_scale.y, 0, 0),
		vec4(0, 0, model_scale.z, 0),
		vec4(0, 0, 0, MODEL_MATRIX[3][3])
	);
	MODELVIEW_NORMAL_MATRIX = mat3(
		MODELVIEW_MATRIX[0].xyz,
		MODELVIEW_MATRIX[1].xyz,
		MODELVIEW_MATRIX[2].xyz
	);
#endif
#endif

	float precision_xy = psx_precision_xy * i_precision_xy;
	float precision_z = psx_precision_z * i_precision_z;

	v_clip = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float fov = 2.0 * atan(1.0 / PROJECTION_MATRIX[1][1]);
	// PARCHE: un vértice en z=0 de vista dividía por cero (NaN: el triángulo
	// desaparecía al pegarse a una pared grande).
	float clip_depth = min(v_clip.z, -0.001) * fov;

	if (precision_xy != 0.0) {
		v_clip.xy = trunc((v_clip.xy / clip_depth) * precision_xy) * clip_depth / precision_xy;
	}
	if (precision_z != 0.0) {
		v_clip.z = trunc((v_clip.z / fov) * precision_z) * fov / precision_z;
	}

	VERTEX = (inverse(MODELVIEW_MATRIX) * v_clip).xyz;

	// PARCHE: afín real = interpolar UV·w y dividir por w en el fragmento,
	// con la w de CLIP (antes v_clip.w = 1 y el afín no hacía nada).
	v_w = max((PROJECTION_MATRIX * v_clip).w, 0.001);
	v_uv = UV * v_w;
	v_uv2 = UV2 * v_w;

#if defined VERTEX_FOG_ENABLED
	// PARCHE: distancia real a la cámara (antes usaba v_clip.w = 1: la niebla
	// nunca aparecía).
	float view_dist = length(v_clip.xyz);
	v_fog_strength = psx_fog_near != psx_fog_far ?
		psx_fog_color.a * clamp((view_dist - psx_fog_near) / (psx_fog_far - psx_fog_near), 0.0, 1.0) :
		0.0;
	v_fog_color = psx_fog_color.rgb;
#elif defined VERTEX_FOG_ALWAYS
	v_fog_strength = psx_fog_color.a;
	v_fog_color = psx_fog_color.rgb;
#endif
}


void fragment() {
	vec2 uv = mix(UV, v_uv / v_w, psx_affine_strength);
	vec2 uv2 = mix(UV2, v_uv2 / v_w, psx_affine_strength);
	float precision_uv = psx_precision_uv * i_precision_uv;

	if (precision_uv != 0.0) {
		uv = trunc(uv * precision_uv) / precision_uv;
		uv2 = trunc(uv2 * precision_uv) / precision_uv;
	}

	vec4 albedo = texture(u_albedo_texture, uv) * u_albedo_color;
	if (u_vertex_color_use_as_albedo) {
		albedo *= vec4(v_vertex_color, 1.0);
	}

#if !defined ALPHA_DISABLED
	ALPHA *= albedo.a;
#if defined ALPHA_SCISSOR
	ALPHA_SCISSOR_THRESHOLD = u_alpha_scissor_threshold;
#endif
#endif

#if defined EMISSION_ADD
	vec3 emission = texture(u_emission_texture, u_emission_on_uv2 ? uv2 : uv).rgb + u_emission;
	EMISSION = emission * u_emission_energy_multiplier;
#elif defined EMISSION_MULTIPLY
	vec3 emission = texture(u_emission_texture, u_emission_on_uv2 ? uv2 : uv).rgb * u_emission;
	EMISSION = emission * u_emission_energy_multiplier;
#endif

#if (defined VERTEX_FOG_ENABLED) || (defined VERTEX_FOG_ALWAYS)
	// PARCHE: con niebla total el color es EXACTAMENTE el de la niebla (= el
	// fondo): se apaga el albedo (las luces no lo iluminan) y la niebla entra
	// por emisión. Antes ALBEDO=niebla se sumaba a la luz y brillaba.
#if defined SHADING_UNSHADED
	ALBEDO = mix(albedo.rgb, v_fog_color, v_fog_strength);
#else
	ALBEDO = albedo.rgb * (1.0 - v_fog_strength);
	EMISSION = EMISSION * (1.0 - v_fog_strength) + v_fog_color * v_fog_strength;
#endif
#else
	ALBEDO = albedo.rgb;
#endif

	SPECULAR = 0.0;
	ROUGHNESS = 0.0;
	METALLIC = 0.0;
}
