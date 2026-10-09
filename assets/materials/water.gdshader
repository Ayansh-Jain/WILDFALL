shader_type spatial;
// Moonlit water: layered ripples, Fresnel sky reflection and a moon glitter
// path. Reflections are faked analytically (no screen-space reflections in
// the Compatibility renderer); `moon_dir` is set by World from the moon light.

render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.015, 0.06, 0.08);
uniform vec3 shallow_color : source_color = vec3(0.04, 0.14, 0.16);
uniform vec3 sky_zenith : source_color = vec3(0.03, 0.05, 0.11);
uniform vec3 sky_horizon : source_color = vec3(0.2, 0.26, 0.36);
uniform vec3 moon_color : source_color = vec3(0.85, 0.9, 1.0);
uniform vec3 moon_dir = vec3(0.54, 0.62, 0.54);
uniform float alpha_base : hint_range(0.0, 1.0) = 0.9;
uniform float ripple_speed = 0.5;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Analytic gradient of a sum of directional waves.
vec2 waves(vec2 p, float t) {
	vec2 g = vec2(0.0);
	vec2 dirs[5] = vec2[](vec2(1.0, 0.2), vec2(-0.4, 1.0), vec2(0.7, -0.7), vec2(-1.0, -0.3), vec2(0.2, 0.9));
	float freq[5] = float[](0.35, 0.6, 1.3, 2.4, 4.1);
	float amp[5] = float[](0.5, 0.35, 0.22, 0.12, 0.07);
	for (int i = 0; i < 5; i++) {
		vec2 d = normalize(dirs[i]);
		float ph = dot(d, p) * freq[i] + t * (1.0 + float(i) * 0.37);
		g += d * cos(ph) * amp[i] * freq[i];
	}
	return g;
}

void fragment() {
	float t = TIME * ripple_speed;
	vec2 g = waves(v_world.xz, t) * 0.09;
	vec3 n = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_world);
	vec3 r = reflect(-v, n);
	vec3 sky = mix(sky_horizon, sky_zenith, smoothstep(0.0, 0.6, r.y));
	float md = max(dot(r, normalize(moon_dir)), 0.0);
	float glint = pow(md, 700.0) * 5.0 + pow(md, 50.0) * 0.25;
	float fres = 0.03 + 0.97 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0);
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	vec3 base = mix(shallow_color, deep_color, smoothstep(5.0, 60.0, dist));
	ALBEDO = base * (1.0 - fres);
	EMISSION = sky * fres * 0.9 + moon_color * glint;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = clamp(alpha_base + fres * 0.1, 0.0, 1.0);
}
