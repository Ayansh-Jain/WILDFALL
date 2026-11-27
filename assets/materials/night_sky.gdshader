shader_type sky;
// Atmospheric sky dome: supports golden daytime sun + Mie scatter halo,
// dramatic sunset/evening gradients, and star-filled moonlit nights.
// Celestial disc follows LIGHT0_DIRECTION so shadows match sky lighting.

uniform vec3 zenith_color : source_color = vec3(0.11, 0.30, 0.62);
uniform vec3 horizon_color : source_color = vec3(0.68, 0.74, 0.80);
uniform vec3 ground_color : source_color = vec3(0.22, 0.23, 0.21);
uniform vec3 celestial_color : source_color = vec3(1.0, 0.92, 0.74);
uniform vec3 cloud_dark : source_color = vec3(0.24, 0.30, 0.40);
uniform vec3 cloud_lit : source_color = vec3(0.98, 0.92, 0.82);
uniform float moon_size = 0.99975;
uniform float star_amount : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.56;
uniform float cloud_speed = 0.0024;
uniform float daylight_factor : hint_range(0.0, 1.0) = 1.0;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.85;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += noise2(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, zenith_color, smoothstep(-0.02, 0.58, h));
	// Soft horizon haze band for atmospheric depth.
	float haze_band = pow(1.0 - clamp(abs(h), 0.0, 1.0), 6.0);
	col = mix(col, horizon_color * 1.06, haze_band * 0.35);
	col = mix(col, ground_color, smoothstep(0.0, -0.24, h));

	float md = 0.0;
	if (LIGHT0_ENABLED) {
		md = max(dot(d, LIGHT0_DIRECTION), 0.0);
		float halo_broad = pow(md, 5.0) * (0.14 + 0.18 * daylight_factor) * sun_glow;
		float halo_tight = pow(md, 42.0) * (0.18 + 0.28 * daylight_factor) * sun_glow;
		col += celestial_color * (halo_broad + halo_tight);
	}

	float clouds = 0.0;
	float cloud_dens = 0.0;
	if (h > -0.05) {
		vec2 uv = d.xz / (max(h, 0.0) + 0.24) * 0.85;
		uv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.38);
		float n = fbm(uv * 1.25);
		float n2 = noise2(uv * 3.1 - vec2(TIME * cloud_speed * 0.6, 0.0));
		cloud_dens = n * 0.78 + n2 * 0.22;
		float cloud_threshold = 0.56 - cloud_cover * 0.34;
		clouds = smoothstep(cloud_threshold, cloud_threshold + 0.24, cloud_dens) * smoothstep(-0.02, 0.22, h);
	}

	if (h > 0.0 && star_amount > 0.005) {
		vec3 cell = floor(d * 260.0);
		float s = hash3(cell);
		float star = step(1.0 - 0.004 * star_amount * 4.0, s);
		float twinkle = 0.6 + 0.4 * sin(TIME * (1.5 + s * 3.0) + s * 40.0);
		col += vec3(0.82, 0.87, 1.0) * star * twinkle * smoothstep(0.05, 0.35, h) * 0.9 * (1.0 - clouds);
	}

	if (LIGHT0_ENABLED) {
		float disc = smoothstep(moon_size, moon_size + 0.00018, md);
		float maria = noise2(vec2(d.x, d.y) * 900.0) * 0.25 + noise2(vec2(d.z, d.y) * 300.0) * 0.2;
		float disc_boost = mix(2.4 - maria, 3.6, daylight_factor);
		col += celestial_color * disc * disc_boost * (1.0 - clouds * 0.82);
	}

	float lit = pow(md, mix(4.0, 2.2, daylight_factor));
	float silver_lining = pow(md, 14.0) * (1.0 - smoothstep(0.55, 0.85, cloud_dens)) * daylight_factor;
	vec3 ccol = mix(cloud_dark, cloud_lit, 0.24 + lit * 0.76) + celestial_color * silver_lining * 0.45;
	col = mix(col, ccol, clouds * 0.82);

	COLOR = col;
}
