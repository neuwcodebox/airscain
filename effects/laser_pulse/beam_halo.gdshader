shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float intensity : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, VERTEX.y, 0.0, 1.0)).xyz;
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 sight = normalize(INV_VIEW_MATRIX[3].xyz - center);
	vec3 right = normalize(cross(axis, sight) + vec3(0.00001));
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(center + right * VERTEX.x, 1.0);
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float halo = exp(-across * across * 7.0) * (1.0 - smoothstep(0.7, 1.0, across));
	float ends = smoothstep(0.0, 0.04, UV.y) * smoothstep(0.0, 0.04, 1.0 - UV.y);
	ALBEDO = vec3(0.08, 0.55, 0.8) * intensity;
	EMISSION = vec3(0.03, 0.4, 0.85) * intensity * 2.0;
	ALPHA = halo * ends * intensity * 0.24;
}
