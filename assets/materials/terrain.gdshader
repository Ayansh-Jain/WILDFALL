shader_type spatial;
// Terrain: vertex colour masks painted by the generator.
//   r = trail, g = forest floor, b = shore / wet ground, a = stone paving.
// Slope and altitude add rock automatically.

uniform vec3 grass_a : source_color = vec3(0.10, 0.17, 0.08);
uniform vec3 grass_b : source_color = vec3(0.16, 0.22, 0.10);
uniform vec3 forest_floor : source_color = vec3(0.12, 0.11, 0.07);
uniform vec3 dirt : source_color = vec3(0.27, 0.22, 0.15);
uniform vec3 rock : source_color = vec3(0.30, 0.31, 0.33);
uniform vec3 rock_dark : source_color = vec3(0.18, 0.19, 0.21);
uniform vec3 mud : source_color = vec3(0.20, 0.17, 0.12);
uniform vec3 paving : source_color = vec3(0.3, 0.29, 0.27);
uniform vec3 underwater : source_color = vec3(0.06, 0.13, 0.14);
uniform float water_level = 0.0;

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec4 v_mask;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_mask = COLOR;
}

void fragment() {
	vec2 p = v_world.xz;
	float n1 = vnoise(p * 0.08);
	float n2 = vnoise(p * 0.6);
	float n3 = vnoise(p * 2.3);

	vec3 col = mix(grass_a, grass_b, smoothstep(0.3, 0.75, n1));
	col *= 0.85 + 0.3 * n2;
	col = mix(col, forest_floor * (0.8 + 0.4 * n2), clamp(v_mask.g, 0.0, 1.0));

	float slope = 1.0 - v_wnormal.y;
	float rockiness = smoothstep(0.16, 0.30, slope + (n2 - 0.5) * 0.08);
	rockiness = max(rockiness, smoothstep(38.0, 48.0, v_world.y + n1 * 6.0));
	vec3 rock_col = mix(rock_dark, rock, n3 * 0.6 + n1 * 0.4);
	col = mix(col, rock_col, rockiness);

	float trail = smoothstep(0.15, 0.7, v_mask.r + (n3 - 0.5) * 0.35);
	col = mix(col, dirt * (0.85 + 0.25 * n3), trail * (1.0 - rockiness * 0.6));

	float pave = smoothstep(0.2, 0.6, v_mask.a + (n2 - 0.5) * 0.4);
	vec2 tile = floor(p * 0.9);
	vec3 pave_col = paving * (0.78 + 0.3 * hash21(tile)) * (0.9 + 0.2 * n3);
	col = mix(col, pave_col, pave);

	col = mix(col, mud * (0.8 + 0.3 * n3), clamp(v_mask.b, 0.0, 1.0));

	float depth = water_level - v_world.y;
	col = mix(col, underwater, smoothstep(0.0, 2.5, depth));

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.75, v_mask.b);
	SPECULAR = 0.15;
}
