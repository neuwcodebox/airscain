shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.28, 0.03);
varying float age;

void vertex() {
	age = INSTANCE_CUSTOM.y;
}

void fragment() {
	float heat = 1.0 - smoothstep(0.12, 0.72, age);
	float fade = 1.0 - smoothstep(0.78, 1.0, age);
	float facet = mix(0.72, 1.0, abs(NORMAL.y));
	vec3 cooled_metal = vec3(0.07, 0.045, 0.035);
	vec3 hot_metal = mix(vec3(1.0, 0.42, 0.035), tint, 0.25);
	ALBEDO = mix(cooled_metal, hot_metal, heat) * facet;
	EMISSION = hot_metal * heat * heat * 7.0;
	ALPHA = fade;
}
