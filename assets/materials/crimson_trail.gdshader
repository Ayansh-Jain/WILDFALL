shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, shadows_disabled, depth_draw_never;
void fragment() {
 float edge = smoothstep(0.15,0.55,UV.y) * (1.0-smoothstep(0.94,1.0,UV.y));
 float core = exp(-pow((UV.y-0.84)*18.0,2.0));
 float streak = 0.88+0.12*sin(UV.x*45.0-TIME*55.0);
 vec3 flame = mix(vec3(0.65,0.005,0.015),vec3(1.0,0.14,0.025),UV.y);
 ALBEDO = mix(flame,vec3(1.0,0.82,0.7),core);
 EMISSION = ALBEDO*0.7;
 ALPHA = COLOR.a*edge*streak;
}
