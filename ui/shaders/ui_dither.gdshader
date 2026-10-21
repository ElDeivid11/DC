// Velo con trama Bayer 4×4 (PS1): fundidos de escena y viñeta del Hub sin
// mezcla alfa suave. Cada celda de la trama es un píxel de arte (cell_px).
//   mode 0 = fundido uniforme (progress 0 → 1 cubre todo)
//   mode 1 = viñeta: más tapado a la izquierda y abajo (detrás del menú)
// El color lo pone el código desde UIStyle (BG_DEEP).
shader_type canvas_item;

uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform int mode = 0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float cell_px = 2.0;

const int B4[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};

void fragment() {
	ivec2 cell = ivec2(floor(FRAGCOORD.xy / max(cell_px, 1.0))) % 4;
	float b = float(B4[cell.y * 4 + cell.x]);
	float a = progress;
	if (mode == 1) {
		float left = 0.9 * (1.0 - UV.x / 0.6);
		float bottom = 0.8 * (1.0 - (1.0 - UV.y) / 0.35);
		a = clamp(max(left, bottom), 0.0, 1.0) * progress;
	}
	COLOR = vec4(color.rgb, (a * 16.0 > b + 0.5) ? color.a : 0.0);
}
