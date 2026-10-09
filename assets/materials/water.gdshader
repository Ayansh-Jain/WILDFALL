shader_type spatial;
// Stylised moonlit water. Opaque enough to read clearly as "not ground".

render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.03, 0.17, 0.21);
uniform vec3 shallow_color : source_color = vec3(0.07, 0.33, 0.36);
uniform vec3 foam_color : source_color = vec3(0.55, 0.7, 0.72);
uniform float alpha_base : hint_range(0.0, 1.0) = 0.84;
uniform float ripple_scale = 0.35;
uniform float ripple_speed = 0.6;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 ripple_grad(vec2 p, float t) {
	vec2 g = vec2(0.0);
	g += vec2(cos(p.x * 0.9 + t * 1.1), 0.0) * 0.9;
	g += vec2(0.0, cos(p.y * 1.2 - t * 0.9)) * 0.8;
	g += vec2(cos((p.x + p.y) * 1.7 + t * 1.6), cos((p.x + p.y) * 1.7 + t * 1.6)) * 0.45;
	g += vec2(cos((p.x - p.y) * 2.9 - t * 2.1), -cos((p.x - p.y) * 2.9 - t * 2.1)) * 0.25;
	return g;
}

void fragment() {
	float t = TIME * ripple_speed;
	vec2 g = ripple_grad(v_world.xz * ripple_scale, t) * 0.06;
	vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float sparkle = smoothstep(0.92, 1.0, sin(v_world.x * 1.7 + t * 2.0) * sin(v_world.z * 1.9 - t * 1.7));
	vec3 col = mix(shallow_color, deep_color, 0.55 + 0.45 * fres);
	col += foam_color * sparkle * 0.08;
	ALBEDO = col;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = clamp(alpha_base + fres * 0.14, 0.0, 1.0);
}
