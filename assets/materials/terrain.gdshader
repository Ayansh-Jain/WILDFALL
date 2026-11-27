shader_type spatial;
// Layered PBR terrain shader (Compatibility GL 3.3 safe).
// Vertex colour masks: r = trail/road, g = forest floor, b = wet riverbank, a = paving.
// Blends sage-green & golden-amber meadows, worn gravel trails, wet mud/pebbles,
// stratified triplanar cliff rock with mossy ledges, and mountain snow.

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

uniform vec3 grass_tint : source_color = vec3(0.48, 0.64, 0.36);
uniform vec3 meadow_gold_tint : source_color = vec3(0.76, 0.67, 0.35);
uniform vec3 forest_tint : source_color = vec3(0.54, 0.52, 0.42);
uniform vec3 rock_tint : source_color = vec3(0.62, 0.65, 0.70);
uniform vec3 moss_tint : source_color = vec3(0.28, 0.39, 0.19);
uniform float grass_scale = 0.24;
uniform float trail_scale = 0.32;
uniform float rock_scale = 0.085;
uniform float snow_height = 56.0;
uniform float brightness = 0.92;
uniform float water_level = 0.0;
uniform vec3 underwater : source_color = vec3(0.04, 0.11, 0.12);

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec4 v_mask;
varying float v_cam_dist;

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

// Two-scale sample: detail tiling blended with a rotated macro tiling.
vec3 tex2(sampler2D t, vec2 p, float s) {
	vec3 a = texture(t, p * s).rgb;
	vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * s * 0.27;
	vec3 b = texture(t, q).rgb;
	return mix(a, b, 0.42);
}

