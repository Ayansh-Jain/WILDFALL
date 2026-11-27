shader_type spatial;
// Castle furniture and fittings. COLOR.rgb is the authored mean colour; COLOR.a
// selects the surface (see Sites.SURF_*): above 0.65 plain, 0.1 wood grain,
// 0.2 dark planks, 0.3 linen/wool, 0.4 forged iron, 0.5 dressed stone, 0.6
// rubble stone. Textures
// are triplanar in world space and only add detail around the authored colour.

uniform sampler2D wood_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D plank_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plank_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloth_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloth_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rubble_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rubble_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wood_scale = 0.9;
uniform float plank_scale = 0.45;
uniform float cloth_scale = 2.2;
uniform float stone_scale = 0.36;
uniform float detail_strength : hint_range(0.0, 1.5) = 0.85;
uniform float normal_strength = 0.8;

varying vec3 v_pos;
varying vec3 v_wn;
varying vec4 v_col;

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = COLOR;
}

vec3 tri_albedo(sampler2D tex, vec3 w, float s) {
	return texture(tex, v_pos.zy * s).rgb * w.x + texture(tex, v_pos.xz * s).rgb * w.y + texture(tex, v_pos.xy * s).rgb * w.z;
}

vec3 tri_normal(sampler2D nrm, vec3 w, float s) {
	vec3 nx = texture(nrm, v_pos.zy * s).rgb * 2.0 - 1.0;
	vec3 ny = texture(nrm, v_pos.xz * s).rgb * 2.0 - 1.0;
	vec3 nz = texture(nrm, v_pos.xy * s).rgb * 2.0 - 1.0;
	return vec3(0.0, nx.y, nx.x) * w.x + vec3(ny.x, 0.0, ny.y) * w.y + vec3(nz.x, nz.y, 0.0) * w.z;
}

void fragment() {
	int surf = v_col.a > 0.65 ? 0 : int(round(v_col.a * 10.0));
	vec3 base = v_col.rgb;
	vec3 w = pow(abs(v_wn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 col = base;
	vec3 pert = vec3(0.0);
	float rough = 0.9;
	float metal = 0.0;
	float spec = 0.25;
	if (surf == 1 || surf == 2 || surf == 3 || surf == 5 || surf == 6) {
		vec3 t;
		vec3 avg;
		if (surf == 1) {
			t = tri_albedo(wood_tex, w, wood_scale);
			avg = textureLod(wood_tex, vec2(0.5), 12.0).rgb;
			pert = tri_normal(wood_nrm, w, wood_scale);
			rough = 0.72;
		} else if (surf == 2) {
			t = tri_albedo(plank_tex, w, plank_scale);
			avg = textureLod(plank_tex, vec2(0.5), 12.0).rgb;
			pert = tri_normal(plank_nrm, w, plank_scale);
			rough = 0.8;
		} else if (surf == 3) {
			t = tri_albedo(cloth_tex, w, cloth_scale);
			avg = textureLod(cloth_tex, vec2(0.5), 12.0).rgb;
			pert = tri_normal(cloth_nrm, w, cloth_scale) * 0.6;
			rough = 0.98;
			spec = 0.12;
		} else if (surf == 6) {
			t = tri_albedo(rubble_tex, w, 0.42);
			avg = textureLod(rubble_tex, vec2(0.5), 12.0).rgb;
			pert = tri_normal(rubble_nrm, w, 0.42);
			rough = 0.9;
		} else {
			t = tri_albedo(stone_tex, w, stone_scale);
			avg = textureLod(stone_tex, vec2(0.5), 12.0).rgb;
			pert = tri_normal(stone_nrm, w, stone_scale);
			rough = 0.85;
		}
		float lum_t = dot(t, vec3(0.299, 0.587, 0.114));
		float lum_a = max(dot(avg, vec3(0.299, 0.587, 0.114)), 0.03);
		col = base * mix(1.0, clamp(lum_t / lum_a, 0.5, 1.8), detail_strength);
	} else if (surf == 4) {
		float n = hash31(floor(v_pos * 9.0));
		col = base * (0.85 + 0.3 * n);
		rough = 0.5 + 0.2 * n;
		metal = 0.4;
		spec = 0.4;
	} else {
		float n = hash31(floor(v_pos * 0.35));
		col = base * (1.0 + (n - 0.5) * 0.12);
	}
	vec3 nn = normalize(v_wn + pert * normal_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(nn, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
}
