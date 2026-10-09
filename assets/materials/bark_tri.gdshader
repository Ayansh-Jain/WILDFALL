shader_type spatial;
// Triplanar bark for procedural trunks and branches (no UVs needed).
// COLOR.rgb tints; COLOR.a < 0.5 switches to pale birch bark with dark marks.

uniform sampler2D bark_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.9;
uniform float brightness = 1.0;

varying vec3 v_pos;
varying vec3 v_n;
varying vec4 v_col;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = COLOR;
}

void fragment() {
	vec3 w = pow(abs(v_n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	// Stretch vertically so bark grain runs along the trunk.
	vec2 px = vec2(v_pos.z, v_pos.y * 0.5) * scale;
	vec2 py = v_pos.xz * scale;
	vec2 pz = vec2(v_pos.x, v_pos.y * 0.5) * scale;
	vec3 c = texture(bark_tex, px).rgb * w.x + texture(bark_tex, py).rgb * w.y + texture(bark_tex, pz).rgb * w.z;
	vec3 nx = texture(bark_nrm, px).rgb * 2.0 - 1.0;
	vec3 nz = texture(bark_nrm, pz).rgb * 2.0 - 1.0;
	vec3 nw = normalize(v_n + (vec3(0.0, nx.y, nx.x) * w.x + vec3(nz.x, nz.y, 0.0) * w.z) * 0.8);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	if (v_col.a < 0.5) {
		float lum = dot(c, vec3(0.3, 0.59, 0.11));
		float marks = smoothstep(0.32, 0.18, lum);
		c = mix(vec3(0.5, 0.49, 0.45) * (0.8 + lum * 0.5), vec3(0.06, 0.05, 0.05), marks);
	} else {
		c *= v_col.rgb;
	}
	ALBEDO = c * brightness;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
