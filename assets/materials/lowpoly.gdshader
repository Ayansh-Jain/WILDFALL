shader_type spatial;
// Shared material for vertex-coloured low-poly props (trees, rocks, ruins, cave, banners).
// UV.x = wind sway weight. MultiMesh instance colours arrive multiplied into COLOR.

uniform vec3 tint : source_color = vec3(1.0);
uniform float wind_strength = 0.0;
uniform float wind_speed = 1.2;
uniform vec2 wind_dir = vec2(0.85, 0.52);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;
uniform float world_variation : hint_range(0.0, 1.0) = 0.18;

varying vec3 v_color;
varying vec3 v_world;

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = UV.x;
	if (wind_strength > 0.0 && sway > 0.0) {
		vec2 wdir = normalize(wind_dir + vec2(0.0001, 0.0));
		float ph = wp.x * 0.12 + wp.z * 0.08;
		float t = TIME * wind_speed;
		float wave = sin(t * 1.4 + ph) + 0.4 * sin(t * 3.2 + ph * 2.0);
		vec2 perp = vec2(-wdir.y, wdir.x);
		vec2 off = (wdir * (0.45 + 0.55 * wave) + perp * cos(t * 1.1 + ph * 1.3) * 0.35) * wind_strength * sway;
		VERTEX.xz += off;
	}
	v_color = COLOR.rgb;
	v_world = wp;
}

void fragment() {
	float n = hash31(floor(v_world * 0.35));
	vec3 col = v_color * tint * (1.0 + (n - 0.5) * world_variation);
	ALBEDO = col;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.2;
}
