shader_type spatial;
// Falling water sheet: streaks scroll down the UV.y axis.

render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec3 water_color : source_color = vec3(0.12, 0.38, 0.42);
uniform vec3 foam_color : source_color = vec3(0.75, 0.88, 0.9);
uniform float speed = 1.6;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float col = floor(uv.x * 26.0);
	float streak = hash(vec2(col, 0.0));
	float flow = fract(uv.y * 3.0 - TIME * speed * (0.7 + streak * 0.6) + streak);
	float foam = smoothstep(0.55, 1.0, flow) * (0.4 + streak * 0.6);
	float edge = smoothstep(0.0, 0.08, uv.x) * smoothstep(1.0, 0.92, uv.x);
	ALBEDO = mix(water_color, foam_color, foam);
	EMISSION = foam_color * foam * 0.15;
	ROUGHNESS = 0.2;
	ALPHA = (0.65 + foam * 0.3) * edge;
}
