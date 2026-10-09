shader_type spatial;
// Terrain: photo textures (Poly Haven, CC0) blended by the generator's vertex
// colour masks:  r = trail, g = forest floor, b = shore / wet ground, a = paving.
// Slope switches to triplanar rock; altitude adds snow on the mountains.
// Each layer is sampled at two scales to hide tiling. Normal maps are applied
// in world space (the terrain mesh has no tangents).

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D trail_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D trail_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paving_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 grass_tint : source_color = vec3(0.5, 0.72, 0.46);
uniform vec3 forest_tint : source_color = vec3(0.62, 0.6, 0.52);
uniform vec3 rock_tint : source_color = vec3(0.74, 0.78, 0.88);
uniform float grass_scale = 0.22;
uniform float trail_scale = 0.3;
uniform float rock_scale = 0.08;
uniform float snow_height = 52.0;
uniform float brightness = 0.8;
uniform float water_level = 0.0;
uniform vec3 underwater : source_color = vec3(0.05, 0.12, 0.13);

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

// Two-scale sample: detail tiling blended with a rotated macro tiling.
vec3 tex2(sampler2D t, vec2 p, float s) {
	vec3 a = texture(t, p * s).rgb;
	vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * s * 0.27;
	vec3 b = texture(t, q).rgb;
	return mix(a, b, 0.4);
}

vec3 nrm_xz(sampler2D t, vec2 p, float s) {
	vec3 n = texture(t, p * s).rgb * 2.0 - 1.0;
	return vec3(n.x, n.z, -n.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_mask = COLOR;
}

void fragment() {
	vec2 p = v_world.xz;
	vec3 n = normalize(v_wnormal);
	float macro = vnoise(p * 0.035);
	float patch = vnoise(p * 0.11);

	// Ground layers.
	vec3 grass = tex2(grass_tex, p, grass_scale) * grass_tint;
	grass *= 0.85 + 0.3 * macro;
	vec3 col = grass;
	float forest_w = clamp(v_mask.g * 1.2 + (patch - 0.5) * 0.3, 0.0, 1.0);
	if (forest_w > 0.01) {
		col = mix(grass, tex2(forest_tex, p, grass_scale * 0.8) * forest_tint, forest_w);
	}
	vec3 gn = nrm_xz(grass_nrm, p, grass_scale);

	float trail = smoothstep(0.15, 0.65, v_mask.r + (patch - 0.5) * 0.3);
	if (trail > 0.001) {
		vec3 trail_col = tex2(trail_tex, p, trail_scale) * vec3(0.55, 0.52, 0.48);
		col = mix(col, trail_col, trail);
		gn = mix(gn, nrm_xz(trail_nrm, p, trail_scale), trail);
	}

	float pave = smoothstep(0.2, 0.6, v_mask.a + (patch - 0.5) * 0.4);
	if (pave > 0.001) {
		vec3 pv = tex2(paving_tex, p, 0.35);
		pv = mix(vec3(dot(pv, vec3(0.33))), pv, 0.35) * vec3(0.62, 0.63, 0.66);
		col = mix(col, pv, pave);
	}
	if (v_mask.b > 0.001) {
		col = mix(col, tex2(mud_tex, p, 0.3) * 0.8, clamp(v_mask.b, 0.0, 1.0));
	}

	// Rock on slopes and high ground (triplanar so cliffs do not stretch).
	float slope = 1.0 - n.y;
	float rockiness = smoothstep(0.17, 0.32, slope + (patch - 0.5) * 0.1);
	rockiness = max(rockiness, smoothstep(40.0, 50.0, v_world.y + macro * 8.0));
	vec3 rn = vec3(0.0);
	if (rockiness > 0.001) {
		vec3 w = pow(abs(n), vec3(4.0));
		w /= (w.x + w.y + w.z);
		vec3 rx = texture(rock_tex, v_world.zy * rock_scale).rgb;
		vec3 ry = texture(rock_tex, v_world.xz * rock_scale).rgb;
		vec3 rz = texture(rock_tex, v_world.xy * rock_scale).rgb;
		vec3 rock = (rx * w.x + ry * w.y + rz * w.z) * rock_tint;
		vec3 rnx = texture(rock_nrm, v_world.zy * rock_scale).rgb * 2.0 - 1.0;
		vec3 rnz = texture(rock_nrm, v_world.xy * rock_scale).rgb * 2.0 - 1.0;
		rn = vec3(0.0, rnx.y, rnx.x) * w.x + vec3(rnz.x, rnz.y, 0.0) * w.z;
		col = mix(col, rock, rockiness);
	}
	// Snow caps on the mountains, settling on flatter faces.
	float snow = smoothstep(snow_height, snow_height + 14.0, v_world.y + macro * 10.0) * smoothstep(0.12, 0.45, n.y);
	if (snow > 0.001) {
		col = mix(col, texture(snow_tex, p * 0.15).rgb * vec3(0.7, 0.76, 0.88), snow);
	}

	vec3 nw = normalize(n + mix(gn * 0.6, rn * 0.9, rockiness) * (1.0 - snow * 0.7));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	float depth = water_level - v_world.y;
	col = mix(col, underwater, smoothstep(0.0, 2.5, depth));

	ALBEDO = col * brightness;
	ROUGHNESS = mix(0.95, 0.6, max(v_mask.b, snow * 0.6));
	SPECULAR = 0.25 + snow * 0.2;
}
