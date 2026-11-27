shader_type spatial;
// Alpha-cut foliage cards (leaf clusters, pine sprays, grass, ferns).
// UV = card texture, UV2.x = wind sway weight, COLOR = vertex tint x MultiMesh
// instance colour. Supports traveling global wind waves and sunlit translucency.

render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D card_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.45;
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.3;
uniform vec2 wind_dir = vec2(0.85, 0.52);
uniform float gust_strength = 0.35;
uniform float translucency : hint_range(0.0, 1.0) = 0.25;
uniform vec3 sun_dir = vec3(0.4, 0.5, 0.4);
uniform vec3 sun_color : source_color = vec3(1.0, 0.90, 0.74);
// Distance fade (0 = off) for ground clutter: dithered out between start and end.
uniform float fade_start = 0.0;
uniform float fade_end = 0.0;

varying vec3 v_color;
varying vec3 v_world;
varying float v_dist;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

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
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = UV2.x;
	if (sway > 0.0) {
		vec2 wdir = normalize(wind_dir + vec2(0.0001, 0.0));
		float t = TIME * wind_speed;
		// Traveling gust wave across the landscape.
		float gust_wave = vnoise(wp.xz * 0.055 - wdir * t * 0.85);
		float gust = smoothstep(0.32, 0.88, gust_wave) * gust_strength;
		float ph = wp.x * 0.14 + wp.z * 0.10;
		float flutter = sin(t * 1.5 + ph) + 0.38 * sin(t * 3.8 + ph * 2.1);
		vec2 perp = vec2(-wdir.y, wdir.x);
		vec2 off = (wdir * (0.55 + gust * 2.1 + flutter * 0.45) + perp * (cos(t * 1.2 + ph * 1.3) * 0.38)) * wind_strength * sway;
		VERTEX.xz += off;
		VERTEX.y -= length(off) * 0.22 * sway;
	}
	v_color = COLOR.rgb;
	v_world = wp;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec4 tex = texture(card_tex, UV);
	float cut = alpha_cut;
	float alpha = tex.a;
	if (fade_end > 0.0) {
		float f = smoothstep(fade_start, fade_end, v_dist);
		cut = mix(alpha_cut, 1.01, f * (0.6 + 0.4 * hash(FRAGCOORD.xy)));
	} else {
		// Compensate mipmap alpha thinning on distant tree canopies so far LODs stay lush.
		float dist_t = clamp((v_dist - 24.0) / 85.0, 0.0, 1.0);
		alpha *= mix(1.0, 1.85, dist_t);
		cut = mix(alpha_cut, 0.16, dist_t);
	}
	if (alpha < cut) {
		discard;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 col = tex.rgb * tint * v_color;
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_world);
	float back = pow(max(dot(-v, normalize(sun_dir)), 0.0), 3.0);
	ALBEDO = col;
	EMISSION = col * translucency * (0.07 + back * 0.28) * sun_color;
	ROUGHNESS = 0.88;
	SPECULAR = 0.10;
}
