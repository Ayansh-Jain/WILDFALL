shader_type spatial;
// Alpha-cut foliage cards (leaf clusters, pine sprays, grass, ferns).
// UV = card texture, UV2.x = wind sway weight, COLOR = vertex tint x MultiMesh
// instance colour. Normals are authored to point out of the canopy, so both
// faces keep them (no back-face flip) for soft, volumetric lighting.

render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D card_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.45;
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.2;
uniform float translucency : hint_range(0.0, 1.0) = 0.25;
// Distance fade (0 = off) for ground clutter: dithered out between start and end.
uniform float fade_start = 0.0;
uniform float fade_end = 0.0;

varying vec3 v_color;
varying float v_dist;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = UV2.x;
	if (sway > 0.0) {
		float ph = wp.x * 0.13 + wp.z * 0.09;
		float t = TIME * wind_speed;
		vec2 off = vec2(sin(t * 1.3 + ph) + 0.35 * sin(t * 3.7 + ph * 2.3),
				cos(t * 1.1 + ph * 1.4) * 0.6) * wind_strength * sway;
		VERTEX.xz += off;
		VERTEX.y += sin(t * 2.1 + ph * 3.0) * wind_strength * 0.2 * sway;
	}
	v_color = COLOR.rgb;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec4 tex = texture(card_tex, UV);
	float cut = alpha_cut;
	if (fade_end > 0.0) {
		float f = smoothstep(fade_start, fade_end, v_dist);
		cut = mix(alpha_cut, 1.01, f * (0.6 + 0.4 * hash(FRAGCOORD.xy)));
	}
	if (tex.a < cut) {
		discard;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;  // undo the engine's back-face flip
	}
	vec3 col = tex.rgb * tint * v_color;
	ALBEDO = col;
	// Cheap translucency: leaves keep some colour even facing away from the moon.
	EMISSION = col * translucency * 0.08;
	ROUGHNESS = 0.9;
	SPECULAR = 0.08;
}
