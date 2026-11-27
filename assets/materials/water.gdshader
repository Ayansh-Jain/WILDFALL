shader_type spatial;
// Flowing river & lake water (Compatibility GL 3.3 safe).
// Uses dual-layer advected noise ripples, optional baked shore/flow texture
// (R = depth 0..1, GB = flow dir, A = rapids/foam boost), shoreline foam,
// depth color absorption, Fresnel sky reflection, and sun/moon sparkle.

render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.02, 0.09, 0.12);
uniform vec3 shallow_color : source_color = vec3(0.06, 0.22, 0.21);
uniform vec3 foam_color : source_color = vec3(0.84, 0.90, 0.92);
uniform vec3 sky_zenith : source_color = vec3(0.11, 0.30, 0.62);
uniform vec3 sky_horizon : source_color = vec3(0.68, 0.74, 0.80);
uniform vec3 moon_color : source_color = vec3(1.0, 0.92, 0.74);
uniform vec3 moon_dir = vec3(0.54, 0.62, 0.54);
uniform float alpha_base : hint_range(0.0, 1.0) = 0.88;
uniform float ripple_speed = 0.65;
uniform float flow_speed = 1.4;
uniform sampler2D shore_map : filter_linear, repeat_disable;
uniform float map_half_size = 340.0;
uniform float use_shore_map = 0.0;

varying vec3 v_world;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.5);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Smooth multi-directional organic water surface height (avoids linear sine stripes).
float water_h(vec2 p, float t) {
	vec2 p1 = mat2(vec2(0.86, 0.50), vec2(-0.50, 0.86)) * p;
	vec2 p2 = mat2(vec2(0.62, -0.78), vec2(0.78, 0.62)) * p;
	float h = vnoise(p1 * 0.42 + vec2(t * 0.55, -t * 0.38)) * 0.55;
	h += vnoise(p2 * 0.95 + vec2(-t * 0.72, t * 0.64)) * 0.30;
	h += vnoise(p * 2.10 + vec2(t * 1.15, t * 0.85)) * 0.15;
	return h;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * ripple_speed;
	vec2 flow = vec2(0.0, 0.45);
	float depth_n = 0.7;
	float rapids = 0.0;

	if (use_shore_map > 0.5) {
		vec2 suv = clamp((v_world.xz / (map_half_size * 2.0)) + 0.5, vec2(0.002), vec2(0.998));
		vec4 sm = texture(shore_map, suv);
		depth_n = sm.r;
		flow = (sm.gb * 2.0 - 1.0) * flow_speed;
		rapids = sm.a;
	}

	vec2 adv = v_world.xz - flow * TIME * 0.9;
	float eps = 0.22;
	float hc = water_h(adv, t);
	float hx = water_h(adv + vec2(eps, 0.0), t);
	float hz = water_h(adv + vec2(0.0, eps), t);
	float amp = mix(0.24, 0.42, clamp(length(flow) * 0.5 + rapids, 0.0, 1.0));
	vec3 n = normalize(vec3((hc - hx) * amp / eps, 1.0, (hc - hz) * amp / eps));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	vec3 v = normalize(CAMERA_POSITION_WORLD - v_world);
	vec3 r = reflect(-v, n);
	vec3 sky = mix(sky_horizon, sky_zenith, smoothstep(-0.02, 0.55, r.y));
	float md = max(dot(r, normalize(moon_dir)), 0.0);
	float glint = pow(md, 420.0) * 3.8 + pow(md, 36.0) * 0.22;
	float fres = 0.035 + 0.965 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0);

	float cam_dist = length(CAMERA_POSITION_WORLD - v_world);
	float depth_mix = smoothstep(0.06, 0.72, depth_n) * mix(0.65, 1.0, smoothstep(4.0, 45.0, cam_dist));
	vec3 water_col = mix(shallow_color, deep_color, depth_mix);

	// Organic shoreline & rapids foam.
	float foam_noise = vnoise(adv * 1.45 + vec2(t * 0.6, -t * 0.4)) * 0.65 + vnoise(adv * 3.4 - vec2(t * 0.9, t * 0.7)) * 0.35;
	float shore_band = (1.0 - smoothstep(0.01, 0.19, depth_n)) * smoothstep(0.36, 0.68, foam_noise + (1.0 - depth_n) * 0.22);
	float rapid_foam = rapids * smoothstep(0.42, 0.78, foam_noise);
	float foam = clamp(max(shore_band * 0.85, rapid_foam), 0.0, 1.0);

	vec3 base = mix(water_col, foam_color, foam * 0.82);
	ALBEDO = base * (1.0 - fres * 0.65);
	EMISSION = sky * fres * 0.85 + moon_color * glint + foam_color * foam * 0.12;
	ROUGHNESS = mix(0.07, 0.45, foam);
	METALLIC = 0.0;
	SPECULAR = 0.58;
	float shore_fade = use_shore_map > 0.5 ? smoothstep(0.0, 0.085, depth_n) : 1.0;
	ALPHA = clamp(mix(0.04, alpha_base, shore_fade) + fres * 0.10 * shore_fade + foam * 0.16, 0.0, 1.0);
}
