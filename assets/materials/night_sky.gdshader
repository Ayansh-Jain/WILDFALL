shader_type sky;
// Night sky: blue-grey horizon, stars, drifting moonlit clouds, and a moon
// drawn along the first directional light so the disc always matches shadows.

uniform vec3 zenith_color : source_color = vec3(0.025, 0.045, 0.1);
uniform vec3 horizon_color : source_color = vec3(0.2, 0.26, 0.36);
uniform vec3 ground_color : source_color = vec3(0.06, 0.07, 0.09);
uniform vec3 moon_color : source_color = vec3(0.95, 0.97, 1.0);
uniform vec3 cloud_dark : source_color = vec3(0.06, 0.08, 0.13);
uniform vec3 cloud_lit : source_color = vec3(0.42, 0.48, 0.6);
uniform float moon_size = 0.99955;
uniform float star_amount : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.58;
uniform float cloud_speed = 0.004;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Sine-free hash: stays stable at large coordinates (no precision banding).
float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += noise2(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, zenith_color, smoothstep(-0.02, 0.6, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.25, h));

	float md = 0.0;
	if (LIGHT0_ENABLED) {
		md = dot(d, LIGHT0_DIRECTION);
		// Wide soft glow around the moon, brightening the sky near it.
		col += moon_color * (pow(max(md, 0.0), 8.0) * 0.07 + pow(max(md, 0.0), 64.0) * 0.12);
	}

	float clouds = 0.0;
	if (h > -0.05) {
		vec2 uv = d.xz / (max(h, 0.0) + 0.25) * 0.8;
		uv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		float n = fbm(uv * 1.3);
		clouds = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.5, n) * smoothstep(-0.02, 0.2, h);
	}

	if (h > 0.0) {
		vec3 cell = floor(d * 260.0);
		float s = hash3(cell);
		float star = step(1.0 - 0.004 * star_amount * 4.0, s);
		float twinkle = 0.6 + 0.4 * sin(TIME * (1.5 + s * 3.0) + s * 40.0);
		col += vec3(0.8, 0.85, 1.0) * star * twinkle * smoothstep(0.05, 0.35, h) * 0.9 * (1.0 - clouds);
	}

	if (LIGHT0_ENABLED) {
		float disc = smoothstep(moon_size, moon_size + 0.00015, md);
		float maria = noise2(vec2(d.x, d.y) * 900.0) * 0.25 + noise2(vec2(d.z, d.y) * 300.0) * 0.2;
		col += moon_color * disc * (2.4 - maria) * (1.0 - clouds * 0.85);
	}

	// Clouds lit from the moon side, darker away from it.
	float lit = pow(max(md, 0.0), 4.0);
	vec3 ccol = mix(cloud_dark, cloud_lit, 0.25 + lit * 0.75);
	col = mix(col, ccol, clouds * 0.85);
	COLOR = col;
}
