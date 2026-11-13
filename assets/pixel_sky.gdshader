shader_type canvas_item;

uniform float camera_offset = 0.0;
uniform float animation_rate = 0.22;

const vec2 PIXEL_GRID = vec2(240.0, 135.0);

float pixel_bubble(vec2 pixel_pos, vec2 center, float radius) {
	float d = length(pixel_pos - center);
	float outer = 1.0 - step(radius, d);
	float inner = 1.0 - step(radius - 1.5, d);
	return max(outer - inner, 0.0);
}

float pixel_fish(vec2 pixel_pos, vec2 center) {
	vec2 p = pixel_pos - center;
	float body = step(abs(p.x), 6.0) * step(abs(p.y), 2.0);
	float tail_span = max(0.0, 7.0 - abs(p.x + 8.0));
	float tail = step(abs(p.y), tail_span * 0.65) * step(p.x, -6.0) * step(-11.0, p.x);
	float fin = step(abs(p.x + 1.0), 2.0) * step(2.0, p.y) * step(p.y, 4.0);
	return max(max(body, tail), fin);
}

void fragment() {
	vec2 uv = floor(UV * PIXEL_GRID) / PIXEL_GRID;
	vec2 pixel_pos = uv * PIXEL_GRID;
	float t = TIME * animation_rate;
	vec3 water_top = vec3(0.30, 0.73, 0.79);
	vec3 water_bottom = vec3(0.025, 0.12, 0.23);
	vec3 color = mix(water_top, water_bottom, smoothstep(0.0, 1.0, uv.y));

	float sway = sin(t * 0.32 + uv.y * 3.0) * 0.018;
	float far_x = uv.x + camera_offset * 0.000012;
	float mid_x = uv.x + camera_offset * 0.000035;
	float ray_a = abs(uv.x - (0.12 + uv.y * 0.30 + sway));
	float ray_b = abs(uv.x - (0.48 + uv.y * 0.18 - sway * 0.7));
	float ray_c = abs(uv.x - (0.82 - uv.y * 0.22 + sway * 0.5));
	float rays = max(max(1.0 - smoothstep(0.025, 0.12, ray_a), 1.0 - smoothstep(0.035, 0.14, ray_b)), 1.0 - smoothstep(0.03, 0.13, ray_c));
	rays *= 1.0 - smoothstep(0.38, 0.78, uv.y);
	color = mix(color, vec3(0.53, 0.84, 0.86), rays * 0.18);

	float rock_edge = 0.48 + sin(far_x * 34.0) * 0.018 + sin(far_x * 79.0) * 0.008;
	float rocks = step(rock_edge, uv.y) * (1.0 - step(0.61, uv.y));
	color = mix(color, vec3(0.24, 0.48, 0.57), rocks * 0.36);
	float reef_edge = 0.60 + sin(mid_x * 24.0 + sin(mid_x * 7.0)) * 0.022;
	float reef = step(reef_edge, uv.y) * (1.0 - step(0.73, uv.y));
	color = mix(color, vec3(0.10, 0.37, 0.43), reef * 0.43);
	float grass_x = fract(mid_x * 13.0);
	float weed_height = 0.055 + 0.035 * (0.5 + 0.5 * sin(mid_x * 53.0 + t * 0.25));
	float weed = step(0.71 - weed_height, uv.y) * step(uv.y, 0.71) * step(0.44, grass_x) * step(grass_x, 0.58);
	color = mix(color, vec3(0.13, 0.42, 0.43), weed * 0.52);

	float bubbles = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float rise = fract(TIME * animation_rate * 0.11 + fi * 0.173);
		float bx = (0.09 + fi * 0.157) + sin(TIME * animation_rate * 0.7 + fi * 2.1) * 0.012;
		float by = 0.76 - rise * 0.73;
		bubbles = max(bubbles, pixel_bubble(pixel_pos, vec2(bx * PIXEL_GRID.x, by * PIXEL_GRID.y), 2.5));
	}
	color = mix(color, vec3(0.73, 0.94, 0.94), bubbles * 0.45);

	float fish_a_x = fract(TIME * animation_rate * 0.10 + 0.16);
	float fish_b_x = fract(TIME * animation_rate * 0.08 + 0.69);
	float fish_a = pixel_fish(pixel_pos, vec2(fish_a_x * PIXEL_GRID.x, 0.39 * PIXEL_GRID.y));
	float fish_b = pixel_fish(pixel_pos, vec2(fish_b_x * PIXEL_GRID.x, 0.31 * PIXEL_GRID.y));
	float fish_visible = step(0.33, fract(TIME * animation_rate * 0.09 + 0.18));
	color = mix(color, vec3(0.49, 0.72, 0.76), max(fish_a, fish_b) * fish_visible * 0.38);

	COLOR = vec4(color, 1.0);
}
