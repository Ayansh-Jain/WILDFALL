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

varying vec3 v_pos;
varying vec3 v_n;
varying vec3 v_wn;
varying vec3 v_col;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
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
	vec3 c = texture(stone_tex, px).rgb * w.x + texture(stone_tex, py).rgb * w.y + texture(stone_tex, pz).rgb * w.z;
	vec3 nx = texture(stone_nrm, px).rgb * 2.0 - 1.0;
	vec3 ny = texture(stone_nrm, py).rgb * 2.0 - 1.0;
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
	ALBEDO = c * brightness;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
