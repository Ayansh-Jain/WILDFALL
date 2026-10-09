shader_type sky;
// Night sky: blue-grey horizon, stars, and a moon drawn along the first
// directional light so the disc always matches the shadows.

uniform vec3 zenith_color : source_color = vec3(0.02, 0.04, 0.09);
uniform vec3 horizon_color : source_color = vec3(0.16, 0.21, 0.29);
uniform vec3 ground_color : source_color = vec3(0.05, 0.06, 0.08);
uniform vec3 moon_color : source_color = vec3(0.92, 0.95, 1.0);
uniform float moon_size = 0.99975;
uniform float star_amount : hint_range(0.0, 1.0) = 0.35;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, zenith_color, smoothstep(-0.02, 0.55, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.25, h));

	if (LIGHT0_ENABLED) {
		float md = dot(d, LIGHT0_DIRECTION);
		float disc = smoothstep(moon_size, moon_size + 0.0002, md);
		float halo = pow(max(md, 0.0), 220.0) * 0.5 + pow(max(md, 0.0), 12.0) * 0.06;
		col += moon_color * (disc * 2.2 + halo);
	}

	if (h > 0.0) {
		vec3 cell = floor(d * 260.0);
		float s = hash3(cell);
		float star = step(1.0 - 0.004 * star_amount * 4.0, s);
		float twinkle = 0.6 + 0.4 * sin(TIME * (1.5 + s * 3.0) + s * 40.0);
		col += vec3(0.8, 0.85, 1.0) * star * twinkle * smoothstep(0.05, 0.35, h) * 0.9;
	}
	COLOR = col;
}
