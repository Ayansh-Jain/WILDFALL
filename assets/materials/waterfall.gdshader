shader_type spatial;
// Multi-layered turbulent waterfall sheet with aerated crest and plunge foam.

render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec3 water_color : source_color = vec3(0.14, 0.36, 0.40);
uniform vec3 foam_color : source_color = vec3(0.86, 0.93, 0.95);
uniform float speed = 1.85;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 41.2);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	float warp = vnoise(vec2(uv.x * 8.0, uv.y * 4.0 - t * 0.9)) * 0.08;
	float stream_a = vnoise(vec2((uv.x + warp) * 16.0, uv.y * 5.0 - t * 1.4));
	float stream_b = vnoise(vec2((uv.x - warp * 0.5) * 30.0, uv.y * 8.5 - t * 2.1));
	float streaks = stream_a * 0.62 + stream_b * 0.38;
	float crest = 1.0 - smoothstep(0.0, 0.16, uv.y);
	float plunge = smoothstep(0.68, 0.98, uv.y);
	float foam = clamp(smoothstep(0.42, 0.82, streaks) * 0.85 + crest * 0.55 + plunge * 0.85, 0.0, 1.0);
	float edge = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
	ALBEDO = mix(water_color, foam_color, foam);
	EMISSION = foam_color * foam * 0.16;
	ROUGHNESS = mix(0.18, 0.55, foam);
	SPECULAR = 0.45;
	ALPHA = (0.58 + foam * 0.38) * edge;
}
