shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.28, 0.03);
varying float age;

void vertex() {
	age = INSTANCE_CUSTOM.y;
}

void fragment() {
	float hot_tip = smoothstep(0.18, 0.82, UV.y);
	float fade = 1.0 - smoothstep(0.72, 1.0, age);
	vec3 dark_body = vec3(0.055, 0.035, 0.025);
	vec3 hot = mix(vec3(1.0, 0.22, 0.015), tint, 0.35);
	ALBEDO = mix(dark_body, hot, hot_tip * (1.0 - age * 0.7));
	EMISSION = hot * hot_tip * fade * 9.0;
	ALPHA = fade;
}
