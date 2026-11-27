shader_type spatial;
// Atmospheric distant mountain silhouettes: triplanar rock strata, valley forest tint,
// high-altitude snow ridges, and distance-based aerial perspective blending into the horizon.

uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 foothill_color : source_color = vec3(0.14, 0.20, 0.13);
uniform vec3 ridge_color : source_color = vec3(0.32, 0.35, 0.40);
uniform vec3 snow_color : source_color = vec3(0.80, 0.84, 0.92);
uniform vec3 haze_color : source_color = vec3(0.56, 0.64, 0.74);
uniform float snow_line = 58.0;
uniform float haze_start = 260.0;
uniform float haze_end = 1350.0;

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec4 v_col;
varying float v_dist;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = COLOR;
	v_dist = length(CAMERA_POSITION_WORLD - v_world);
}

void fragment() {
	vec3 n = normalize(v_wnormal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float rs = 0.032;
	vec3 rk = texture(rock_tex, v_world.zy * rs).rgb * w.x
		+ texture(rock_tex, v_world.xz * rs).rgb * w.y
		+ texture(rock_tex, v_world.xy * rs).rgb * w.z;
	float macro = vnoise(v_world.xz * 0.008);
	float strata = 0.86 + 0.24 * vnoise(vec2(v_world.y * 0.14 + macro * 2.0, v_world.x * 0.01));
	vec3 rock = rk * ridge_color * 1.45 * strata;

	// Forested foothills below rock/snow line (driven by vertex color green channel).
	float forest = clamp(v_col.g * 1.5 + (1.0 - smoothstep(14.0, 48.0, v_world.y)) * 0.5, 0.0, 1.0) * smoothstep(0.35, 0.72, n.y);
	vec3 col = mix(rock, foothill_color * (0.75 + 0.5 * macro), forest);

	// Snow on upper ridges and flatter ledges.
	float snow_w = smoothstep(snow_line, snow_line + 26.0, v_world.y + macro * 18.0) * smoothstep(0.18, 0.55, n.y);
	if (snow_w > 0.01) {
		vec3 sn = texture(snow_tex, v_world.xz * 0.04).rgb * snow_color;
		col = mix(col, sn, snow_w);
	}

	// Aerial perspective haze separating near foothills from far peaks.
	float haze = smoothstep(haze_start, haze_end, v_dist) * 0.62;
	col = mix(col, haze_color, haze);

	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.65, snow_w);
	SPECULAR = 0.18;
}
