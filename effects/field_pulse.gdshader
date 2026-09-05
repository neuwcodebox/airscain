shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.5);
	float bands = pow(0.5 + 0.5 * sin(UV.y * 55.0 - progress * 22.0), 10.0);
	float fade = pow(1.0 - progress, 1.6);
	ALBEDO = vec3(0.32, 0.49, 0.8) * fade;
	EMISSION = vec3(0.16, 0.32, 0.9) * fade * 1.5;
	ALPHA = (rim * 0.32 + bands * 0.08) * fade;
}