vec3 nrm_xz(sampler2D t, vec2 p, float s) {
	vec3 n = texture(t, p * s).rgb * 2.0 - 1.0;
	return vec3(n.x, n.z, -n.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_mask = COLOR;
	v_cam_dist = length(CAMERA_POSITION_WORLD - v_world);
}

void fragment() {
	vec2 p = v_world.xz;
	vec3 n = normalize(v_wnormal);
	float macro = vnoise(p * 0.022);
	float meadow_gold = smoothstep(0.36, 0.72, vnoise(p * 0.015 + vec2(19.4, 7.1)));
	float patch = vnoise(p * 0.11);
	float micro = vnoise(p * 0.42);
	float nrm_fade = 1.0 - smoothstep(28.0, 130.0, v_cam_dist);

	// 1. Meadow grass: rich sage-green shifting into warm golden-amber drifts.
	vec3 grass_base = tex2(grass_tex, p, grass_scale);
	vec3 biome_tint = mix(grass_tint, meadow_gold_tint, meadow_gold * (1.0 - v_mask.g * 0.8));
	vec3 grass = grass_base * biome_tint * (0.82 + 0.34 * macro) * (0.92 + 0.16 * micro);
	vec3 col = grass;
	float rough = 0.94;
	float spec = 0.16;

	// 2. Forest floor (pine needles, leaf litter, dappled shade tone).
	float forest_w = clamp(v_mask.g * 1.25 + (patch - 0.5) * 0.28, 0.0, 1.0);
	if (forest_w > 0.01) {
		vec3 fcol = tex2(forest_tex, p, grass_scale * 0.78) * forest_tint * (0.85 + 0.25 * macro);
		col = mix(col, fcol, forest_w);
	}
	vec3 gn = nrm_xz(grass_nrm, p, grass_scale);

	// 3. Worn horseback trails & gravel shoulders.
	float trail_noise = (patch - 0.5) * 0.28 + (micro - 0.5) * 0.12;
	float trail_shoulder = smoothstep(0.05, 0.42, v_mask.r + trail_noise);
	float trail_core = smoothstep(0.35, 0.78, v_mask.r + trail_noise * 0.5);
	if (trail_shoulder > 0.001) {
		vec3 raw_trail = tex2(trail_tex, p, trail_scale);
		vec3 shoulder_col = raw_trail * vec3(0.62, 0.58, 0.48) * (0.88 + 0.22 * macro);
		vec3 core_col = raw_trail * vec3(0.50, 0.44, 0.38) * (0.9 + 0.2 * micro);
		col = mix(col, shoulder_col, trail_shoulder * 0.65);
		col = mix(col, core_col, trail_core);
		gn = mix(gn, nrm_xz(trail_nrm, p, trail_scale), trail_shoulder);
		rough = mix(rough, 0.86, trail_core);
	}

	// 4. Cobblestone paving in castle/village yards.
	float pave = smoothstep(0.22, 0.62, v_mask.a + (patch - 0.5) * 0.35);
	if (pave > 0.001) {
		vec3 pv = tex2(paving_tex, p, 0.36);
		pv = mix(vec3(dot(pv, vec3(0.33))), pv, 0.32) * vec3(0.64, 0.63, 0.62);
		col = mix(col, pv, pave);
		rough = mix(rough, 0.76, pave);
		spec = mix(spec, 0.28, pave);
	}

	// 5. Wet riverbank mud, damp pebbles & moss.
	if (v_mask.b > 0.001) {
		float wet_w = clamp(v_mask.b, 0.0, 1.0);
		vec3 mud = tex2(mud_tex, p, 0.32) * 0.76;
		vec3 pebble_mix = tex2(trail_tex, p, 0.48) * vec3(0.45, 0.44, 0.40);
		vec3 bank = mix(pebble_mix, mud, smoothstep(0.25, 0.8, wet_w));
		col = mix(col, bank, wet_w);
		rough = mix(rough, 0.36, wet_w * 0.85);
		spec = mix(spec, 0.44, wet_w * 0.8);
	}

	// 6. Stratified triplanar cliff rock & mossy rock shelves.
	float slope = 1.0 - n.y;
	float rockiness = smoothstep(0.16, 0.31, slope + (patch - 0.5) * 0.11);
	rockiness = max(rockiness, smoothstep(38.0, 50.0, v_world.y + macro * 8.0));
	vec3 rn = vec3(0.0);
	if (rockiness > 0.001) {
		vec3 w = pow(abs(n), vec3(4.0));
		w /= (w.x + w.y + w.z);
		vec3 rx = texture(rock_tex, v_world.zy * rock_scale).rgb;
		vec3 ry = texture(rock_tex, v_world.xz * rock_scale).rgb;
		vec3 rz = texture(rock_tex, v_world.xy * rock_scale).rgb;
		vec3 rock = (rx * w.x + ry * w.y + rz * w.z) * rock_tint;
		// Subtle horizontal geological strata + macro color shift.
		float strata = 0.88 + 0.22 * vnoise(vec2(v_world.y * 0.42 + macro * 1.4, p.x * 0.03));
		rock *= strata * mix(vec3(0.95, 0.94, 0.92), vec3(1.04, 1.01, 0.96), macro);
		// Moss settles on gentler rock ledges below the snowline.
		float ledge_moss = smoothstep(0.45, 0.82, n.y) * (1.0 - smoothstep(26.0, 42.0, v_world.y)) * smoothstep(0.42, 0.72, patch);
		rock = mix(rock, moss_tint * (0.75 + 0.5 * rock.g), ledge_moss * 0.7);

		vec3 rnx = texture(rock_nrm, v_world.zy * rock_scale).rgb * 2.0 - 1.0;
		vec3 rnz = texture(rock_nrm, v_world.xy * rock_scale).rgb * 2.0 - 1.0;
		rn = vec3(0.0, rnx.y, rnx.x) * w.x + vec3(rnz.x, rnz.y, 0.0) * w.z;
		col = mix(col, rock, rockiness);
		rough = mix(rough, 0.86, rockiness);
	}

	// 7. Mountain snow caps on high elevations and flatter ridges.
	float snow = smoothstep(snow_height, snow_height + 16.0, v_world.y + macro * 10.0) * smoothstep(0.14, 0.48, n.y);
	if (snow > 0.001) {
		vec3 snow_col = texture(snow_tex, p * 0.14).rgb * vec3(0.78, 0.82, 0.90);
		col = mix(col, snow_col, snow);
		rough = mix(rough, 0.56, snow);
		spec = mix(spec, 0.42, snow);
	}

	vec3 nw = normalize(n + mix(gn * 0.65, rn * 0.95, rockiness) * (1.0 - snow * 0.7) * nrm_fade);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	float depth = water_level - v_world.y;
	col = mix(col, underwater, smoothstep(0.0, 2.2, depth));

	ALBEDO = col * brightness;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
