shader_type spatial;
// Same as glow.gdshader but ignores fog, so beacon lights on the central
// landmark stay readable from distant viewpoints.

render_mode diffuse_lambert, specular_disabled, fog_disabled;

uniform vec3 glow_color : source_color = vec3(1.0, 0.7, 0.35);
uniform float energy = 2.5;
uniform float pulse_speed = 0.8;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.2;

varying vec3 v_color;
varying float v_phase;

void vertex() {
	v_color = COLOR.rgb;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_phase = wp.x * 0.37 + wp.z * 0.21;
}

void fragment() {
	float p = 1.0 - pulse_amount * (0.5 + 0.5 * sin(TIME * pulse_speed + v_phase));
	vec3 c = glow_color * v_color;
	ALBEDO = c * 0.25;
	EMISSION = c * energy * p;
}
