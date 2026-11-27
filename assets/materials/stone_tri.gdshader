shader_type spatial;
// Triplanar photo-textured stone/rock with normal map and moss on upward faces.
// Used for boulders, ruins, bridges and the cave. COLOR (vertex colour x
// instance colour) still tints, so existing per-block variation survives.

uniform sampler2D stone_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.45;
uniform float normal_strength = 0.9;
uniform vec3 moss_color : source_color = vec3(0.16, 0.24, 0.1);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.35;
uniform float tint_strength : hint_range(0.0, 1.0) = 0.6;
uniform float brightness = 1.0;
uniform float saturation : hint_range(0.0, 1.5) = 1.0;
// Object-space mapping for moving things (e.g. view models); world space otherwise.
uniform bool object_space = false;
// Optional separate texture for upward faces (floors, stair treads, wall tops).
uniform bool use_top_tex = false;
uniform sampler2D top_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D top_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float top_scale = 0.3;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
// Large-scale tonal variation that hides texture repetition on big surfaces.
uniform float macro_strength : hint_range(0.0, 1.0) = 0.0;
uniform float macro_scale = 0.11;
// Blends a second, larger and offset sampling of the wall texture to break up tiling.
uniform float second_scale_mix : hint_range(0.0, 1.0) = 0.0;
uniform float macro_hue : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_pos;
varying vec3 v_n;
varying vec3 v_wn;
varying vec3 v_col;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash(i);
	float n100 = hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (object_space) {
		v_pos = VERTEX;
		v_n = NORMAL;
	} else {
		v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		v_n = v_wn;
	}
	v_col = COLOR.rgb;
}

void fragment() {
	vec3 w = pow(abs(v_n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec2 px = v_pos.zy * scale;
	vec2 py = v_pos.xz * scale;
	vec2 pz = v_pos.xy * scale;
	vec3 cy;
	vec3 ny;
	if (use_top_tex && v_n.y > 0.0) {
		vec2 pt = v_pos.xz * top_scale;
		cy = texture(top_tex, pt).rgb;
		ny = texture(top_nrm, pt).rgb * 2.0 - 1.0;
	} else {
		cy = texture(stone_tex, py).rgb;
		ny = texture(stone_nrm, py).rgb * 2.0 - 1.0;
	}
	vec3 c = texture(stone_tex, px).rgb * w.x + cy * w.y + texture(stone_tex, pz).rgb * w.z;
	if (second_scale_mix > 0.0) {
		float s2 = 0.41;
		vec3 c2 = texture(stone_tex, px * s2 + vec2(0.37, 0.19)).rgb * w.x + cy * w.y + texture(stone_tex, pz * s2 + vec2(0.71, 0.53)).rgb * w.z;
		c = mix(c, c2, second_scale_mix);
	}
	vec3 nx = texture(stone_nrm, px).rgb * 2.0 - 1.0;
	vec3 nz = texture(stone_nrm, pz).rgb * 2.0 - 1.0;
	vec3 pert = vec3(0.0, nx.y, nx.x) * w.x + vec3(ny.x, 0.0, ny.y) * w.y + vec3(nz.x, nz.y, 0.0) * w.z;
	vec3 nn = normalize(v_n + pert * normal_strength);
	if (object_space) {
		nn = normalize((MODEL_MATRIX * vec4(nn, 0.0)).xyz);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(nn, 0.0)).xyz);
	vec3 tint = mix(vec3(1.0), v_col / max(max(v_col.r, max(v_col.g, v_col.b)), 0.001) * 0.8 + 0.2, tint_strength);
	float lum_tint = dot(v_col, vec3(0.33)) * 2.2;
	c *= tint * clamp(lum_tint, 0.55, 1.25);
	float moss = smoothstep(0.55, 0.9, v_wn.y + (hash(floor(v_pos * 2.0)) - 0.5) * 0.25) * moss_amount;
	c = mix(c, moss_color * (0.7 + 0.6 * c.g), moss);
	c = mix(vec3(dot(c, vec3(0.3, 0.59, 0.11))), c, saturation);
	if (macro_strength > 0.0) {
		float m = value_noise(v_pos * macro_scale) * 0.65 + value_noise(v_pos * macro_scale * 3.1) * 0.35;
		c *= 1.0 + (m - 0.5) * 2.0 * macro_strength;
		if (macro_hue > 0.0) {
			float hv = value_noise(v_pos * macro_scale * 0.7 + vec3(17.3, 5.1, 9.7));
			c *= mix(vec3(1.0), mix(vec3(1.06, 1.0, 0.9), vec3(0.93, 0.98, 1.06), hv), macro_hue);
		}
	}
	ALBEDO = c * brightness;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.25;
}
