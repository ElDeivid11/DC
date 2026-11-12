shader_type canvas_item;
// Trama de color de PS1 (15 bits: 5 por canal, Bayer 4x4) aplicada DENTRO del
// SubViewport de baja resolución: cada celda de la trama es un píxel del
// juego y la UI (fuera del SubViewport) queda limpia. Es la misma cuenta que
// addons/psx/shaders/psx_postprocess.gdshader, con la profundidad como
// uniform local (el global psx_bit_depth queda en 0 y apaga el del addon).

const float BAYER_4X4[16] = float[](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0
);

uniform int bit_depth: hint_range(1, 7) = 5;
uniform sampler2D screen_texture: hint_screen_texture, filter_nearest;

void fragment() {
	ivec2 p = ivec2(floor(FRAGCOORD.xy));
	float norm = BAYER_4X4[(p.x & 3) + (p.y & 3) * 4] / 16.0;
	float levels = float((1 << bit_depth) - 1);
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	COLOR = vec4(floor((c + norm / levels) * levels) / levels, 1.0);
}
