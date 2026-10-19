shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Shader PS1 casero — vertex snapping manual, sin depender de ningún asset externo.
// Simula la baja precisión de posición de vértices de la PS1 (el "temblor" característico)
// redondeando la posición en espacio de clip a una grilla de baja resolución.
// Para un resultado más completo (mapeo de texturas afín, dithering, etc.) conviene
// más adelante instalar un plugin real desde el AssetLib de Godot (ver README).

uniform vec4 albedo : source_color = vec4(1.0);
uniform float snap_precision : hint_range(1.0, 64.0) = 16.0; // mayor = menos temblor

void vertex() {
	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip_pos.xyz /= clip_pos.w;
	clip_pos.xy = floor(clip_pos.xy * snap_precision) / snap_precision;
	clip_pos.xyz *= clip_pos.w;
	POSITION = clip_pos;
}

void fragment() {
	ALBEDO = albedo.rgb;
}
